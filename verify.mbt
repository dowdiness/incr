///|
/// Core verification algorithm. Returns true if the cell's value may have
/// changed after the given revision.
///
/// For inputs: simply checks changed_at > after_revision.
/// For derived: walks dependencies iteratively, recomputing only when needed.
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
fn maybe_changed_after_derived(
  rt : Runtime,
  cell : CellMeta,
  after_revision : Revision,
) -> Bool {
  // Use an explicit stack to avoid call-stack overflow on deep graphs
  let stack : Array[VerifyFrame] = []
  // Track the final result — set when the root frame completes
  let mut final_result = false
  // Try to start verification on the root cell; if fast paths apply, return early
  match try_start_verify(rt, cell, after_revision) {
    Some(result) => return result
    None => {
      // Need full dependency walk — push initial frame
      stack.push({ cell, after_revision, dep_index: 0, any_dep_changed: false })
    }
  }
  // Iterative dependency walk
  // NOTE: Always access stack[top] directly to avoid copy semantics issues
  while stack.length() > 0 {
    let top = stack.length() - 1
    if stack[top].any_dep_changed {
      // A dependency changed — recompute this cell
      let result = finish_frame_changed(rt, stack[top])
      let _ = stack.pop()
      if stack.length() > 0 {
        if result {
          stack[stack.length() - 1].any_dep_changed = true
        }
      } else {
        final_result = result
      }
      continue
    }
    let deps = stack[top].cell.dependencies
    if stack[top].dep_index >= deps.length() {
      // All dependencies checked, none changed — green path
      let result = finish_frame_unchanged(rt, stack[top])
      let _ = stack.pop()
      if stack.length() > 0 {
        if result {
          stack[stack.length() - 1].any_dep_changed = true
        }
      } else {
        final_result = result
      }
      continue
    }
    // Check next dependency
    let dep_id = deps[stack[top].dep_index]
    stack[top].dep_index = stack[top].dep_index + 1
    let dep_cell = rt.get_cell(dep_id)
    match dep_cell.kind {
      Input => {
        // Input cells are checked inline — no stack push needed
        if dep_cell.changed_at.after(stack[top].cell.verified_at) {
          stack[top].any_dep_changed = true
        }
      }
      Derived => {
        // Check fast paths for the derived dependency
        match try_start_verify(rt, dep_cell, stack[top].cell.verified_at) {
          Some(changed) => {
            if changed {
              stack[top].any_dep_changed = true
            }
          }
          None => {
            // Need full walk — push a new frame for this dependency
            stack.push(
              {
                cell: dep_cell,
                after_revision: stack[top].cell.verified_at,
                dep_index: 0,
                any_dep_changed: false,
              },
            )
          }
        }
      }
    }
  }
  final_result
}

///|
/// Try to resolve a derived cell via fast paths. Returns Some(result) if
/// resolved, None if a full dependency walk is needed.
/// Sets in_progress flag if returning None.
fn try_start_verify(
  rt : Runtime,
  cell : CellMeta,
  after_revision : Revision,
) -> Bool? {
  // Fast path: already verified this revision
  if cell.verified_at == rt.current_revision {
    return Some(cell.changed_at.after(after_revision))
  }
  // Durability shortcut
  let dur_idx = cell.durability.index()
  if not(rt.durability_last_changed[dur_idx].after(after_revision)) {
    cell.verified_at = rt.current_revision
    return Some(false)
  }
  // Cycle detection
  if cell.in_progress {
    abort(
      "Cycle detected: cell " + cell.id.to_string() + " is already being verified",
    )
  }
  cell.in_progress = true
  None
}

///|
/// Finish a frame where a dependency changed: recompute and return result.
/// Clear in_progress before recompute because force_recompute has its own
/// cycle detection. Set verified_at after recompute to maintain cache invariants.
fn finish_frame_changed(_rt : Runtime, frame : VerifyFrame) -> Bool {
  let cell = frame.cell
  // Clear in_progress before recompute — force_recompute handles its own cycle detection
  cell.in_progress = false
  match cell.recompute_and_check {
    Some(recompute) => {
      let _ = recompute()
      // force_recompute already sets verified_at and changed_at
      cell.changed_at.after(frame.after_revision)
    }
    None => true
  }
}

///|
/// Finish a frame where no dependency changed: green path.
fn finish_frame_unchanged(rt : Runtime, frame : VerifyFrame) -> Bool {
  let cell = frame.cell
  cell.verified_at = rt.current_revision
  cell.in_progress = false
  cell.changed_at.after(frame.after_revision)
}
