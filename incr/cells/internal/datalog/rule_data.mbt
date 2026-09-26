///|
/// Internal SoA entry for a Datalog rule cell.
pub(all) struct RuleData {
  meta : CellMeta
  apply_delta : () -> Unit
  input_relations : Array[CellId]
  output_relations : Array[CellId]
}

///|
pub impl HasCellMeta for RuleData with fn meta(self) {
  self.meta
}
pub extend RuleData with HasCellMeta::{meta}
pub extend RuleData with CellOps::{
  cell_id, changed_at, set_changed_at, subscribers, label, durability, level,
  dep_changed_since, push_reachable_count, gc_role, gc_dependencies,
}

///|
/// CellOps dispatch for rule cells — defaults via HasCellMeta plus a
/// `gc_role` override. The `with` block alone registers the impl; a
/// separate bare anchor would be redundant.
pub impl CellOps for RuleData with fn gc_role(_self) -> GcRole {
  Source
}
