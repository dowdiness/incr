///|
priv struct RuleData {
  meta : CellMeta
  apply_delta : () -> Unit
  input_relations : Array[CellId]
  output_relations : Array[CellId]
}

///|
impl HasCellMeta for RuleData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for rule cells — all defaults via HasCellMeta.
impl CellOps for RuleData

///|
impl CellLifecycle for RuleData with dispose_cell(self, rt, cell_id) -> Unit {
  self.meta.subscribers.clear()
  self.meta.label = None
  rt.core.cell_index[cell_id.id] = Disposed
}

///|
impl CellOps for RuleData with gc_role(_self) -> GcRole {
  Source
}

///|
pub fn Runtime::new_rule(
  self : Runtime,
  input_relations : Array[CellId],
  output_relations : Array[CellId],
  apply_delta : () -> Unit,
  label? : String,
) -> @incr_types.RuleId {
  for id in input_relations {
    self.assert_rule_relation_id(id, "input")
  }
  for id in output_relations {
    self.assert_rule_relation_id(id, "output")
  }
  let idx = self.datalog.rules.length()
  let cell_id = self.alloc_cell_id(Rule(idx))
  let data : RuleData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
      push_reachable_count: 0,
    },
    apply_delta,
    input_relations,
    output_relations,
  }
  self.datalog.rules.push(data)
  let ops : &CellOps = self.datalog.rules[idx]
  self.core.cell_ops.push(ops)
  let lifecycle : &CellLifecycle = self.datalog.rules[idx]
  self.core.cell_lifecycle.push(lifecycle)
  @incr_types.RuleId::{ id: cell_id }
}

///|
fn Runtime::assert_rule_relation_id(
  self : Runtime,
  id : CellId,
  role : String,
) -> Unit {
  if id.runtime_id != self.core.runtime_id {
    abort(
      "new_rule: " +
      role +
      " relation belongs to Runtime " +
      id.runtime_id.to_string() +
      ", expected Runtime " +
      self.core.runtime_id.to_string(),
    )
  }
  if id.id < 0 || id.id >= self.core.cell_index.length() {
    abort(
      "new_rule: " +
      role +
      " relation cell_id out of bounds: " +
      id.id.to_string(),
    )
  }
  match self.core.cell_index[id.id] {
    Relation(_) | FunctionalRelation(_) => ()
    _ =>
      abort(
        "new_rule: " + role + " cell_id is not a Relation: " + id.id.to_string(),
      )
  }
}
