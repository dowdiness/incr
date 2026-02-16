///|
/// A dependency recording frame pushed onto the runtime's tracking stack
/// when a memo is being computed.
///
/// During a memo's compute function, every `Signal::get()` or `Memo::get()`
/// call records a dependency in the active query. When the computation
/// finishes, the collected dependencies are stored on the memo's cell metadata.
///
/// Dependencies are deduplicated using a HashSet for O(1) membership checks.
priv struct ActiveQuery {
  cell_id : CellId
  dependencies : Array[CellId]
  seen : @hashset.HashSet[CellId]
}

///|
/// Creates a new active query.
///
/// # Parameters
///
/// - `cell_id`: The cell ID of the memo being computed
///
/// # Returns
///
/// A new active query with an empty dependency set
fn ActiveQuery::new(cell_id : CellId) -> ActiveQuery {
  { cell_id, dependencies: [], seen: @hashset.new() }
}

///|
/// Records that the currently computing memo depends on the given cell.
///
/// If the cell has already been recorded as a dependency, this is a no-op
/// (deduplication via HashSet). This ensures the dependency list is minimal
/// and order-preserving.
///
/// # Parameters
///
/// - `dep`: The cell ID to record as a dependency
fn ActiveQuery::record(self : ActiveQuery, dep : CellId) -> Unit {
  if self.seen.contains(dep) {
    return
  }
  self.seen.add(dep)
  self.dependencies.push(dep)
}
