///|
using @datalog {type RelationData, type FunctionalRelationData, type RuleData}

///|
/// Shared teardown for datalog cells: they hold no upstream subscriber links
/// or free-list slots, so disposal only clears metadata and marks the slot
/// `Disposed`.
fn dispose_datalog_cell(
  meta : CellMeta,
  rt : Runtime,
  cell_id : CellId,
) -> Unit {
  meta.subscribers.clear()
  meta.label = None
  rt.core.cell_index[cell_id.id] = Disposed
}

///|
fn RuleDeclarationRole::label(self : RuleDeclarationRole) -> String {
  match self {
    InputOnly => "input"
    OutputOnly => "output"
    InputAndOutput => "both"
  }
}

///|
fn dispose_relation_datalog_cell(
  meta : CellMeta,
  rt : Runtime,
  cell_id : CellId,
) -> Unit {
  match find_live_rule_declaration(rt.core, rt.datalog.rules, cell_id) {
    Some(declaration) =>
      abort(
        "dispose: relation " +
        cell_id.id.to_string() +
        " is pinned by live rule " +
        declaration.rule_id.id.to_string() +
        " as " +
        declaration.role.label() +
        "; dispose the rule first",
      )
    None => dispose_datalog_cell(meta, rt, cell_id)
  }
}

///|
impl CellLifecycle for RelationData with fn dispose_cell(self, rt, cell_id) -> Unit {
  dispose_relation_datalog_cell(self.meta, rt, cell_id)
}

///|
impl CellLifecycle for FunctionalRelationData with fn dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  dispose_relation_datalog_cell(self.meta, rt, cell_id)
}

///|
impl CellLifecycle for RuleData with fn dispose_cell(self, rt, cell_id) -> Unit {
  dispose_datalog_cell(self.meta, rt, cell_id)
}
