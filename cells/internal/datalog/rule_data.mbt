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
/// CellOps dispatch for rule cells — all defaults via HasCellMeta.
pub impl CellOps for RuleData

///|
pub impl CellOps for RuleData with gc_role(_self) -> GcRole {
  Source
}
