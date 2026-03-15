///|
/// Type-erased metadata for a Pull Memo cell in the SoA layout.
///
/// The actual typed value lives in the `Memo[T]` handle held by user code.
/// `compute` is a closure captured at construction time that recomputes
/// the memo and returns whether the value changed.
priv struct MemoData {
  meta : CellMeta
  compute : () -> Result[Bool, CycleError]
  mut verified_at : Revision
  mut dependencies : Array[CellId]
  mut in_progress : Bool
  mut dirty : Bool
  mut on_change : (() -> Unit)?
}

///|
impl HasCellMeta for MemoData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for pull-memo cells — defaults via HasCellMeta,
/// with deep-verification override.
impl CellOps for MemoData

///|
impl CellOps for MemoData with dep_changed_since(_self, _verified_at) -> Bool? {
  None
}
