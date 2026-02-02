///|
/// A dependency recording frame pushed when a Memo is being computed.
/// Collects all CellIds that are read during the computation.
pub(all) struct ActiveQuery {
  cell_id : CellId
  mut dependencies : Array[CellId]
}

///|
pub fn ActiveQuery::new(cell_id : CellId) -> ActiveQuery {
  { cell_id, dependencies: [] }
}

///|
/// Record that the current computation depends on the given cell.
/// Deduplicates: a cell appearing multiple times is recorded only once.
pub fn ActiveQuery::record(self : ActiveQuery, dep : CellId) -> Unit {
  for i = 0; i < self.dependencies.length(); i = i + 1 {
    if self.dependencies[i] == dep {
      return
    }
  }
  self.dependencies.push(dep)
}
