///|
/// Undo entry for one signal touched by a batch frame.
priv struct BatchUndo {
  cell_id : CellId
  rollback : () -> Unit
}

///|
/// Per-batch-frame rollback log for nested batch semantics.
priv struct BatchFrame {
  undo_entries : Array[BatchUndo]
  undo_ids : @hashset.HashSet[CellId]
}

///|
fn BatchFrame::new() -> BatchFrame {
  { undo_entries: [], undo_ids: @hashset.new() }
}

///|
fn BatchFrame::has_undo_for(self : BatchFrame, cell_id : CellId) -> Bool {
  self.undo_ids.contains(cell_id)
}

///|
/// Executes a closure with batched signal updates.
///
/// All `Signal::set` calls inside the closure are deferred. At batch end,
/// a single revision bump occurs for all changes. This provides:
///
/// - **Atomicity**: Memos see either all changes or none
/// - **Efficiency**: One verification pass instead of many
/// - **Revert detection**: Setting a signal back to its original value is a no-op
///
/// Batches can be nested. Only the outermost batch commits changes.
///
/// # Parameters
///
/// - `f`: The closure to execute
///   If `f` raises an error, pending writes in this batch are rolled back and
///   the error is re-raised to the caller.
///
/// # Example
///
/// ```moonbit nocheck
/// rt.batch(() => {
///   x.set(10)
///   y.set(20)
///   z.set(30)
/// })
/// // Single revision bump for all three changes
/// ```
///
/// # Revert Detection
///
/// ```moonbit nocheck
/// rt.batch(() => {
///   x.set(5)   // Change from 0 to 5
///   x.set(0)   // Change back to 0
/// })
/// // No revision bump — net change is zero
/// ```
///
/// # Abort Behavior
///
/// MoonBit `abort()` is not catchable. If `f` aborts (rather than raises),
/// cleanup cannot run and runtime state may be left inconsistent.
pub fn Runtime::batch(self : Runtime, f : () -> Unit raise?) -> Unit raise? {
  self.core.batch.depth = self.core.batch.depth + 1
  self.core.batch.frames.push(BatchFrame::new())
  f() catch {
    e => {
      self.core.batch.depth = self.core.batch.depth - 1
      if self.core.batch.depth < 0 {
        abort("batch_depth underflow: batch() nesting is unbalanced")
      }
      self.rollback_current_batch_frame()
      raise e
    }
  }
  self.core.batch.depth = self.core.batch.depth - 1
  // Defense-in-depth: batch_depth is priv, but guard future modifications to mutation sites
  if self.core.batch.depth < 0 {
    abort("batch_depth underflow: batch() nesting is unbalanced")
  }
  self.complete_batch_frame_success()
  if self.core.batch.depth == 0 {
    self.commit_batch()
  }
}

///|
/// Executes a batch and returns raised errors as `Result` instead of re-raising.
///
/// This is a convenience wrapper around `Runtime::batch` for callers that prefer
/// explicit result handling. Like `Runtime::batch`, this captures raised errors
/// only; `abort()` is not recoverable here and still escapes `Runtime::batch_result`.
pub fn Runtime::batch_result(
  self : Runtime,
  f : () -> Unit raise?,
) -> Result[Unit, Error] {
  try? self.batch(f)
}

///|
/// Rolls back only the currently failing batch frame.
fn Runtime::rollback_current_batch_frame(self : Runtime) -> Unit {
  match self.core.batch.frames.pop() {
    Some(frame) => {
      let mut i = frame.undo_entries.length()
      while i > 0 {
        i = i - 1
        (frame.undo_entries[i].rollback)()
      }
      self.recompute_batch_max_durability()
    }
    None => abort("batch frame underflow: batch() nesting is unbalanced")
  }
}

///|
/// Completes the current frame after successful batch execution.
/// - Outermost success: discard undo log.
/// - Nested success: merge child frame entries into parent for outer rollback.
fn Runtime::complete_batch_frame_success(self : Runtime) -> Unit {
  match self.core.batch.frames.pop() {
    Some(frame) => {
      if self.core.batch.frames.length() == 0 {
        return
      }
      let parent = self.core.batch.frames[self.core.batch.frames.length() - 1]
      for entry in frame.undo_entries {
        if !parent.has_undo_for(entry.cell_id) {
          parent.undo_entries.push(entry)
          parent.undo_ids.add(entry.cell_id)
        }
      }
    }
    None => abort("batch frame underflow: batch() nesting is unbalanced")
  }
}

///|
/// Commit pending batch changes using two-phase values.
/// Phase 1: commit each signal's pending value, collecting which actually changed.
/// Phase 2: if any changed, single revision bump and metadata update.
/// Loops until no more callbacks queue additional signals, then fires the
/// global on_change callback exactly once if anything changed.
fn Runtime::commit_batch(self : Runtime) -> Unit {
  let mut any_changed = false
  while self.core.batch.pending.length() > 0 {
    // Phase 1: commit pending values and collect which actually changed
    let changed : Array[&Committable] = []
    for c in self.core.batch.pending {
      if c.do_commit() {
        changed.push(c)
      }
    }
    self.core.batch.pending.clear()
    // Phase 2: if any value actually changed, do a single revision bump
    if changed.length() > 0 {
      any_changed = true
      // Snapshot on_change callbacks BEFORE propagation — preserves the
      // invariant that push propagation cannot affect which handlers fire
      // in this batch wave (a PushReactive's compute closure could call
      // clear_on_change() or on_change() on a changed signal).
      let callbacks : Array[() -> Unit] = []
      for c in changed {
        let sig = self.get_pull_signal(c.cell_id())
        match sig.on_change {
          Some(f) => callbacks.push(f)
          None => ()
        }
      }
      let changed_ids : Array[CellId] = changed.map(fn(c) { c.cell_id() })
      self.propagate_changes(changed_ids, self.core.batch.max_durability)
      self.core.batch.max_durability = Low
      // Raise batch_depth while invoking callbacks so that any signal.set()
      // inside a callback takes the batch path instead of set_unconditional,
      // preventing re-entrant fire_on_change() calls.
      // If callbacks queue more signals, the while loop will process them.
      self.core.batch.depth = self.core.batch.depth + 1
      for cb in callbacks {
        cb()
      }
      self.core.batch.depth = self.core.batch.depth - 1
    } else {
      self.core.batch.max_durability = Low
    }
  }
  self.core.batch.max_durability = Low
  // Fire global on_change exactly once after all waves complete.
  if any_changed {
    self.fire_on_change()
  }
}

///|
/// Records a signal as having a pending change during a batch.
///
/// Called internally by `Signal::set` during batch operations.
///
/// # Parameters
///
/// - `committable`: A `&Committable` wrapping the `PullSignalData` with a
///   pending value. `commit_batch` later calls `do_commit()` on it to apply
///   the pending change and `cell_id()` / `durability()` to update metadata.
fn Runtime::record_batch_signal(
  self : Runtime,
  committable : &Committable,
) -> Unit {
  self.core.batch.pending.push(committable)
}

///|
/// Registers a rollback action for the current batch frame.
/// Only the first write per signal in a frame stores an undo entry.
fn Runtime::record_batch_rollback(
  self : Runtime,
  cell_id : CellId,
  rollback : () -> Unit,
) -> Unit {
  // Some internal batch-like flows (e.g. commit callbacks) temporarily
  // raise batch_depth without creating an undo frame. In this mode, writes
  // still use batch commit mechanics, but there is no user-visible frame to roll back.
  if self.core.batch.frames.length() == 0 {
    return
  }
  let frame = self.core.batch.frames[self.core.batch.frames.length() - 1]
  if frame.has_undo_for(cell_id) {
    return
  }
  frame.undo_entries.push({ cell_id, rollback })
  frame.undo_ids.add(cell_id)
}

///|
/// Removes one pending signal registration by id.
///
/// Called only from rollback closures during batch undo, which is rare.
/// Uses O(n) copy-and-rebuild because `batch_pending` must remain an ordered
/// queue — insertion order determines commit order in `commit_batch`.
fn Runtime::remove_batch_signal(self : Runtime, cell_id : CellId) -> Unit {
  let kept : Array[&Committable] = []
  let mut removed = false
  for c in self.core.batch.pending {
    if !removed && c.cell_id() == cell_id {
      removed = true
    } else {
      kept.push(c)
    }
  }
  self.core.batch.pending.clear()
  for c in kept {
    self.core.batch.pending.push(c)
  }
}

///|
/// Recompute max durability from currently pending signals.
fn Runtime::recompute_batch_max_durability(self : Runtime) -> Unit {
  let mut max_durability : Durability = Low
  for c in self.core.batch.pending {
    let d = c.durability()
    if d > max_durability {
      max_durability = d
    }
  }
  self.core.batch.max_durability = max_durability
}
