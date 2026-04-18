///|
using @datalog {type RelationData, type FunctionalRelationData, type RuleData}

///|
impl CellLifecycle for RelationData with dispose_cell(self, rt, cell_id) -> Unit {
  self.meta.subscribers.clear()
  self.meta.label = None
  rt.core.cell_index[cell_id.id] = Disposed
}

///|
impl CellLifecycle for FunctionalRelationData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  self.meta.subscribers.clear()
  self.meta.label = None
  rt.core.cell_index[cell_id.id] = Disposed
}

///|
impl CellLifecycle for RuleData with dispose_cell(self, rt, cell_id) -> Unit {
  self.meta.subscribers.clear()
  self.meta.label = None
  rt.core.cell_index[cell_id.id] = Disposed
}
