///|
pub struct RelationId[T] {
  id : CellId
}

///|
struct RelationData {
  cell_id : CellId
  drain_delta : () -> Unit
  is_delta_empty : () -> Bool
  subscribers : @hashset.HashSet[CellId]
  mut changed_at : Revision
  mut changed : Bool
  label : String?
  durability : Durability
}

///|
impl CellOps for RelationData with cell_id(self) { self.cell_id }

///|
impl CellOps for RelationData with changed_at(self) { self.changed_at }

///|
impl CellOps for RelationData with set_changed_at(self, rev) {
  self.changed_at = rev
}

///|
impl CellOps for RelationData with subscribers(self) { self.subscribers }

///|
impl CellOps for RelationData with label(self) { self.label }

///|
impl CellOps for RelationData with durability(self) { self.durability }
