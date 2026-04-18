///|
/// Construct a CycleError from a path of cell IDs and the cell that closes
/// the cycle.
///
/// Copies `path`, appends `closing_id`, and snapshots labels for the leading
/// `MAX_CYCLE_DISPLAY_STEPS` entries via `rt.cell_info`. This keeps the
/// rendered output informative (labels-when-available) while bounding memory
/// at a small multiple of the display cap even for pathological long cycles.
///
/// Callers provide whatever path they have collected (tracking-stack IDs or
/// verification-frame IDs) without exposing runtime internals beyond label
/// lookup.
fn CycleError::from_path(
  rt : Runtime,
  path : Array[CellId],
  closing_id : CellId,
) -> CycleError {
  let full_path = path.copy()
  full_path.push(closing_id)
  let label_cap = if full_path.length() < @incr_types.MAX_CYCLE_DISPLAY_STEPS {
    full_path.length()
  } else {
    @incr_types.MAX_CYCLE_DISPLAY_STEPS
  }
  let labels : Array[String?] = []
  for i in 0..<label_cap {
    let label = match rt.cell_info(full_path[i]) {
      Some(info) => info.label
      None => None
    }
    labels.push(label)
  }
  CycleDetected(closing_id, full_path, labels)
}
