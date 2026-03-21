///|
struct FunctionalRelationData {
  meta : CellMeta
  drain_delta : () -> Unit
  is_delta_empty : () -> Bool
  promote_staged_delta : () -> Unit
  is_staged_delta_empty : () -> Bool
}

///|
impl HasCellMeta for FunctionalRelationData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for functional relation cells — all defaults via HasCellMeta.
impl CellOps for FunctionalRelationData
