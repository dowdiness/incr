///|
/// Type-erased metadata for a HybridMemo cell in the SoA layout.
///
/// HybridMemo uses the unified MemoData struct for dependency tracking.
/// Staleness is detected via `verified_at < current_revision`; no separate
/// dirty flag is needed since `HybridMemo` does not increment `push.node_count`.

///|
/// User-facing hybrid memo cell.
///
/// Verifies lazily on `get()`. When `verified_at >= current_revision`,
/// `get()` returns the cached value immediately without any dep walk.
/// Staleness is detected purely via the revision counter — no dirty flag.
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
  let memo_idx = rt.pull.memos.length()
  let cell_id = rt.alloc_cell_id(HybridMemo(memo_idx))
  let memo : HybridMemo[T] = { label, rt, cell_id, compute, value: None }
  rt.pull.memos.push({
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
    },
    compute: () => memo.recompute_inner(),
    verified_at: Revision::initial(),
    dependencies: [],
    in_progress: false,
    on_change: None,
  })
  let ops : &CellOps = rt.pull.memos[memo_idx]
  rt.core.cell_ops.push(ops)
  // HybridMemo intentionally does NOT increment rt.push.node_count.
  // This means signal.set() skips push_propagate_from when only hybrid
  // memos exist downstream, relying on verified_at staleness instead.
  memo
}

///|
/// Returns the memoized value, recomputing if necessary.
///
/// Fast path: if already verified this revision, returns the cached value
/// immediately without any dep walk.
///
/// Slow path: calls `pull_verify` to walk deps.
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
  if self.rt.core.in_fixpoint {
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
      let cell = self.rt.get_memo_data(self.cell_id)
      // Fast path: already verified this revision
      if cell.verified_at >= self.rt.core.current_revision {
        self.rt.record_dependency(self.cell_id)
        return cached
      }
      // Slow path: verify deps
      match self.rt.pull_verify(self.cell_id) {
        Ok(_) => {
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
      self.rt.get_memo_data(self.cell_id).verified_at ==
      self.rt.core.current_revision
  }
}

///|
/// Force recomputation: delegates to shared memo_force_recompute helper.
fn[T : Eq] HybridMemo::force_recompute(
  self : HybridMemo[T],
) -> Result[T, CycleError] {
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
fn[T : Eq] HybridMemo::recompute_inner(
  self : HybridMemo[T],
) -> Result[Bool, CycleError] {
  let cell = self.rt.get_memo_data(self.cell_id)
  let old_changed_at = cell.meta.changed_at
  match self.force_recompute() {
    Ok(_) => {
      let changed = cell.meta.changed_at != old_changed_at
      if changed {
        match cell.on_change {
          Some(f) => f()
          None => ()
        }
      }
      Ok(changed)
    }
    Err(e) => Err(e)
  }
}
