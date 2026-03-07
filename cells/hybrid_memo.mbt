///|
/// Type-erased metadata for a HybridMemo cell in the SoA layout.
///
/// Like PullMemoData but adds a `dirty` flag set eagerly by push propagation.
/// On `get()`, the dirty flag allows skipping full dependency verification
/// when no upstream push cell has signaled a change.
priv struct HybridMemoData {
  cell_id : CellId
  label : String?
  compute : () -> Result[Bool, CycleError]
  mut changed_at : Revision
  mut verified_at : Revision
  mut durability : Durability
  mut dependencies : Array[CellId]
  subscribers : @hashset.HashSet[CellId]
  mut in_progress : Bool
  mut dirty : Bool
}

///|
impl CellOps for HybridMemoData with dep_changed_since(_self, _verified_at) -> Bool? {
  None
}

///|
/// User-facing hybrid memo cell.
///
/// Receives dirty flags eagerly (via push propagation) but verifies
/// lazily on `get()`. When `dirty = false` and already verified for the
/// current revision, `get()` returns the cached value without any dep walk.
pub(all) struct HybridMemo[T] {
  priv label : String?
  priv rt : Runtime
  priv cell_id : CellId
  priv compute : () -> T
  priv mut value : T?

  fn[T : Eq] new(
    rt : Runtime,
    compute : () -> T,
    label? : String,
  ) -> HybridMemo[T]
} derive(Debug(ignore=[Runtime, Fn, CellId]))

///|
/// Creates a new hybrid memo with the given compute function.
pub fn[T : Eq] HybridMemo::new(
  rt : Runtime,
  compute : () -> T,
  label? : String,
) -> HybridMemo[T] {
  let memo_idx = rt.push.hybrid_memos.length()
  let cell_id = rt.alloc_cell_id(HybridMemo(memo_idx))
  let memo : HybridMemo[T] = { label, rt, cell_id, compute, value: None }
  rt.push.hybrid_memos.push({
    cell_id,
    label,
    compute: () => memo.recompute_inner(),
    changed_at: Revision::initial(),
    verified_at: Revision::initial(),
    durability: Low,
    dependencies: [],
    subscribers: @hashset.new(),
    in_progress: false,
    dirty: false,
  })
  let ops : &CellOps = rt.push.hybrid_memos[memo_idx]
  rt.core.cell_ops.push(ops)
  rt.push.node_count = rt.push.node_count + 1
  memo
}

///|
/// Returns the memoized value, recomputing if necessary.
///
/// Fast path: if `dirty = false` and already verified this revision,
/// returns the cached value immediately without any dep walk.
///
/// Slow path: calls `pull_verify_hybrid` to walk deps, then clears `dirty`.
pub fn[T : Eq] HybridMemo::get(self : HybridMemo[T]) -> T {
  let active_rt = current_computing_runtime_id.val
  if active_rt >= 0 && active_rt != self.rt.core.runtime_id {
    current_computing_runtime_id.val = -1
    abort(
      "Cross-runtime dependency: HybridMemo belongs to Runtime " +
      self.rt.core.runtime_id.to_string() +
      " but is read inside a memo on Runtime " +
      active_rt.to_string(),
    )
  }
  if self.rt.datalog.in_fixpoint {
    abort(
      "HybridMemo::get() cannot be called during fixpoint(); read relations directly or call get() after fixpoint() completes",
    )
  }
  match self.value {
    None =>
      match self.force_recompute() {
        Ok(value) => {
          self.rt.record_dependency(self.cell_id)
          value
        }
        Err(e) => abort(e.format_path(self.rt))
      }
    Some(cached) => {
      let cell = self.rt.get_hybrid_memo(self.cell_id)
      // Fast path: not dirtied and already verified this revision
      if not(cell.dirty) && cell.verified_at >= self.rt.core.current_revision {
        self.rt.record_dependency(self.cell_id)
        return cached
      }
      // Slow path: verify deps, then clear dirty flag
      match self.rt.pull_verify_hybrid(self.cell_id) {
        Ok(_) => {
          cell.dirty = false
          self.rt.record_dependency(self.cell_id)
          match self.value {
            Some(v) => v
            None =>
              abort(
                "unreachable: value is always Some after successful verification",
              )
          }
        }
        Err(e) => abort(e.format_path(self.rt))
      }
    }
  }
}

///|
/// Returns the unique identifier for this hybrid memo.
pub fn[T] HybridMemo::id(self : HybridMemo[T]) -> CellId {
  self.cell_id
}

///|
/// Returns true if the hybrid memo's value is verified at the current revision.
pub fn[T] HybridMemo::is_up_to_date(self : HybridMemo[T]) -> Bool {
  match self.value {
    None => false
    Some(_) =>
      self.rt.get_hybrid_memo(self.cell_id).verified_at ==
      self.rt.core.current_revision
  }
}

///|
/// Force recomputation: push tracking frame, execute compute, pop frame,
/// update deps/subscribers/backdating.
fn[T : Eq] HybridMemo::force_recompute(
  self : HybridMemo[T],
) -> Result[T, CycleError] {
  let cell = self.rt.get_hybrid_memo(self.cell_id)
  if cell.in_progress {
    return Err(
      CycleError::from_path(self.rt.collect_tracking_path(), cell.cell_id),
    )
  }
  cell.in_progress = true
  let old_deps = cell.dependencies
  self.rt.push_tracking(self.cell_id)
  let new_value = (self.compute)()
  let (new_deps, new_seen) = self.rt.pop_tracking()
  let mut deps_changed = new_deps.length() != old_deps.length()
  let old_seen : @hashset.HashSet[CellId] = @hashset.new()
  for dep in old_deps {
    old_seen.add(dep)
    if not(new_seen.contains(dep)) {
      deps_changed = true
    }
  }
  if deps_changed {
    for dep in old_deps {
      if not(new_seen.contains(dep)) {
        self.rt.remove_subscriber(dep, self.cell_id)
      }
    }
    for dep in new_deps {
      if not(old_seen.contains(dep)) {
        self.rt.add_subscriber(dep, self.cell_id)
      }
    }
  }
  cell.dependencies = new_deps
  if deps_changed {
    cell.durability = compute_durability(self.rt, new_deps)
  }
  let value_changed = match self.value {
    None => true
    Some(old) => old != new_value
  }
  self.value = Some(new_value)
  if value_changed {
    cell.changed_at = self.rt.core.current_revision
  }
  cell.verified_at = self.rt.core.current_revision
  cell.dirty = false
  cell.in_progress = false
  Ok(new_value)
}

///|
/// Internal: recompute and return whether the value changed.
/// Stored as the type-erased `compute` closure in `HybridMemoData`.
fn[T : Eq] HybridMemo::recompute_inner(
  self : HybridMemo[T],
) -> Result[Bool, CycleError] {
  let cell = self.rt.get_hybrid_memo(self.cell_id)
  let old_changed_at = cell.changed_at
  match self.force_recompute() {
    Ok(_) => Ok(cell.changed_at != old_changed_at)
    Err(e) => Err(e)
  }
}

///|
/// CellOps dispatch for hybrid-memo cells.
impl CellOps for HybridMemoData with cell_id(self) -> CellId {
  self.cell_id
}

///|
impl CellOps for HybridMemoData with changed_at(self) -> Revision {
  self.changed_at
}

///|
impl CellOps for HybridMemoData with set_changed_at(self, rev : Revision) -> Unit {
  self.changed_at = rev
}

///|
impl CellOps for HybridMemoData with subscribers(self) -> @hashset.HashSet[
  CellId,
] {
  self.subscribers
}

///|
impl CellOps for HybridMemoData with label(self) -> String? {
  self.label
}

///|
impl CellOps for HybridMemoData with durability(self) -> Durability {
  self.durability
}
