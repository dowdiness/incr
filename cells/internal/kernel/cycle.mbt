///|
/// Construct a CycleError from a path of cell IDs and the cell that closes
/// the cycle.
///
/// Copies `path`, appends `closing_id`, and snapshots labels for the leading
/// `MAX_CYCLE_DISPLAY_STEPS` entries via `core.cell_ops[i].label()`. Moved
/// from cells/cycle.mbt in R1 Stage 3b — the cells/ caller chain runs entirely
/// through kernel now (verify, memo_force_recompute), so kernel owns the
/// constructor.
pub fn construct_cycle_error(
  core : RuntimeCore,
  path : Array[CellId],
  closing_id : CellId,
) -> @incr_types.CycleError {
  let full_path = path.copy()
  full_path.push(closing_id)
  let label_cap = if full_path.length() < @incr_types.MAX_CYCLE_DISPLAY_STEPS {
    full_path.length()
  } else {
    @incr_types.MAX_CYCLE_DISPLAY_STEPS
  }
  let labels : Array[String?] = []
  for i in 0..<label_cap {
    let cell_id = full_path[i]
    let label = if cell_id.id >= 0 && cell_id.id < core.cell_ops.length() {
      core.cell_ops[cell_id.id].label()
    } else {
      None
    }
    labels.push(label)
  }
  @incr_types.CycleError::new(closing_id, full_path, labels)
}
