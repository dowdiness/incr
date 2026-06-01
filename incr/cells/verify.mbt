///|
/// Threads `accumulator_snapshots` (Runtime-owned) into the kernel verify.
fn Runtime::pull_verify(
  self : Runtime,
  cell_id : CellId,
) -> Result[Unit, CycleError] raise Failure {
  self.evaluation_strategies.pull_verify(
    self.core,
    self.pull,
    self.accumulator_snapshots,
    cell_id,
  )
}
