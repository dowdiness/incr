///|
/// Type-erased metadata for a Pull Memo cell in the SoA layout.
///
/// The actual typed value lives in the `Memo[T]` handle held by user code.
/// `compute` is a closure captured at construction time that recomputes the
/// memo and returns whether the value changed.
pub(all) struct MemoData {
  meta : CellMeta
  compute : () -> Result[Bool, CycleError]
  mut verified_at : Revision
  mut dependencies : Array[CellId]
  mut in_progress : Bool
  mut on_change : (() -> Unit)?
  is_hybrid : Bool
  // accumulator_reads: (slot_id, target_cell_id) -> stored push revision.
  // Persisted state for synthetic accumulator deps. Populated on successful
  // recompute commit; consulted by pull_verify's synthetic dep check.
  mut accumulator_reads : @hashmap.HashMap[
    (@incr_types.AccumulatorId, @incr_types.CellId),
    @incr_types.Revision,
  ]
}

///|
pub impl HasCellMeta for MemoData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for pull-memo cells — defaults via HasCellMeta, with
/// deep-verification override.
pub impl CellOps for MemoData

///|
pub impl CellOps for MemoData with dep_changed_since(_self, _verified_at) -> Bool? {
  None
}

///|
pub impl CellOps for MemoData with gc_role(_self) -> GcRole {
  Interior
}

///|
pub impl CellOps for MemoData with gc_dependencies(self) -> Array[CellId] {
  self.dependencies
}
