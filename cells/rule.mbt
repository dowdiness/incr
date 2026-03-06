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

///|
fn Runtime::new_rule(
  self : Runtime,
  input_relations : Array[CellId],
  output_relations : Array[CellId],
  apply_delta : () -> Unit,
  label? : String,
) -> RuleId {
  // Validate all inputs are Relations
  for id in input_relations {
    match self.cell_index[id.id] {
      Relation(_) => ()
      _ => abort("new_rule: input cell_id is not a Relation: " + id.id.to_string())
    }
  }
  // Validate all outputs are Relations
  for id in output_relations {
    match self.cell_index[id.id] {
      Relation(_) => ()
      _ =>
        abort(
          "new_rule: output cell_id is not a Relation: " + id.id.to_string(),
        )
    }
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
