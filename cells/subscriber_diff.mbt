///|
/// Thin Runtime wrapper over `@kernel.diff_and_update_subscribers`.
///
/// Kept in cells/ so wbtests (`subscriber_diff_wbtest.mbt`) can exercise
/// the full Runtime + Signal/Memo path without reaching into kernel
/// state directly.
fn Runtime::diff_and_update_subscribers(
  self : Runtime,
  cell_id : CellId,
  old_deps : Array[CellId],
  new_deps : Array[CellId],
  new_seen? : @hashset.HashSet[CellId],
) -> Bool {
  @kernel.diff_and_update_subscribers(
    self.core,
    self.pull,
    self.push,
    self.datalog,
    cell_id,
    old_deps,
    new_deps,
    new_seen?,
  )
}
