///|
/// Internal SoA entry for a Datalog relation cell.
pub(all) struct RelationData {
  meta : CellMeta
  drain_delta : () -> Unit
  is_delta_empty : () -> Bool
  promote_staged_delta : () -> Unit
  is_staged_delta_empty : () -> Bool
  begin_fixpoint : () -> Unit
  finish_fixpoint_changed : () -> Bool
}

///|
pub impl HasCellMeta for RelationData with fn meta(self) {
  self.meta
}
pub extend RelationData with HasCellMeta::{meta}
pub extend RelationData with CellOps::{
  cell_id, changed_at, set_changed_at, subscribers, label, durability, level,
  dep_changed_since, push_reachable_count, gc_role, gc_dependencies,
}

///|
/// CellOps dispatch for relation cells — all defaults via HasCellMeta.
pub impl CellOps for RelationData
