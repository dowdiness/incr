///|
/// Internal SoA entry for a Datalog relation cell.
pub(all) struct RelationData {
  meta : CellMeta
  drain_delta : () -> Unit
  is_delta_empty : () -> Bool
  promote_staged_delta : () -> Unit
  is_staged_delta_empty : () -> Bool
}

///|
pub impl HasCellMeta for RelationData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for relation cells — all defaults via HasCellMeta.
pub impl CellOps for RelationData
