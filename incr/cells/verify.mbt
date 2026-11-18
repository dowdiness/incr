///|
/// Threads `accumulator_snapshots` (Runtime-owned) into the kernel verify.
fn Runtime::pull_verify(self : Runtime, cell_id : CellId) -> Unit raise Error {
  self.evaluation_strategies.pull_verify(
    self.core,
    self.pull,
    self.accumulator_snapshots,
    cell_id,
  )
}
