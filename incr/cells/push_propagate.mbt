///|
/// Level lookup used by push lifecycle cell setup.
fn Runtime::recompute_level(
  self : Runtime,
  cell_id : CellId,
  sources : Array[CellId],
) -> Int {
  @kernel.recompute_level(self.core, cell_id, sources)
}
