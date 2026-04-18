///|
/// Internal SoA entry for a Datalog rule cell.
pub(all) struct RuleData {
  meta : CellMeta
  apply_delta : () -> Unit
  input_relations : Array[CellId]
  output_relations : Array[CellId]
}

///|
pub impl HasCellMeta for RuleData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for rule cells — defaults via HasCellMeta plus a
/// `gc_role` override. The `with` block alone registers the impl; a
/// separate bare anchor would be redundant.
pub impl CellOps for RuleData with gc_role(_self) -> GcRole {
  Source
}
