///|
/// Core verification algorithm: determines if a cell's value may have changed
/// after the given revision.
///
/// This is the heart of the incremental computation framework. It answers
/// the question: "does this cell need to be recomputed?"
///
/// # Algorithm
///
/// - **Input cells**: Simply check `changed_at > after_revision`
/// - **Derived cells**: Apply fast paths first, then walk dependencies
///   iteratively using an explicit stack (to avoid stack overflow on deep graphs)
///
/// # Fast Paths (in order)
///
/// 1. **Already verified**: If `verified_at == current_revision`, return immediately
/// 2. **Durability shortcut**: If no input of this durability changed, return false
/// 3. **Cycle detection**: If cell is `in_progress`, return `Err(CycleError)`
///
/// # Parameters
///
/// - `rt`: The runtime containing cell metadata
/// - `cell_id`: The cell to check
/// - `after_revision`: The revision to compare against
///
/// # Returns
///
/// `Ok(true)` if the cell's value may have changed after `after_revision`,
/// `Ok(false)` if the cell is definitely unchanged,
/// `Err(CycleError)` if a cycle is detected
fn maybe_changed_after(
  rt : Runtime,
  cell_id : CellId,
  after_revision : Revision,
) -> Result[Bool, CycleError] {
  let cell = rt.get_cell(cell_id)
  match cell.kind {
    Input => Ok(cell.changed_at > after_revision)
    Derived => maybe_changed_after_derived(rt, cell, after_revision)
  }
}

///|
/// A frame on the explicit verification stack, replacing recursion.
///
/// Safety: `cell` is a reference, not a copy. In MoonBit, structs with `mut`
/// fields (like CellMeta) are heap-allocated and use reference semantics.
/// Mutations to `cell.in_progress`, `cell.verified_at`, etc. in
/// `finish_frame_changed` and `finish_frame_unchanged` affect the canonical
/// CellMeta stored in `Runtime.cells`, not a detached copy.
priv struct VerifyFrame {
  cell : CellMeta
  after_revision : Revision
  mut dep_index : Int
  mut any_dep_changed : Bool
}

///|
/// Cleans up the verification stack by clearing in_progress flags
/// on all cells. Called when an error occurs to restore consistent state.
fn cleanup_stack(stack : Array[VerifyFrame]) -> Unit {
  for i = 0; i < stack.length(); i = i + 1 {
    stack[i].cell.in_progress = false
  }
}

///|
/// Pop the top frame and propagate its result to the parent frame or final_result.
/// Called after both finish_frame_changed and finish_frame_unchanged.
fn pop_frame(
  stack : Array[VerifyFrame],
  path : Array[CellId],
  result : Bool,
  final_result : Ref[Bool],
) -> Unit {
  let _ = stack.pop()
  let _ = path.pop()
  if stack.length() > 0 {
    if result {
      stack[stack.length() - 1].any_dep_changed = true
    }
  } else {
    final_result.val = result
  }
}

///|
fn maybe_changed_after_derived(
  rt : Runtime,
  cell : CellMeta,
  after_revision : Revision,
) -> Result[Bool, CycleError] {
  // Use an explicit stack to avoid call-stack overflow on deep graphs
  let stack : Array[VerifyFrame] = []
  // Track the dependency path for cycle error diagnostics
  let path : Array[CellId] = []
  // Track the final result — set when the root frame completes
  let final_result : Ref[Bool] = { val: false }
  // Try to start verification on the root cell; if fast paths apply, return early
  match try_start_verify(rt, cell, after_revision, path) {
    Ok(Some(result)) => return Ok(result)
    Ok(None) => {
      // Need full dependency walk — push initial frame
      stack.push({ cell, after_revision, dep_index: 0, any_dep_changed: false })
      // Push root cell to path
      path.push(cell.id)
    }
    Err(e) => return Err(e)
  }
  // Iterative dependency walk
  // NOTE: Always access stack[top] directly to avoid copy semantics issues
  while stack.length() > 0 {
    let top = stack.length() - 1
    if stack[top].any_dep_changed {
      // A dependency changed — recompute this cell
      match finish_frame_changed(rt, stack[top]) {
        Ok(result) => pop_frame(stack, path, result, final_result)
        Err(e) => {
          cleanup_stack(stack)
          return Err(e)
        }
      }
      continue
    }
    let deps = stack[top].cell.dependencies
    if stack[top].dep_index >= deps.length() {
      // All dependencies checked, none changed — green path
      let result = finish_frame_unchanged(rt, stack[top])
      pop_frame(stack, path, result, final_result)
      continue
    }
    // Check next dependency
    let dep_id = deps[stack[top].dep_index]
    stack[top].dep_index = stack[top].dep_index + 1
    let dep_cell = rt.get_cell(dep_id)
    match dep_cell.kind {
      Input =>
        // Input cells are checked inline — no stack push needed
        if dep_cell.changed_at > stack[top].cell.verified_at {
          stack[top].any_dep_changed = true
        }
      Derived =>
        // Check fast paths for the derived dependency
        match
          try_start_verify(rt, dep_cell, stack[top].cell.verified_at, path) {
          Ok(Some(changed)) => if changed { stack[top].any_dep_changed = true }
          Ok(None) => {
            // Need full walk — push a new frame for this dependency
            stack.push({
              cell: dep_cell,
              after_revision: stack[top].cell.verified_at,
              dep_index: 0,
              any_dep_changed: false,
            })
            // Push dependency cell to path when entering new frame
            path.push(dep_cell.id)
          }
          Err(e) => {
            cleanup_stack(stack)
            return Err(e)
          }
        }
    }
  }
  Ok(final_result.val)
}

///|
/// Try to resolve a derived cell via fast paths. Returns `Ok(Some(result))` if
/// resolved, `Ok(None)` if a full dependency walk is needed, or
/// `Err(CycleError)` if a cycle is detected.
/// Sets in_progress flag if returning `Ok(None)`.
// Note: `path` is only read on the cycle-detection error path (see below).
// It has no effect on the verification logic itself — it is purely for
// building the CycleError diagnostic when a cycle is detected.
fn try_start_verify(
  rt : Runtime,
  cell : CellMeta,
  after_revision : Revision,
  path : Array[CellId],
) -> Result[Bool?, CycleError] {
  // Fast path: already verified this revision
  if cell.verified_at == rt.current_revision {
    return Ok(Some(cell.changed_at > after_revision))
  }
  // Durability shortcut
  let dur_idx = cell.durability.index()
  if not(rt.durability_last_changed[dur_idx] > after_revision) {
    cell.verified_at = rt.current_revision
    return Ok(Some(false))
  }
  // Cycle detection
  if cell.in_progress {
    // Cycle detected! Push the current cell to path to show the full cycle
    let full_path = Array::new(capacity=path.length() + 1)
    for i = 0; i < path.length(); i = i + 1 {
      full_path.push(path[i])
    }
    full_path.push(cell.id)
    return Err(CycleDetected(cell.id, full_path))
  }
  cell.in_progress = true
  Ok(None)
}

///|
/// Finish a frame where a dependency changed: recompute and return result.
/// Clear in_progress before recompute because force_recompute has its own
/// cycle detection. Set verified_at after recompute to maintain cache invariants.
///
/// Returns `Ok(changed)` where `changed` indicates if the value changed,
/// or `Err(CycleError)` if a cycle is detected during recomputation.
fn finish_frame_changed(
  _rt : Runtime,
  frame : VerifyFrame,
) -> Result[Bool, CycleError] {
  let cell = frame.cell
  // Clear in_progress before recompute — force_recompute handles its own cycle detection
  cell.in_progress = false
  match cell.recompute_and_check {
    Some(recompute) =>
      match recompute() {
        Ok(_) =>
          // force_recompute already sets verified_at and changed_at
          Ok(cell.changed_at > frame.after_revision)
        Err(e) => Err(e)
      }
    None => Ok(true)
  }
}

///|
/// Finish a frame where no dependency changed: green path.
fn finish_frame_unchanged(rt : Runtime, frame : VerifyFrame) -> Bool {
  let cell = frame.cell
  cell.verified_at = rt.current_revision
  cell.in_progress = false
  cell.changed_at > frame.after_revision
}
