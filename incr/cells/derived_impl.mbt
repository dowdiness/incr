///|
/// Compute the durability of a derived cell from its dependencies.
/// A derived cell's durability is the minimum of its dependencies' durabilities.
fn compute_durability(rt : Runtime, deps : Array[CellId]) -> Durability {
  if deps.length() == 0 {
    return Low
  }
  let mut min_dur = Durability::High
  for dep_id in deps {
    let dur = rt.get_durability(dep_id)
    if dur < min_dur {
      min_dur = dur
    }
  }
  min_dur
}

///|
/// Shared force-recompute logic for all memo types (pull and hybrid).
///
/// Handles cycle detection, dependency tracking, subscriber link maintenance,
/// durability recomputation, and backdating.
fn[T] Runtime::memo_force_recompute(
  self : Runtime,
  cell_id : CellId,
  compute_fn : () -> T raise Failure,
  old_value : T?,
  eq_fn : (T, T) -> Bool,
) -> Result[T, CycleError] raise Failure {
  let cell = self.get_memo_data(cell_id)
  if cell.in_progress {
    return Err(
      @kernel.construct_cycle_error(
        self.core,
        @kernel.collect_tracking_path(self.core),
        cell.meta.cell_id,
      ),
    )
  }
  cell.in_progress = true
  self.dispatch_before_recompute_hooks(cell_id)
  let old_deps = cell.dependencies
  @kernel.push_tracking(self.core, cell_id)
  let new_value = compute_fn() catch {
    e => {
      self.dispatch_after_abort_hooks(cell_id, e)
      let _ = @kernel.pop_tracking_full(self.core)
      cell.in_progress = false
      raise e
    }
  }
  let query = @kernel.pop_tracking_full(self.core)
  let new_deps = query.dependencies
  let new_seen = query.seen
  let _ = @kernel.diff_and_update_subscribers(
    self.core,
    self.pull,
    self.push,
    self.datalog,
    cell_id,
    old_deps,
    new_deps,
    new_seen~,
  )
  cell.dependencies = new_deps
  cell.meta.durability = compute_durability(self, new_deps)
  let value_changed = match old_value {
    None => true
    Some(old) => !eq_fn(old, new_value)
  }
  if value_changed {
    cell.meta.changed_at = self.core.revision.current_revision
  }
  cell.verified_at = self.core.revision.current_revision
  cell.has_been_computed = true
  cell.in_progress = false
  self.dispatch_after_success_hooks(cell_id)
  Ok(new_value)
}

///|
fn[T] Runtime::static_memo_force_recompute(
  self : Runtime,
  cell_id : CellId,
  compute_fn : () -> T raise Failure,
  old_value : T?,
  eq_fn : (T, T) -> Bool,
) -> Result[T, CycleError] raise Failure {
  let cell = self.get_memo_data(cell_id)
  if cell.in_progress {
    return Err(
      @kernel.construct_cycle_error(
        self.core,
        @kernel.collect_in_progress_path(self.pull),
        cell.meta.cell_id,
      ),
    )
  }
  cell.in_progress = true
  self.dispatch_before_recompute_hooks(cell_id)
  self.enter_static_recompute()
  let new_value = compute_fn() catch {
    e => {
      self.leave_static_recompute()
      self.dispatch_after_abort_hooks(cell_id, e)
      cell.in_progress = false
      raise e
    }
  }
  self.leave_static_recompute()
  cell.meta.durability = compute_durability(self, cell.dependencies)
  let value_changed = match old_value {
    None => true
    Some(old) => !eq_fn(old, new_value)
  }
  if value_changed {
    cell.meta.changed_at = self.core.revision.current_revision
  }
  cell.verified_at = self.core.revision.current_revision
  cell.has_been_computed = true
  cell.in_progress = false
  self.dispatch_after_success_hooks(cell_id)
  Ok(new_value)
}

///|
/// Internal: allocate a new Derived cell in the SoA and return the typed handle.
fn[T] Derived::_create(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
  backdate_eq : (T, T) -> Bool,
) -> Derived[T] {
  let memo_idx = rt.pull.free_memos.pop().unwrap_or(rt.pull.memos.length())
  let cell_id = rt.alloc_cell_id(PullMemo(memo_idx))
  let derived : Derived[T] = {
    label,
    rt,
    cell_id,
    compute,
    is_static: false,
    backdate_eq,
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
    is_hybrid: false,
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
  derived
}

///|
fn[T] Derived::_create_static(
  rt : Runtime,
  deps : Array[CellId],
  compute : (CellId) -> T raise Failure,
  label? : String,
  backdate_eq : (T, T) -> Bool,
) -> Derived[T] {
  let fixed_deps = rt.normalize_static_derived_deps(deps)
  let memo_idx = rt.pull.free_memos.pop().unwrap_or(rt.pull.memos.length())
  let cell_id = rt.alloc_cell_id(PullMemo(memo_idx))
  let derived : Derived[T] = {
    label,
    rt,
    cell_id,
    compute: () => compute(cell_id),
    is_static: true,
    backdate_eq,
    value: None,
  }
  let data : MemoData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: compute_durability(rt, fixed_deps),
      subscribers: @hashset.HashSet([]),
      push_reachable_count: 0,
    },
    compute: () => derived.recompute_inner(),
    verified_at: Revision::initial(),
    dependencies: fixed_deps,
    in_progress: false,
    on_change: None,
    is_hybrid: false,
    accumulator_reads: @hashmap.HashMap([]),
    has_been_computed: false,
  }
  if memo_idx < rt.pull.memos.length() {
    rt.pull.memos[memo_idx] = data
  } else {
    rt.pull.memos.push(data)
  }
  let ops : &CellOps = rt.pull.memos[memo_idx]
  rt.core.cell_ops.push(ops)
  let lifecycle : &CellLifecycle = rt.pull.memos[memo_idx]
  rt.cell_lifecycle.push(lifecycle)
  for dep in fixed_deps {
    rt.add_subscriber(dep, cell_id)
  }
  derived
}

///|
/// Internal: the core verification logic. Does NOT check tracking context.
/// Aborts during fixpoint (see InFixpoint guard below).
fn[T] Derived::get_result_inner(
  self : Derived[T],
) -> Result[T, CycleError] raise Failure {
  self.get_result_inner_impl(record_dependency=true)
}

///|
fn[T] Derived::get_result_inner_impl(
  self : Derived[T],
  record_dependency~ : Bool,
) -> Result[T, CycleError] raise Failure {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Derived::get called on a disposed derived cell")
  }
  @kernel.repair_stale_runtime_sentinel_for_untracked_read(
    self.rt.core,
    "Derived",
  )
  if self.rt.core.phase is InFixpoint {
    abort(
      "Derived::get() cannot be called during fixpoint(); read relations directly or call get() after fixpoint() completes",
    )
  }
  match self.value {
    None => {
      let r = self.force_recompute()
      match r {
        Ok(_) => {
          if record_dependency {
            self.rt.record_dependency(self.cell_id)
          }
          Ok(self.value.unwrap())
        }
        Err(e) => Err(e)
      }
    }
    Some(cached) => {
      let cell = self.rt.get_memo_data(self.cell_id)
      if cell.verified_at >= self.rt.core.revision.current_revision {
        if record_dependency {
          self.rt.record_dependency(self.cell_id)
        }
        Ok(cached)
      } else {
        let vr = self.rt.pull_verify(self.cell_id)
        match vr {
          Ok(_) => {
            if record_dependency {
              self.rt.record_dependency(self.cell_id)
            }
            Ok(self.value.unwrap())
          }
          Err(e) => Err(e)
        }
      }
    }
  }
}

///|
/// Package-private honest permissive read — the single source of truth for the
/// read channel. A disposed read returns `Err(Disposed(_))` (not an abort); a
/// cycle returns `Err(Cycle(_))`. A compute `raise Failure` is a *defect* and
/// still aborts. Reports `Disposed` only for *this* cell; a disposed transitive
/// dependency surfaced during verification still aborts inside `pull_verify`.
/// Records a dependency when tracked (only on a successful read).
fn[T] Derived::read_honest(self : Derived[T]) -> Result[T, ReadError] {
  self.read_honest_impl(record_dependency=true)
}

///|
fn[T] Derived::read_honest_impl(
  self : Derived[T],
  record_dependency~ : Bool,
) -> Result[T, ReadError] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    return Err(ReadError::disposed(self.cell_id))
  }
  self.rt.check_cross_runtime(self.rt.core.runtime_id, "Derived")
  let result = self.get_result_inner_impl(record_dependency~) catch {
    e => {
      self.rt.drain_pending_events_direct()
      abort("Derived compute raised: " + e.to_string())
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
fn[T] Derived::read_permissive(self : Derived[T]) -> T {
  let r = self.get_result_inner() catch {
    e => {
      self.rt.drain_pending_events_direct()
      abort("Derived compute raised: " + e.to_string())
    }
  }
  let value = match r {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
  value
}

///|
/// Force recomputation: delegates to the dynamic or static memo recompute helper.
fn[T] Derived::force_recompute(
  self : Derived[T],
) -> Result[T, CycleError] raise Failure {
  let result = if self.is_static {
    self.rt.static_memo_force_recompute(
      self.cell_id,
      self.compute,
      self.value,
      self.backdate_eq,
    )
  } else {
    self.rt.memo_force_recompute(
      self.cell_id,
      self.compute,
      self.value,
      self.backdate_eq,
    )
  }
  match result {
    Ok(new_value) => {
      self.value = Some(new_value)
      Ok(new_value)
    }
    Err(e) => Err(e)
  }
}

///|
/// Internal: recompute and return whether the value changed.
/// This is the closure stored in CellMeta for type-erased recomputation.
fn[T] Derived::recompute_inner(
  self : Derived[T],
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
fn[T] Derived::read_declared_fixed_dep_or_abort(
  self : Derived[T],
  dependent : CellId,
) -> T raise Failure {
  guard self.rt.validate_cell_soft(dependent) else {
    fail("static Derived fixed-source read from a different runtime")
  }
  let dependent_data = self.rt.get_memo_data(dependent)
  guard dependent_data.in_progress else {
    fail("static Derived fixed-source read outside dependent recompute")
  }
  guard dependent_data.dependencies.contains(self.cell_id) else {
    fail("static Derived fixed-source read without a declared dependency")
  }
  match self.read_honest_impl(record_dependency=false) {
    Ok(value) => {
      @kernel.set_current_computing_runtime_id(Some(self.rt.core.runtime_id))
      value
    }
    Err(e) => abort(e.format_path())
  }
}

///|
/// Package-private strict honest read. Requires an active tracked context;
/// reports mechanism failures (cycle / disposed) as `ReadError`.
fn[T] Derived::get_strict_honest(self : Derived[T]) -> Result[T, ReadError] {
  guard self.rt.core.tracking.stack.length() > 0 else {
    abort(
      "Derived::get() called outside tracked context. Use Derived::read(), Derived::read_or_abort(), or Derived::watch() to read from outside the graph.",
    )
  }
  self.read_honest()
}

///|
/// Package-private strict Result read. Requires an active tracked context.
/// Compatibility projection of `get_strict_honest` onto `CycleError`.
fn[T] Derived::get_strict_result(self : Derived[T]) -> Result[T, CycleError] {
  guard self.rt.core.tracking.stack.length() > 0 else {
    abort(
      "Derived::get() called outside tracked context. Use Derived::read(), Derived::read_or_abort(), or Derived::watch() to read from outside the graph.",
    )
  }
  self.read_result()
}

///|
/// Package-private permissive Result read. Records a dependency when tracked.
/// Compatibility projection of `read_honest` onto `CycleError`: a disposed read
/// aborts (legacy contract), a cycle is `Err(CycleError)`.
fn[T] Derived::read_result(self : Derived[T]) -> Result[T, CycleError] {
  match self.read_honest() {
    Ok(v) => Ok(v)
    Err(ReadError::Cycle(e)) => Err(e)
    Err(ReadError::Disposed(_)) =>
      abort("Derived::get called on a disposed derived cell")
  }
}

///|
fn[T] Derived::is_up_to_date(self : Derived[T]) -> Bool {
  match self.value {
    None => false
    Some(_) =>
      self.rt.get_memo_data(self.cell_id).verified_at ==
      self.rt.core.revision.current_revision
  }
}

///|
fn[T] Derived::watch_result(self : Derived[T]) -> Watch[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Derived::watch called on a disposed derived cell")
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
