///|
/// Thin Runtime wrapper over `@kernel.push_propagate_from`.
///
/// The algorithm body moved to `kernel/push_propagate.mbt` in R1 Stage 3f.
fn Runtime::push_propagate_from(
  self : Runtime,
  changed_sources : Array[CellId],
) -> Unit {
  @kernel.push_propagate_from(
    self.core,
    self.pull,
    self.push,
    self.datalog,
    changed_sources,
  )
}

///|
/// Thin wrapper — level lookup used by push lifecycle cell setup.
fn Runtime::recompute_level(
  self : Runtime,
  cell_id : CellId,
  sources : Array[CellId],
) -> Int {
  @kernel.recompute_level(self.core, cell_id, sources)
}
