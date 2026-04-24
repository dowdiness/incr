///|
/// Thin Runtime wrapper over `@kernel.pull_verify`.
///
/// Passes `self.accumulator_snapshots` to kernel per the Stage 3 §0
/// decision: accumulator state stays on Runtime; the snapshot array
/// threads through as an explicit parameter rather than living on
/// RuntimeCore.
fn Runtime::pull_verify(
  self : Runtime,
  cell_id : CellId,
) -> Result[Unit, CycleError] raise Failure {
  @kernel.pull_verify(self.core, self.pull, self.accumulator_snapshots, cell_id)
}
