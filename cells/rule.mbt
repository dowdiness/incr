///|
pub struct RuleId {
  id : CellId
}

///|
struct RuleData {
  cell_id : CellId
  label : String?
  apply_delta : () -> Unit
  input_relations : Array[CellId]
  output_relations : Array[CellId]
  subscribers : @hashset.HashSet[CellId]
  mut changed_at : Revision
  durability : Durability
}

///|
impl CellOps for RuleData with cell_id(self) { self.cell_id }

///|
impl CellOps for RuleData with changed_at(self) { self.changed_at }

///|
impl CellOps for RuleData with set_changed_at(self, rev) {
  self.changed_at = rev
}

///|
impl CellOps for RuleData with subscribers(self) { self.subscribers }

///|
impl CellOps for RuleData with label(self) { self.label }

///|
impl CellOps for RuleData with durability(self) { self.durability }
