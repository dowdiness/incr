///|
/// Runs fixpoint evaluation and publishes any resulting cell changes.
pub fn Runtime::fixpoint(self : Runtime) -> Unit {
  let changed_ids = self.evaluation_strategies.run_fixpoint(
    self.core,
    self.datalog,
  )
  if changed_ids.length() > 0 {
    self.publish_cell_changes(changed_ids, Low)
  }
  if self.has_pending_events() {
    self.drain_pending_events_if_idle()
  }
}
