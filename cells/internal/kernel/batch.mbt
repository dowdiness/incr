///|
/// Batch commit coordinator.
///
/// Preservation checklist (I4 + supporting invariants, see docs/plans/
/// 2026-04-24-r1-stage4-notes.md §2.B):
///
/// 1. Snapshot-before-propagate [I4]: callbacks array built BEFORE
///    `propagate_changes` so PushReactive compute closures that call
///    `set_on_change`/`clear_on_change` cannot affect which handlers fire
///    in this wave.
/// 2. Outer `while pending.length() > 0` wave loop processes
///    callback-queued signals in later waves.
/// 3. Temporary `batch.depth` raise around the callback loop prevents
///    re-entrant `fire_on_change` when a callback calls `Signal::set`.
/// 4. `any_changed` accumulator fires the final global `on_change`
///    exactly once after all waves complete.
/// 5. `max_durability = Low` resets on all three paths (changed branch,
///    no-change branch, after the while loop).
///
/// Commit pending batch changes using two-phase values.
/// Phase 1: commit each signal's pending value, collecting which actually changed.
/// Phase 2: if any changed, single revision bump and metadata update.
/// Loops until no more callbacks queue additional signals, then fires the
/// global on_change callback exactly once if anything changed.
pub fn commit_batch(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
) -> Unit {
  let mut any_changed = false
  while core.batch.pending.length() > 0 {
    // Phase 1: commit pending values and collect which actually changed
    let changed : Array[&Committable] = []
    for c in core.batch.pending {
      if c.do_commit() {
        changed.push(c)
      }
    }
    core.batch.pending.clear()
    // Phase 2: if any value actually changed, do a single revision bump
    if changed.length() > 0 {
      any_changed = true
      // Snapshot on_change callbacks BEFORE propagation — preserves the
      // invariant that push propagation cannot affect which handlers fire
      // in this batch wave (a PushReactive's compute closure could call
      // clear_on_change() or on_change() on a changed signal).
      let callbacks : Array[() -> Unit] = []
      for c in changed {
        let cell_id = c.cell_id()
        validate_cell(core, cell_id, "commit_batch")
        let sig = match core.cell_index[cell_id.id] {
          PullSignal(idx) => pull.signals[idx]
          _ =>
            abort(
              "Expected signal cell but found different kind: " +
              cell_id.id.to_string(),
            )
        }
        match sig.on_change {
          Some(f) => callbacks.push(f)
          None => ()
        }
      }
      let changed_ids : Array[CellId] = changed.map(fn(c) { c.cell_id() })
      propagate_changes(
        core,
        pull,
        push,
        datalog,
        changed_ids,
        core.batch.max_durability,
      )
      core.batch.max_durability = Low
      // Raise batch_depth while invoking callbacks so that any signal.set()
      // inside a callback takes the batch path instead of set_unconditional,
      // preventing re-entrant fire_on_change() calls.
      // If callbacks queue more signals, the while loop will process them.
      core.batch.depth = core.batch.depth + 1
      for cb in callbacks {
        cb()
      }
      core.batch.depth = core.batch.depth - 1
    } else {
      core.batch.max_durability = Low
    }
  }
  core.batch.max_durability = Low
  // Fire global on_change exactly once after all waves complete.
  if any_changed {
    fire_on_change(core)
  }
}
