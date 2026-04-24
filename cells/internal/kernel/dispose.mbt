///|
/// Pure-state dispose helpers.
///
/// The `Runtime::dispose_cell` coordinator stays in `cells/runtime.mbt`
/// because `CellLifecycle::dispose_cell(Runtime, CellId)` takes a full
/// `Runtime` (retyping the trait is out of R1 scope). Only the
/// Runtime-field-free bits live here.

///|
/// Validates that `cell_id` belongs to this runtime and is live enough to
/// dispose. Returns `true` if the caller should proceed with dispose,
/// `false` if the cell is already disposed (idempotent short-circuit).
/// Aborts on cross-runtime CellId.
pub fn validate_cell_for_dispose(core : RuntimeCore, cell_id : CellId) -> Bool {
  guard cell_id.runtime_id == core.runtime_id else {
    abort("dispose_cell: CellId belongs to a different Runtime")
  }
  !is_cell_disposed(core, cell_id)
}

///|
/// Drops the GC observer reference-count entry for a cell being disposed.
/// Prevents leaks when observed cells are manually disposed before their
/// observers.
pub fn drop_gc_root(core : RuntimeCore, cell_id : CellId) -> Unit {
  core.gc_root_counts.remove(cell_id)
}

///|
/// Guards against disposing a cell during fixpoint or its own computation.
pub fn check_dispose_guard(core : RuntimeCore, cell_id : CellId) -> Unit {
  guard !(core.phase is InFixpoint) else {
    abort("dispose: cannot dispose cells during fixpoint()")
  }
  for aq in core.tracking.stack {
    guard aq.cell_id != cell_id else {
      abort("dispose: cannot dispose a cell during its own computation")
    }
  }
}
