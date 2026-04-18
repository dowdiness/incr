///|
using @datalog {type RelationData, type FunctionalRelationData, type RuleData}

///|
/// Shared teardown for datalog cells: they hold no upstream subscriber links
/// or free-list slots, so disposal only clears metadata and marks the slot
/// `Disposed`. Each kind's `dispose_cell` impl is a one-liner over this.
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
impl CellLifecycle for RelationData with dispose_cell(self, rt, cell_id) -> Unit {
  dispose_datalog_cell(self.meta, rt, cell_id)
}

///|
impl CellLifecycle for FunctionalRelationData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  dispose_datalog_cell(self.meta, rt, cell_id)
}

///|
impl CellLifecycle for RuleData with dispose_cell(self, rt, cell_id) -> Unit {
  dispose_datalog_cell(self.meta, rt, cell_id)
}
