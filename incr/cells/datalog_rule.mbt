///|
priv enum RuleDeclarationRole {
  InputOnly
  OutputOnly
  InputAndOutput
}

///|
priv struct LiveRuleDeclaration {
  rule_id : CellId
  role : RuleDeclarationRole
}

///|
fn find_live_rule_declaration(
  core : RuntimeCore,
  rules : Array[RuleData],
  relation_id : CellId,
) -> LiveRuleDeclaration? {
  for rule in rules {
    guard !@kernel.is_cell_disposed(core, rule.meta.cell_id) else { continue }
    let is_input = rule.input_relations.contains(relation_id)
    let is_output = rule.output_relations.contains(relation_id)
    if is_input || is_output {
      let role = if is_input && is_output {
        InputAndOutput
      } else if is_input {
        InputOnly
      } else {
        OutputOnly
      }
      return Some({ rule_id: rule.meta.cell_id, role })
    }
  }
  None
}

///|
/// Registers a Datalog rule over declared input and output relations.
///
/// The declaration arrays are snapshotted. A live rule pins every relation it
/// declares, so dispose each declaring rule before disposing those relations.
/// Panics if a declared cell belongs to another runtime, is disposed, or is
/// not a relation.
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
      subscribers: @hashset.HashSet([]),
      push_reachable_count: 0,
    },
    apply_delta,
    input_relations: input_relations.copy(),
    output_relations: output_relations.copy(),
  }
  self.datalog.rules.push(data)
  let ops : &CellOps = self.datalog.rules[idx]
  self.core.cell_ops.push(ops)
  let lifecycle : &CellLifecycle = self.datalog.rules[idx]
  self.cell_lifecycle.push(lifecycle)
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
    Disposed =>
      abort(
        "new_rule: " +
        role +
        " relation cell_id is disposed: " +
        id.id.to_string(),
      )
    _ =>
      abort(
        "new_rule: " + role + " cell_id is not a Relation: " + id.id.to_string(),
      )
  }
}
