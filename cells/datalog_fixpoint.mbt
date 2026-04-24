///|
/// Thin Runtime wrapper over `@kernel.run_fixpoint`.
///
/// Kernel owns the fixpoint loop (R1 Stage 3g). The wrapper invokes
/// publish_cell_changes on the changed-id set; it collapses to a
/// one-liner when Stage 4 moves publish_cell_changes to kernel.
pub fn Runtime::fixpoint(self : Runtime) -> Unit {
  let changed_ids = @kernel.run_fixpoint(self.core, self.datalog)
  if changed_ids.length() > 0 {
    self.publish_cell_changes(changed_ids, Low)
  }
}
