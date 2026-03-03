///|
/// A frame on the SoA-based verification stack used by `pull_verify`.
///
/// Tracks iteration progress through one memo's dependency list. Uses
/// array indices into `Runtime.pull_memos` for direct access without
/// going through CellMeta.
priv struct PullVerifyFrame {
  cell_id : CellId
  memo_idx : Int
  mut dep_cursor : Int
  mut changed : Bool
}

///|
/// SoA-native verification: determines whether a cell needs recomputation
/// and recomputes it if so, using explicit stack iteration over `pull_memos`.
///
/// This is the SoA replacement for `maybe_changed_after`. It dispatches
/// directly on `cell_index` and accesses `PullMemoData` entries without
/// going through `CellMeta`.
///
/// # Algorithm
///
/// - **PullSignal**: Always fresh — returns `Ok(())` immediately.
/// - **PullMemo**: Walks dependencies iteratively with an explicit
///   `PullVerifyFrame` stack. On green path (no dep changed), marks
///   `verified_at` without recomputation. On changed path, calls the
///   type-erased `compute` closure, which handles backdating.
///
/// # Returns
///
/// `Ok(())` on success (cell is up-to-date after this call),
/// `Err(CycleError)` if a cycle is detected
fn Runtime::pull_verify(
  self : Runtime,
  cell_id : CellId,
) -> Result[Unit, CycleError] {
  match self.cell_index[cell_id.id] {
    PullSignal(_) => Ok(()) // always fresh
    PullMemo(root_idx) => {
      let root = self.pull_memos[root_idx]
      if root.verified_at >= self.current_revision {
        return Ok(())
      }
      if root.in_progress {
        return Err(
          CycleError::from_path(self.collect_in_progress_path(), cell_id),
        )
      }
      let stack : Array[PullVerifyFrame] = []
      root.in_progress = true
      stack.push({ cell_id, memo_idx: root_idx, dep_cursor: 0, changed: false })
      while stack.length() > 0 {
        let top = stack.length() - 1
        let memo = self.pull_memos[stack[top].memo_idx]
        if stack[top].dep_cursor < memo.dependencies.length() {
          // Advance cursor and inspect the next dependency.
          let dep_id = memo.dependencies[stack[top].dep_cursor]
          stack[top].dep_cursor = stack[top].dep_cursor + 1
          match self.cell_index[dep_id.id] {
            PullMemo(dep_idx) => {
              let dep = self.pull_memos[dep_idx]
              if dep.verified_at < self.current_revision {
                // Dep needs verification; push a new frame.
                if dep.in_progress {
                  // Cycle detected — collect path, clear flags, return error.
                  let path = self.collect_in_progress_path()
                  for frame in stack {
                    self.pull_memos[frame.memo_idx].in_progress = false
                  }
                  return Err(CycleError::from_path(path, dep_id))
                }
                dep.in_progress = true
                stack.push({
                  cell_id: dep_id,
                  memo_idx: dep_idx,
                  dep_cursor: 0,
                  changed: false,
                })
              } else {
                // Already verified this revision; check if its value changed.
                if dep.changed_at > memo.verified_at {
                  stack[top].changed = true
                }
              }
            }
            _ => {
              // PullSignal: check changed_at directly.
              if self.get_changed_at(dep_id) > memo.verified_at {
                stack[top].changed = true
              }
            }
          }
        } else {
          // All deps inspected; finalize this memo.
          let frame_changed = stack[top].changed
          let _ = stack.pop()
          // memo is still valid — PullMemoData is heap-allocated (has mut fields)
          memo.in_progress = false
          if frame_changed {
            match (memo.compute)() {
              Ok(_) => () // recompute done; may backdate memo.changed_at
              Err(e) => {
                // Clean up remaining in_progress flags before propagating error.
                for frame in stack {
                  self.pull_memos[frame.memo_idx].in_progress = false
                }
                return Err(e)
              }
            }
          }
          memo.verified_at = self.current_revision
          // Tell the parent frame whether this memo's value changed.
          if stack.length() > 0 {
            let parent_top = stack.length() - 1
            let parent_memo = self.pull_memos[stack[parent_top].memo_idx]
            if memo.changed_at > parent_memo.verified_at {
              stack[parent_top].changed = true
            }
          }
        }
      }
      Ok(())
    }
  }
}
