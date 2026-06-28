///|
/// Internal: allocate a new ReachableDerived cell in the SoA and return the typed handle.
fn[T : Eq] ReachableDerived::_create(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
) -> ReachableDerived[T] {
  let memo_idx = rt.pull.free_memos.pop().unwrap_or(rt.pull.memos.length())
  let cell_id = rt.alloc_cell_id(HybridMemo(memo_idx))
  let derived : ReachableDerived[T] = {
    label,
    rt,
    cell_id,
    compute,
    value: None,
  }
  let new_data : MemoData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.HashSet([]),
      push_reachable_count: 0,
    },
    compute: () => derived.recompute_inner(),
    verified_at: Revision::initial(),
    dependencies: [],
    in_progress: false,
    on_change: None,
    is_hybrid: true,
    accumulator_reads: @hashmap.HashMap([]),
    has_been_computed: false,
  }
  if memo_idx < rt.pull.memos.length() {
    rt.pull.memos[memo_idx] = new_data
  } else {
    rt.pull.memos.push(new_data)
  }
  let ops : &CellOps = rt.pull.memos[memo_idx]
  rt.core.cell_ops.push(ops)
  let lifecycle : &CellLifecycle = rt.pull.memos[memo_idx]
  rt.cell_lifecycle.push(lifecycle)
  // ReachableDerived intentionally does NOT increment rt.push.node_count.
  // However, it does participate in push_reachable_count tracking: when a
  // live Reactive/Effect subscribes through a ReachableDerived, the cell and its
  // upstream cells each get push_reachable_count incremented. This lets
  // enqueue_push_subscribers prune dead ReachableDerived branches in the BFS
  // without traversing them. When push_reachable_count == 0, staleness is
  // detected purely via verified_at < current_revision.
  derived
}

///|
/// Package-private honest permissive read — the single source of truth for the
/// read channel. A disposed read returns `Err(Disposed(_))`; a cycle returns
/// `Err(Cycle(_))`; a compute `raise Failure` is a defect and still aborts.
/// Records a dependency when tracked (only on a successful read).
fn[T : Eq] ReachableDerived::read_honest(
  self : ReachableDerived[T],
) -> Result[T, ReadError] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    return Err(ReadError::disposed(self.cell_id))
  }
  let result = self.read_result_inner() catch {
    e => {
      self.rt.drain_pending_events_direct()
      abort("ReachableDerived compute raised: " + e.to_string())
    }
  }
  if self.rt.has_pending_events() {
    self.rt.drain_pending_events_if_idle()
  }
  match result {
    Ok(v) => Ok(v)
    Err(e) => Err(ReadError::cycle(e))
  }
}

///|
/// Internal: ReachableDerived verification logic shared by Result and aborting reads.
fn[T : Eq] ReachableDerived::read_result_inner(
  self : ReachableDerived[T],
) -> Result[T, CycleError] raise Failure {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("ReachableDerived::get called on a disposed reachable derived cell")
  }
  self.rt.check_cross_runtime(self.rt.core.runtime_id, "ReachableDerived")
  if self.rt.core.phase is InFixpoint {
    abort(
      "ReachableDerived::get() cannot be called during fixpoint(); read relations directly or call get() after fixpoint() completes",
    )
  }
  let result = match self.value {
    None => {
      let r = self.force_recompute()
      match r {
        Ok(value) => {
          self.rt.record_dependency(self.cell_id)
          Ok(value)
        }
        Err(e) => Err(e)
      }
    }
    Some(cached) => {
      let cell = self.rt.get_memo_data(self.cell_id)
      if cell.verified_at >= self.rt.core.revision.current_revision {
        self.rt.record_dependency(self.cell_id)
        Ok(cached)
      } else {
        let vr = self.rt.pull_verify(self.cell_id)
        match vr {
          Ok(_) => {
            self.rt.record_dependency(self.cell_id)
            match self.value {
              Some(v) => Ok(v)
              None =>
                abort(
                  "unreachable: value is always Some after successful verification",
                )
            }
          }
          Err(e) => Err(e)
        }
      }
    }
  }
  result
}

///|
fn[T : Eq] ReachableDerived::read_permissive(self : ReachableDerived[T]) -> T {
  let r = self.read_result_inner() catch {
    e => {
      self.rt.drain_pending_events_direct()
      abort("ReachableDerived compute raised: " + e.to_string())
    }
  }
  match r {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Force recomputation: delegates to shared memo_force_recompute helper.
fn[T : Eq] ReachableDerived::force_recompute(
  self : ReachableDerived[T],
) -> Result[T, CycleError] raise Failure {
  match
    self.rt.memo_force_recompute(self.cell_id, self.compute, self.value, fn(
      a,
      b,
    ) {
      a == b
    }) {
    Ok(new_value) => {
      self.value = Some(new_value)
      Ok(new_value)
    }
    Err(e) => Err(e)
  }
}

///|
/// Internal: recompute and return whether the value changed.
/// Stored as the type-erased `compute` closure in `MemoData`.
fn[T : Eq] ReachableDerived::recompute_inner(
  self : ReachableDerived[T],
) -> Result[Bool, CycleError] raise Failure {
  let cell = self.rt.get_memo_data(self.cell_id)
  let old_changed_at = cell.meta.changed_at
  match self.force_recompute() {
    Ok(_) => {
      let changed = cell.meta.changed_at != old_changed_at
      if changed {
        match cell.on_change {
          Some(f) => @kernel.run_callback(self.rt.core, f)
          None => ()
        }
      }
      Ok(changed)
    }
    Err(e) => Err(e)
  }
}

///|
/// Package-private strict honest read. Requires an active tracked context;
/// reports mechanism failures (cycle / disposed) as `ReadError`.
fn[T : Eq] ReachableDerived::get_strict_honest(
  self : ReachableDerived[T],
) -> Result[T, ReadError] {
  guard self.rt.core.tracking.stack.length() > 0 else {
    abort(
      "ReachableDerived::get() called outside tracked context. Use ReachableDerived::read(), ReachableDerived::read_or_abort(), or ReachableDerived::watch() to read from outside the graph.",
    )
  }
  self.read_honest()
}

///|
/// Package-private strict Result read. Requires an active tracked context.
/// Compatibility projection of `get_strict_honest` onto `CycleError`.
fn[T : Eq] ReachableDerived::get_strict_result(
  self : ReachableDerived[T],
) -> Result[T, CycleError] {
  guard self.rt.core.tracking.stack.length() > 0 else {
    abort(
      "ReachableDerived::get() called outside tracked context. Use ReachableDerived::read(), ReachableDerived::read_or_abort(), or ReachableDerived::watch() to read from outside the graph.",
    )
  }
  self.read_result()
}

///|
/// Package-private permissive Result read. Records a dependency when tracked.
/// Compatibility projection of `read_honest` onto `CycleError`: a disposed read
/// aborts (legacy contract), a cycle is `Err(CycleError)`.
fn[T : Eq] ReachableDerived::read_result(
  self : ReachableDerived[T],
) -> Result[T, CycleError] {
  match self.read_honest() {
    Ok(v) => Ok(v)
    Err(ReadError::Cycle(e)) => Err(e)
    Err(ReadError::Disposed(_)) =>
      abort("ReachableDerived::get called on a disposed reachable derived cell")
  }
}

///|
/// Returns true if the reachable derived value has a cached value and its
/// verified_at matches the runtime's current revision.
fn[T] ReachableDerived::is_up_to_date(self : ReachableDerived[T]) -> Bool {
  match self.value {
    None => false
    Some(_) =>
      self.rt.get_memo_data(self.cell_id).verified_at ==
      self.rt.core.revision.current_revision
  }
}

///|
fn[T : Eq] ReachableDerived::watch_result(
  self : ReachableDerived[T],
) -> Watch[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("ReachableDerived::watch called on a disposed reachable derived cell")
  }
  let rt = self.rt
  rt.add_read_root(self.cell_id)
  {
    runtime: rt,
    target_id: self.cell_id,
    getter: fn() { self.read_honest() },
    disposed: false,
  }
}
