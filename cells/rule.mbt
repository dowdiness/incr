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
impl CellOps for RuleData with cell_id(self) {
  self.cell_id
}

///|
impl CellOps for RuleData with changed_at(self) {
  self.changed_at
}

///|
impl CellOps for RuleData with set_changed_at(self, rev) {
  self.changed_at = rev
}

///|
impl CellOps for RuleData with subscribers(self) {
  self.subscribers
}

///|
impl CellOps for RuleData with label(self) {
  self.label
}

///|
impl CellOps for RuleData with durability(self) {
  self.durability
}

///|
pub fn Runtime::new_rule(
  self : Runtime,
  input_relations : Array[CellId],
  output_relations : Array[CellId],
  apply_delta : () -> Unit,
  label? : String,
) -> RuleId {
  for id in input_relations {
    self.assert_rule_relation_id(id, "input")
  }
  for id in output_relations {
    self.assert_rule_relation_id(id, "output")
  }
  let idx = self.rules.length()
  let cell_id = self.alloc_cell_id(Rule(idx))
  let data : RuleData = {
    cell_id,
    label,
    apply_delta,
    input_relations,
    output_relations,
    subscribers: @hashset.new(),
    changed_at: Revision::initial(),
    durability: Low,
  }
  self.rules.push(data)
  let ops : &CellOps = self.rules[idx]
  self.cell_ops.push(ops)
  { id: cell_id }
}

///|
fn Runtime::assert_rule_relation_id(
  self : Runtime,
  id : CellId,
  role : String,
) -> Unit {
  if id.runtime_id != self.runtime_id {
    abort(
      "new_rule: " +
      role +
      " relation belongs to Runtime " +
      id.runtime_id.to_string() +
      ", expected Runtime " +
      self.runtime_id.to_string(),
    )
  }
  if id.id < 0 || id.id >= self.cell_index.length() {
    abort(
      "new_rule: " +
      role +
      " relation cell_id out of bounds: " +
      id.id.to_string(),
    )
  }
  match self.cell_index[id.id] {
    Relation(_) => ()
    _ =>
      abort(
        "new_rule: " + role + " cell_id is not a Relation: " + id.id.to_string(),
      )
  }
}
