///|
/// Internal SoA entry for a Datalog functional relation cell.
pub(all) struct FunctionalRelationData {
  meta : CellMeta
  drain_delta : () -> Unit
  is_delta_empty : () -> Bool
  promote_staged_delta : () -> Unit
  is_staged_delta_empty : () -> Bool
}

///|
pub impl HasCellMeta for FunctionalRelationData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for functional relation cells — all defaults via HasCellMeta.
pub impl CellOps for FunctionalRelationData
