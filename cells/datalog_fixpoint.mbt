///|
/// Runs fixpoint evaluation and publishes any resulting cell changes.
pub fn Runtime::fixpoint(self : Runtime) -> Unit {
  let changed_ids = @kernel.run_fixpoint(self.core, self.datalog)
  if changed_ids.length() > 0 {
    self.publish_cell_changes(changed_ids, Low)
  }
}
