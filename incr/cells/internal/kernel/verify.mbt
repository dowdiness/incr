///|
/// A frame on the SoA-based verification stack used by `pull_verify`.
///
/// Tracks iteration progress through one memo's dependency list. Uses
/// array indices into `PullState.memos` for direct access without
/// going through CellMeta.
priv struct PullVerifyFrame {
  cell_id : CellId
  memo_idx : Int32
  mut dep_cursor : Int32
  mut changed : Bool
}

///|
/// Clears the `in_progress` flag on every memo referenced by the stack.
///
/// Called on error exit paths (cycle detection, compute failure) so that
/// no memo is left permanently stuck as in-progress.
fn clear_verify_stack(pull : PullState, stack : Array[PullVerifyFrame]) -> Unit {
  for frame in stack {
    pull.memos[frame.memo_idx].in_progress = false
  }
}

///|
fn derived_is_revision_fresh(
  core : RuntimeCore,
  derived : @pull.MemoData,
) -> Bool {
  derived.verified_at >= core.revision.current_revision
}

///|
fn can_skip_dep_walk_by_durability(
  core : RuntimeCore,
  derived : @pull.MemoData,
) -> Bool {
  derived.accumulator_reads.is_empty() &&
  core.revision.durability_last_changed[derived.meta.durability.index()] <=
  derived.verified_at
}

///|
priv enum DependencyFreshness {
  DependencyUnchanged
  DependencyChanged
  DependencyNeedsVerification(Int32)
}

///|
fn classify_dependency_freshness(
  core : RuntimeCore,
  dep_id : CellId,
  dep_variant : CellRef,
  verified_at : Revision,
) -> DependencyFreshness {
  let dep_ops = core.cell_ops[dep_id.id]
  match dep_ops.dep_changed_since(verified_at) {
    Some(true) => DependencyChanged
    Some(false) => DependencyUnchanged
    None =>
      match dep_variant {
        PullMemo(dep_idx) | HybridMemo(dep_idx) =>
          DependencyNeedsVerification(dep_idx)
        _ => DependencyUnchanged
      }
  }
}

///|
fn enter_pull_frame(
  stack : Array[PullVerifyFrame],
  derived : @pull.MemoData,
  cell_id : CellId,
  derived_idx : Int32,
) -> Unit {
  derived.in_progress = true
  stack.push({ cell_id, memo_idx: derived_idx, dep_cursor: 0, changed: false, })
}

///|
fn abort_pull_rebuild(pull : PullState, stack : Array[PullVerifyFrame]) -> Unit {
  clear_verify_stack(pull, stack)
}

///|
fn run_pull_recompute(
  pull : PullState,
  stack : Array[PullVerifyFrame],
  derived : @pull.MemoData,
  changed : Bool,
) -> Unit raise Error {
  if !changed {
    return
  }
  errdefer abort_pull_rebuild(pull, stack)
  ignore((derived.compute)())
}

///|
fn commit_pull_rebuild(
  core : RuntimeCore,
  pull : PullState,
  stack : Array[PullVerifyFrame],
  derived : @pull.MemoData,
) -> Unit {
  derived.verified_at = core.revision.current_revision
  if stack.length() > 0 {
    let parent_top = stack.length() - 1
    let parent_derived = pull.memos[stack[parent_top].memo_idx]
    if derived.meta.changed_at > parent_derived.verified_at {
      stack[parent_top].changed = true
      stack[parent_top].dep_cursor = parent_derived.dependencies.length()
    }
  }
}

///|
/// Returns `true` if any synthetic accumulator dep of `memo` has been
/// invalidated (target/slot disposed, or producer `push_revised_at` advanced
/// past the stored read revision). Returns `false` if all synthetic deps
/// are still current. Raises `CycleError` if a recursive `pull_verify` on a
/// target surfaces a cycle.
///
/// Runs during per-frame finalize in `pull_verify`. The caller keeps
/// `memo.in_progress = true` across this call so that a recursive verify of
/// a target that transitively depends on `memo` is detected as a cycle.
fn synthetic_accumulator_changed(
  core : RuntimeCore,
  pull : PullState,
  slot_snapshots : Array[&@shared.SlotSnapshot],
  memo : @pull.MemoData,
) -> Bool raise Error {
  if memo.accumulator_reads.is_empty() {
    return false
  }
  for entry in memo.accumulator_reads {
    let slot_id = entry.0.0
    let target_id = entry.0.1
    let stored_rev = entry.1
    if slot_id.id >= slot_snapshots.length() ||
      slot_snapshots[slot_id.id].disposed() {
      return true
    }
    if is_cell_disposed(core, target_id) {
      return true
    }
    pull_verify(core, pull, slot_snapshots, target_id)
    let current_rev = slot_snapshots[slot_id.id].push_revised_at_for(target_id)
    if current_rev > stored_rev {
      return true
    }
  }
  false
}

///|
/// SoA-native verification: determines whether a cell needs recomputation
/// and recomputes it if so, using explicit stack iteration over `pull.memos`.
/// Takes the accumulator snapshot array explicitly so kernel does not
/// depend on Runtime's accumulator state.
pub fn pull_verify(
  core : RuntimeCore,
  pull : PullState,
  slot_snapshots : Array[&@shared.SlotSnapshot],
  cell_id : CellId,
) -> Unit raise Error {
  validate_cell(core, cell_id, "pull_verify")
  match core.cell_index[cell_id.id] {
    PullInput(_) => () // always fresh
    PushReactive(_) | PushEffect(_) => () // freshness via push_propagate_from
    Relation(_) | FunctionalRelation(_) | Rule(_) =>
      if core.phase is InFixpoint {
        abort("pull_verify: cannot verify Relation/Rule during fixpoint()")
      }
    Disposed => abort("pull_verify: cell has been disposed")
    PullMemo(root_idx) | HybridMemo(root_idx) => {
      let root = pull.memos[root_idx]
      if derived_is_revision_fresh(core, root) {
        return
      }
      // Durability fast-path: if no input at root's durability level changed
      // since root was last verified, mark verified without walking deps.
      // SKIP this optimization when root has accumulator_reads — synthetic
      // deps can be invalidated by low-durability pushes that don't appear
      // in the durability index.
      if can_skip_dep_walk_by_durability(core, root) {
        root.verified_at = core.revision.current_revision
        return
      }
      if root.in_progress {
        raise construct_cycle_error(
          core,
          collect_in_progress_path(pull),
          cell_id,
        )
      }
      let stack : Array[PullVerifyFrame] = []
      enter_pull_frame(stack, root, cell_id, root_idx)
      while stack.length() > 0 {
        let top = stack.length() - 1
        let memo = pull.memos[stack[top].memo_idx]
        if stack[top].dep_cursor < memo.dependencies.length() {
          // Advance cursor and inspect the next dependency.
          let dep_id = memo.dependencies[stack[top].dep_cursor]
          stack[top].dep_cursor = stack[top].dep_cursor + 1
          if dep_id.runtime_id != core.runtime_id {
            abort(
              "pull_verify: dependency belongs to a different Runtime: " +
              dep_id.id.to_string(),
            )
          }
          // Single cell_index read per dep: one match for the structural
          // guard (disposed/fixpoint) reused below for the deep-verify
          // dispatch in the `None` branch.
          let dep_variant = core.cell_index[dep_id.id]
          match dep_variant {
            Disposed => abort("pull_verify: dependency has been disposed")
            Relation(_) | FunctionalRelation(_) | Rule(_) =>
              if core.phase is InFixpoint {
                abort_pull_rebuild(pull, stack)
                abort(
                  "pull_verify: cannot verify memo with Relation dependency during fixpoint()",
                )
              }
            _ => ()
          }
          match
            classify_dependency_freshness(
              core,
              dep_id,
              dep_variant,
              memo.verified_at,
            ) {
            DependencyChanged => {
              stack[top].changed = true
              stack[top].dep_cursor = memo.dependencies.length()
            }
            DependencyUnchanged => ()
            DependencyNeedsVerification(dep_idx) => {
              let dep = pull.memos[dep_idx]
              if !derived_is_revision_fresh(core, dep) {
                // Durability shortcut: if no input at dep's durability level
                // changed since dep was last verified, skip traversal.
                // SKIP when dep has accumulator_reads (synthetic deps
                // need the walk to check push_revised_at).
                if can_skip_dep_walk_by_durability(core, dep) {
                  dep.verified_at = core.revision.current_revision
                  if dep.meta.changed_at > memo.verified_at {
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
                    abort_pull_rebuild(pull, stack)
                    raise construct_cycle_error(core, path, dep_id)
                  }
                  enter_pull_frame(stack, dep, dep_id, dep_idx)
                }
              } else if dep.meta.changed_at > memo.verified_at {
                stack[top].changed = true
                stack[top].dep_cursor = memo.dependencies.length()
              }
            }
          }
        } else {
          // All deps inspected; finalize this memo. Check synthetic
          // accumulator deps BEFORE clearing in_progress — recursive
          // pull_verify calls on target memos must observe this frame
          // as in-progress so that a cycle through an accumulator
          // producer is detected.
          let acc_changed = {
            errdefer abort_pull_rebuild(pull, stack)
            synthetic_accumulator_changed(core, pull, slot_snapshots, memo)
          }
          let frame_changed = stack[top].changed || acc_changed
          let _ = stack.pop()
          // memo is still valid — MemoData is heap-allocated (has mut fields)
          memo.in_progress = false
          run_pull_recompute(pull, stack, memo, frame_changed)
          commit_pull_rebuild(core, pull, stack, memo)
        }
      }
    }
  }
}
