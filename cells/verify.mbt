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

///|
/// Clears the `in_progress` flag on every memo referenced by the stack.
///
/// Called on error exit paths (cycle detection, compute failure) so that
/// no memo is left permanently stuck as in-progress.
fn clear_verify_stack(rt : Runtime, stack : Array[PullVerifyFrame]) -> Unit {
  for frame in stack {
    rt.pull.memos[frame.memo_idx].in_progress = false
  }
}

///|
fn Runtime::pull_verify(
  self : Runtime,
  cell_id : CellId,
) -> Result[Unit, CycleError] {
  if cell_id.runtime_id != self.core.runtime_id {
    abort("pull_verify: cell belongs to a different Runtime")
  }
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    abort("pull_verify: cell_id out of bounds: " + cell_id.id.to_string())
  }
  match self.core.cell_index[cell_id.id] {
    PullSignal(_) => Ok(()) // always fresh
    PushReactive(_) | PushEffect(_) => Ok(()) // freshness via push_propagate_from
    HybridMemo(_) => Ok(()) // freshness managed by HybridMemo::get
    Relation(_) | Rule(_) => {
      if self.datalog.in_fixpoint {
        abort("pull_verify: cannot verify Relation/Rule during fixpoint()")
      }
      Ok(())
    }
    Disposed => abort("pull_verify: cell has been disposed")
    PullMemo(root_idx) => {
      let root = self.pull.memos[root_idx]
      if root.verified_at >= self.core.current_revision {
        return Ok(())
      }
      // Durability fast-path: if no input at root's durability level changed
      // since root was last verified, mark verified without walking deps.
      if self.core.durability_last_changed[root.durability.index()] <=
        root.verified_at {
        root.verified_at = self.core.current_revision
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
        let memo = self.pull.memos[stack[top].memo_idx]
        if stack[top].dep_cursor < memo.dependencies.length() {
          // Advance cursor and inspect the next dependency.
          let dep_id = memo.dependencies[stack[top].dep_cursor]
          stack[top].dep_cursor = stack[top].dep_cursor + 1
          if dep_id.runtime_id != self.core.runtime_id {
            abort(
              "pull_verify: dependency belongs to a different Runtime: " +
              dep_id.id.to_string(),
            )
          }
          // Single cell_index lookup: fixpoint guard + disposed check.
          match self.core.cell_index[dep_id.id] {
            Disposed => abort("pull_verify: dependency has been disposed")
            Relation(_) | Rule(_) =>
              if self.datalog.in_fixpoint {
                clear_verify_stack(self, stack)
                abort(
                  "pull_verify: cannot verify memo with Relation dependency during fixpoint()",
                )
              }
            _ => ()
          }
          let dep_ops = self.core.cell_ops[dep_id.id]
          match dep_ops.dep_changed_since(memo.verified_at) {
            Some(true) => {
              stack[top].changed = true
              stack[top].dep_cursor = memo.dependencies.length()
            }
            Some(false) => ()
            None =>
              // Needs deep verification — only PullMemo and HybridMemo reach here
              match self.core.cell_index[dep_id.id] {
                PullMemo(dep_idx) => {
                  let dep = self.pull.memos[dep_idx]
                  if dep.verified_at < self.core.current_revision {
                    // Durability shortcut: if no input at dep's durability level
                    // changed since dep was last verified, skip traversal.
                    if self.core.durability_last_changed[dep.durability.index()] <=
                      dep.verified_at {
                      dep.verified_at = self.core.current_revision
                      if dep.changed_at > memo.verified_at {
                        stack[top].changed = true
                        stack[top].dep_cursor = memo.dependencies.length()
                      }
                    } else {
                      // Dep needs verification; push a new frame.
                      if dep.in_progress {
                        // Cycle detected — build path from stack (traversal order),
                        // clear flags, return error.
                        let path : Array[CellId] = []
                        for frame in stack {
                          path.push(frame.cell_id)
                        }
                        clear_verify_stack(self, stack)
                        return Err(CycleError::from_path(path, dep_id))
                      }
                      dep.in_progress = true
                      stack.push({
                        cell_id: dep_id,
                        memo_idx: dep_idx,
                        dep_cursor: 0,
                        changed: false,
                      })
                    }
                    // Already verified this revision; check if its value changed.
                  } else if dep.changed_at > memo.verified_at {
                    stack[top].changed = true
                    stack[top].dep_cursor = memo.dependencies.length()
                  }
                }
                HybridMemo(_) =>
                  match self.pull_verify_hybrid(dep_id) {
                    Ok(_) =>
                      if dep_ops.changed_at() > memo.verified_at {
                        stack[top].changed = true
                        stack[top].dep_cursor = memo.dependencies.length()
                      }
                    Err(e) => {
                      clear_verify_stack(self, stack)
                      return Err(e)
                    }
                  }
                _ => () // unreachable — Disposed caught above; only memo-like cells return None
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
                clear_verify_stack(self, stack)
                return Err(e)
              }
            }
          }
          memo.verified_at = self.core.current_revision
          // Tell the parent frame whether this memo's value changed.
          if stack.length() > 0 {
            let parent_top = stack.length() - 1
            let parent_memo = self.pull.memos[stack[parent_top].memo_idx]
            if memo.changed_at > parent_memo.verified_at {
              stack[parent_top].changed = true
              stack[parent_top].dep_cursor = parent_memo.dependencies.length()
            }
          }
        }
      }
      Ok(())
    }
  }
}

///|
/// Verifies a HybridMemo cell, walking its dep list directly.
///
/// Unlike `pull_verify` (which skips `HybridMemo` roots as "managed by
/// HybridMemo::get"), this function performs the actual dep walk for a
/// HybridMemo root. Called by `HybridMemo::get` on the slow path.
///
/// PullMemo deps are verified recursively via `pull_verify`. Hybrid deps are
/// reverified via `pull_verify_hybrid` so dirty-but-not-recomputed hybrids
/// cannot appear fresh based only on stale `changed_at`.
fn Runtime::pull_verify_hybrid(
  self : Runtime,
  cell_id : CellId,
) -> Result[Unit, CycleError] {
  if cell_id.runtime_id != self.core.runtime_id {
    abort("pull_verify_hybrid: cell belongs to a different Runtime")
  }
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    abort(
      "pull_verify_hybrid: cell_id out of bounds: " + cell_id.id.to_string(),
    )
  }
  let root_idx = match self.core.cell_index[cell_id.id] {
    HybridMemo(i) => i
    _ => abort("pull_verify_hybrid: not a HybridMemo")
  }
  let root = self.push.hybrid_memos[root_idx]
  // Fast path: skip only when not dirty AND already verified this revision.
  // A dirty hybrid memo must always re-verify even if verified_at is current,
  // because push propagation may have dirtied it after the last verification.
  if not(root.dirty) && root.verified_at >= self.core.current_revision {
    return Ok(())
  }
  // Durability shortcut: if no input at this durability level changed since
  // the last verification, mark verified without walking deps.
  if self.core.durability_last_changed[root.durability.index()] <=
    root.verified_at {
    root.verified_at = self.core.current_revision
    return Ok(())
  }
  if root.in_progress {
    return Err(CycleError::from_path(self.collect_in_progress_path(), cell_id))
  }
  root.in_progress = true
  let verified_at_snap = root.verified_at
  let mut dep_changed = false
  let mut idx = 0
  while idx < root.dependencies.length() && not(dep_changed) {
    let dep_id = root.dependencies[idx]
    idx = idx + 1
    if dep_id.runtime_id != self.core.runtime_id {
      abort(
        "pull_verify_hybrid: dependency belongs to a different Runtime: " +
        dep_id.id.to_string(),
      )
    }
    // Single cell_index lookup: fixpoint guard + disposed check.
    match self.core.cell_index[dep_id.id] {
      Disposed => {
        root.in_progress = false
        abort("pull_verify_hybrid: dependency has been disposed")
      }
      Relation(_) | Rule(_) =>
        if self.datalog.in_fixpoint {
          root.in_progress = false
          abort(
            "pull_verify_hybrid: cannot verify HybridMemo with Relation dependency during fixpoint()",
          )
        }
      _ => ()
    }
    let dep_ops = self.core.cell_ops[dep_id.id]
    match dep_ops.dep_changed_since(verified_at_snap) {
      Some(true) => dep_changed = true
      Some(false) => ()
      None =>
        // Needs deep verification — only PullMemo and HybridMemo reach here
        match self.core.cell_index[dep_id.id] {
          PullMemo(_) =>
            match self.pull_verify(dep_id) {
              Ok(_) =>
                if dep_ops.changed_at() > verified_at_snap {
                  dep_changed = true
                }
              Err(e) => {
                root.in_progress = false
                return Err(e)
              }
            }
          HybridMemo(_) =>
            match self.pull_verify_hybrid(dep_id) {
              Ok(_) =>
                if dep_ops.changed_at() > verified_at_snap {
                  dep_changed = true
                }
              Err(e) => {
                root.in_progress = false
                return Err(e)
              }
            }
          _ => () // unreachable — Disposed caught above; only memo-like cells return None
        }
    }
  }
  root.in_progress = false
  if dep_changed {
    match (root.compute)() {
      Ok(_) => () // force_recompute handles verified_at + backdating
      Err(e) => return Err(e)
    }
  } else {
    root.verified_at = self.core.current_revision
  }
  Ok(())
}
