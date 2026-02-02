///|
/// Core verification algorithm. Returns true if the cell's value may have
/// changed after the given revision.
///
/// For inputs: simply checks changed_at > after_revision.
/// For derived: walks dependencies recursively, recomputing only when needed.
pub fn maybe_changed_after(
  rt : Runtime,
  cell_id : CellId,
  after_revision : Revision,
) -> Bool {
  let cell = rt.get_cell(cell_id)
  match cell.kind {
    Input => cell.changed_at.after(after_revision)
    Derived => maybe_changed_after_derived(rt, cell, after_revision)
  }
}

///|
fn maybe_changed_after_derived(
  rt : Runtime,
  cell : CellMeta,
  after_revision : Revision,
) -> Bool {
  // Fast path: already verified this revision
  if cell.verified_at == rt.current_revision {
    return cell.changed_at.after(after_revision)
  }
  // Durability shortcut: if no input of this durability (or lower) changed
  // since after_revision, the cell cannot have changed
  let dur_idx = cell.durability.index()
  if not(rt.durability_last_changed[dur_idx].after(after_revision)) {
    cell.verified_at = rt.current_revision
    return false
  }
  // Cycle detection
  if cell.in_progress {
    abort("Cycle detected: cell " + cell.id.to_string() + " is already being verified")
  }
  cell.in_progress = true
  // Walk dependencies: check if any dependency changed
  let deps = cell.dependencies
  let mut any_dep_changed = false
  for i = 0; i < deps.length(); i = i + 1 {
    if maybe_changed_after(rt, deps[i], cell.verified_at) {
      any_dep_changed = true
      break
    }
  }
  if any_dep_changed {
    // A dependency changed — recompute this cell to check if value actually changed.
    // This is critical for backdating: if the recomputed value is the same,
    // changed_at is kept old and downstream cells can skip recomputation.
    cell.in_progress = false
    match cell.recompute_and_check {
      Some(recompute) => {
        let _ = recompute()
        // After recompute, force_recompute already set verified_at and changed_at
        return cell.changed_at.after(after_revision)
      }
      None => return true // Should not happen for derived cells
    }
  }
  // No dependency changed — green path: mark verified, value unchanged
  cell.verified_at = rt.current_revision
  cell.in_progress = false
  cell.changed_at.after(after_revision)
}
