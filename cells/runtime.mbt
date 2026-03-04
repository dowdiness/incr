///|
/// Global counter for assigning unique IDs to Runtime instances.
///
/// Each Runtime gets a unique ID to prevent CellIds from different
/// runtimes being incorrectly queried against each other.
///
/// Note: This is a reference cell to enable mutable global state.
let next_runtime_id : Ref[Int] = { val: 0 }

///|
/// Tracks the runtime_id currently executing a memo computation.
/// -1 means no computation is active (sentinel; runtime IDs start at 0).
/// Set by push_tracking, cleared by pop_tracking when the stack empties.
/// Used by Signal::get and Memo::get_result to detect cross-runtime reads.
///
/// **Single-threaded assumption**: MoonBit currently targets WebAssembly
/// (inherently single-threaded) and a single-threaded native runtime, so a
/// plain `Ref[Int]` is safe here. If parallel execution is ever introduced
/// (e.g. native threads or shared-memory WASM), this sentinel must be
/// replaced with a thread-local or an atomic, and push/pop_tracking must
/// use appropriate synchronisation primitives.
let current_computing_runtime_id : Ref[Int] = { val: -1 }

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
/// Central coordinator for the incremental computation framework.
///
/// The Runtime manages all bookkeeping for dependency tracking, revision
/// counting, and batch operations. Every Signal and Memo is associated
/// with exactly one Runtime.
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime()
///
/// let x = Signal(rt, 10)
///
/// let doubled = Memo(rt, () => x.get() * 2)
/// ```
pub(all) struct Runtime {
  priv runtime_id : Int
  priv mut current_revision : Revision
  priv mut next_cell_id : Int
  priv tracking_stack : Array[ActiveQuery]
  priv durability_last_changed : FixedArray[Revision]
  priv mut batch_depth : Int
  priv batch_pending_signals : Array[CellId]
  priv batch_frames : Array[BatchFrame]
  priv mut batch_max_durability : Durability
  priv mut on_change : (() -> Unit)?
  // SoA storage arrays
  priv pull_signals : Array[PullSignalData]
  priv pull_memos : Array[PullMemoData]
  priv cell_index : Array[CellRef]

  fn new(on_change? : () -> Unit) -> Runtime
}

///|
/// Creates a new runtime with an empty dependency graph.
///
/// This is the entry point for using the incremental computation framework.
/// Create one runtime, then create signals and memos associated with it.
///
/// # Parameters
///
/// - `on_change`: Optional callback invoked whenever any signal changes
///   (or at the end of a batch if values actually changed). Equivalent
///   to calling `Runtime::set_on_change` immediately after construction.
///
/// # Returns
///
/// A new runtime ready to manage signals and memos
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime()
///
/// let rt = Runtime(on_change=() => rerender())
///
/// let x = Signal(rt, 10)
///
/// let doubled = Memo(rt, () => x.get() * 2)
/// ```
pub fn Runtime::new(on_change? : () -> Unit) -> Runtime {
  let id = next_runtime_id.val
  next_runtime_id.val = next_runtime_id.val + 1
  {
    runtime_id: id,
    current_revision: Revision::initial(),
    next_cell_id: 0,
    tracking_stack: [],
    durability_last_changed: FixedArray::make(
      @incr_types.DURABILITY_COUNT,
      Revision::initial(),
    ),
    batch_depth: 0,
    batch_pending_signals: [],
    batch_frames: [],
    batch_max_durability: Low,
    on_change,
    pull_signals: [],
    pull_memos: [],
    cell_index: [],
  }
}

///|
/// Structured metadata about a cell in the dependency graph.
///
/// This structure provides a uniform view of both Signal and Memo cells.
/// For signals, the `dependencies` array will be empty.
///
/// # Fields
///
/// - `label`: Optional human-readable name for debugging and introspection
/// - `id`: The unique identifier for this cell
/// - `changed_at`: When this cell's value last actually changed
/// - `verified_at`: When this cell was last confirmed up-to-date
/// - `durability`: How often this cell is expected to change
/// - `dependencies`: Cell IDs this cell depends on (empty for signals)
pub(all) struct CellInfo {
  label : String?
  id : CellId
  changed_at : Revision
  verified_at : Revision
  durability : Durability
  dependencies : Array[CellId]
  subscribers : Array[CellId]
}

///|
/// Allocates a raw cell identifier (internal helper).
///
/// Increments `next_cell_id` and returns the new CellId without touching
/// `cell_index`. Used by `alloc_cell_id(CellRef)`.
fn Runtime::alloc_next_id(self : Runtime) -> CellId {
  let id = self.next_cell_id
  self.next_cell_id = id + 1
  { runtime_id: self.runtime_id, id }
}

///|
/// Allocates a fresh cell identifier and registers it in the SoA cell_index.
///
/// The `cell_ref` argument records which typed SoA array this cell lives in
/// (e.g. `PullSignal(idx)` or `PullMemo(idx)`).  The returned `CellId.id`
/// is the index into `cell_index` for fast dispatch.
///
/// # Returns
///
/// A new unique cell identifier
fn Runtime::alloc_cell_id(self : Runtime, cell_ref : CellRef) -> CellId {
  let cell_id = self.alloc_next_id()
  self.cell_index.push(cell_ref)
  cell_id
}

///|
/// Allocates a new Pull Signal cell in the SoA layout.
///
/// Pushes a `PullSignalData` entry into `pull_signals` and registers
/// `PullSignal(idx)` in `cell_index` via `alloc_cell_id`.
///
/// The `on_change`, `commit_pending`, and `rollback_pending` closures start
/// as `None` and are set later by `Signal::on_change` and `Signal::set_batch`.
///
/// # Returns
///
/// The new cell's unique identifier
fn Runtime::new_signal_id(
  self : Runtime,
  durability : Durability,
  label : String?,
) -> CellId {
  let idx = self.pull_signals.length()
  let cell_id = self.alloc_cell_id(PullSignal(idx))
  self.pull_signals.push({
    cell_id,
    label,
    changed_at: Revision::initial(),
    durability,
    subscribers: @hashset.new(),
    on_change: None,
    commit_pending: None,
    rollback_pending: None,
  })
  cell_id
}

///|
/// Collects all pull memos currently marked in_progress.
///
/// Called when a cycle is detected during `pull_verify`. The in_progress
/// flags on `PullMemoData` entries identify the exact cycle participants.
///
/// # Returns
///
/// Array of CellIds for all pull memos with `in_progress = true`
fn Runtime::collect_in_progress_path(self : Runtime) -> Array[CellId] {
  let path : Array[CellId] = []
  for memo in self.pull_memos {
    if memo.in_progress {
      path.push(memo.cell_id)
    }
  }
  path
}

///|
/// Returns the `changed_at` revision for any cell, dispatching via cell_index.
///
/// Covers PullSignal and PullMemo; aborts on unknown or out-of-bounds IDs.
fn Runtime::get_changed_at(self : Runtime, id : CellId) -> Revision {
  if id.runtime_id != self.runtime_id {
    abort("Cell belongs to a different Runtime")
  }
  if id.id < 0 || id.id >= self.cell_index.length() {
    abort("get_changed_at: cell_id out of bounds: " + id.id.to_string())
  }
  match self.cell_index[id.id] {
    PullSignal(idx) => self.pull_signals[idx].changed_at
    PullMemo(idx) => self.pull_memos[idx].changed_at
  }
}

///|
/// Returns the `durability` for any cell, dispatching via cell_index.
fn Runtime::get_durability(self : Runtime, id : CellId) -> Durability {
  match self.cell_index[id.id] {
    PullSignal(idx) => self.pull_signals[idx].durability
    PullMemo(idx) => self.pull_memos[idx].durability
  }
}

///|
/// Returns the CellId stored in the given SoA entry (reverse lookup).
///
/// Each SoA data struct caches its own CellId so we can round-trip from a
/// CellRef index back to the unified CellId without an extra map.
fn Runtime::cell_id_for(self : Runtime, cell_ref : CellRef) -> CellId {
  match cell_ref {
    PullSignal(idx) => self.pull_signals[idx].cell_id
    PullMemo(idx) => self.pull_memos[idx].cell_id
  }
}

///|
/// Returns the PullSignalData for a signal cell.
///
/// # Panics
///
/// Aborts if the cell belongs to a different runtime or is not a signal.
fn Runtime::get_pull_signal(self : Runtime, id : CellId) -> PullSignalData {
  if id.runtime_id != self.runtime_id {
    abort("Cell belongs to a different Runtime")
  }
  if id.id < 0 || id.id >= self.cell_index.length() {
    abort("get_pull_signal: cell_id out of bounds: " + id.id.to_string())
  }
  match self.cell_index[id.id] {
    PullSignal(idx) => self.pull_signals[idx]
    PullMemo(_) =>
      abort("Expected signal cell but found memo: " + id.id.to_string())
  }
}

///|
/// Returns the PullMemoData for a memo cell.
///
/// # Panics
///
/// Aborts if the cell belongs to a different runtime or is not a memo.
fn Runtime::get_pull_memo(self : Runtime, id : CellId) -> PullMemoData {
  if id.runtime_id != self.runtime_id {
    abort("Cell belongs to a different Runtime")
  }
  if id.id < 0 || id.id >= self.cell_index.length() {
    abort("get_pull_memo: cell_id out of bounds: " + id.id.to_string())
  }
  match self.cell_index[id.id] {
    PullMemo(idx) => self.pull_memos[idx]
    PullSignal(_) =>
      abort("Expected memo cell but found signal: " + id.id.to_string())
  }
}

///|
/// Returns an iterator over the subscriber IDs for the given cell.
///
/// Used by Phase 3 push propagation to enumerate cells that must be
/// notified when a cell's value changes. Phase 3 extends this with
/// `PushReactive`, `PushEffect`, and `Disposed` arms.
fn Runtime::get_subscribers(self : Runtime, cell_id : CellId) -> Iter[CellId] {
  match self.cell_index[cell_id.id] {
    PullSignal(idx) => self.pull_signals[idx].subscribers.iter()
    PullMemo(idx) => self.pull_memos[idx].subscribers.iter()
  }
}

///|
/// Returns the mutable subscriber set for the given cell.
///
/// Returns the live `HashSet[CellId]` object; mutations through it are
/// immediately reflected in the runtime. Used by `finish_tracking` and
/// Phase 3 disposal to add/remove reverse edges efficiently.
fn Runtime::get_subscribers_mut(
  self : Runtime,
  cell_id : CellId,
) -> @hashset.HashSet[CellId] {
  match self.cell_index[cell_id.id] {
    PullSignal(idx) => self.pull_signals[idx].subscribers
    PullMemo(idx) => self.pull_memos[idx].subscribers
  }
}

///|
/// Removes `subscriber` from the subscriber set of `dep`.
fn Runtime::remove_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  match self.cell_index[dep.id] {
    PullSignal(idx) => self.pull_signals[idx].subscribers.remove(subscriber)
    PullMemo(idx) => self.pull_memos[idx].subscribers.remove(subscriber)
  }
}

///|
/// Adds `subscriber` to the subscriber set of `dep`.
fn Runtime::add_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  match self.cell_index[dep.id] {
    PullSignal(idx) => self.pull_signals[idx].subscribers.add(subscriber)
    PullMemo(idx) => self.pull_memos[idx].subscribers.add(subscriber)
  }
}

///|
/// Registers a callback that fires whenever a revision bump occurs.
/// During a batch, it fires once at batch end (only if values actually changed).
///
/// # Parameters
///
/// - `f`: The callback to invoke on change
pub fn Runtime::set_on_change(self : Runtime, f : () -> Unit) -> Unit {
  self.on_change = Some(f)
}

///|
/// Removes the on_change callback.
pub fn Runtime::clear_on_change(self : Runtime) -> Unit {
  self.on_change = None
}

///|
/// Fires the on_change callback if one is registered.
fn Runtime::fire_on_change(self : Runtime) -> Unit {
  match self.on_change {
    Some(f) => f()
    None => ()
  }
}

///|
/// Returns structured metadata for any cell (signal or memo).
///
/// This method provides uniform introspection access to cell metadata regardless of
/// whether the cell is a Signal or Memo. It returns CellInfo containing the cell's
/// ID, type, revision information, durability, and dependency list.
///
/// # Parameters
///
/// - `id`: The CellId to query (obtained via Signal::id() or Memo::id())
///
/// # Returns
///
/// - `Some(CellInfo)`: If the cell ID is valid and points to an active cell
/// - `None`: If the cell ID is out of bounds or points to an unused slot
///
/// # Usage
///
/// ```moonbit nocheck
/// let rt = Runtime()
/// let sig = Signal(rt, 42)
/// let memo = Memo(rt, () => sig.get() * 2)
/// let _ = memo.get()  // Force computation
///
/// // Query signal metadata
/// match rt.cell_info(sig.id()) {
///   Some(info) => {
///     println("Signal changed at: \{info.changed_at}")
///     println("Dependencies: \{info.dependencies.length()}")
///   }
///   None => println("Cell not found")
/// }
///
/// // Query memo metadata
/// match rt.cell_info(memo.id()) {
///   Some(info) => {
///     println("Memo durability: \{info.durability}")
///     println("Depends on \{info.dependencies.length()} cells")
///   }
///   None => println("Cell not found")
/// }
/// ```
///
/// # Notes
///
/// - The dependency array is a copy; modifying it does not affect the runtime
/// - For signals, the dependencies array is always empty
/// - For memos, dependencies are populated after the first computation
/// - The method performs bounds checking and returns None for invalid IDs
pub fn Runtime::cell_info(self : Runtime, id : CellId) -> CellInfo? {
  if id.runtime_id != self.runtime_id {
    return None
  }
  if id.id < 0 || id.id >= self.cell_index.length() {
    return None
  }
  match self.cell_index[id.id] {
    PullSignal(idx) => {
      let sig = self.pull_signals[idx]
      Some(CellInfo::{
        label: sig.label,
        id,
        changed_at: sig.changed_at,
        // Signals are always up-to-date after a set; verified_at == changed_at
        verified_at: sig.changed_at,
        durability: sig.durability,
        dependencies: [],
        subscribers: snapshot_subscribers(sig.subscribers),
      })
    }
    PullMemo(idx) => {
      let memo = self.pull_memos[idx]
      Some(CellInfo::{
        label: memo.label,
        id,
        changed_at: memo.changed_at,
        verified_at: memo.verified_at,
        durability: memo.durability,
        dependencies: memo.dependencies.copy(),
        subscribers: snapshot_subscribers(memo.subscribers),
      })
    }
  }
}

///|
/// Snapshot a HashSet[CellId] into an Array[CellId].
fn snapshot_subscribers(
  subscribers : @hashset.HashSet[CellId],
) -> Array[CellId] {
  let result : Array[CellId] = []
  for sub in subscribers {
    result.push(sub)
  }
  result
}

///|
/// Returns the cell IDs that depend on the given cell (reverse edges).
///
/// This enables introspection of the dependency graph in both directions.
/// The returned array is a snapshot; modifying it does not affect the runtime.
///
/// Returns an empty array if the cell ID is invalid, out of bounds, or
/// belongs to a different runtime — matching `cell_info` semantics.
///
/// # Parameters
///
/// - `id`: The cell to query
///
/// # Returns
///
/// Array of CellIds that have `id` in their dependency list, or empty
/// array if the cell ID is not valid for this runtime
pub fn Runtime::dependents(self : Runtime, id : CellId) -> Array[CellId] {
  if id.runtime_id != self.runtime_id {
    return []
  }
  if id.id < 0 || id.id >= self.cell_index.length() {
    return []
  }
  match self.cell_index[id.id] {
    PullSignal(idx) => snapshot_subscribers(self.pull_signals[idx].subscribers)
    PullMemo(idx) => snapshot_subscribers(self.pull_memos[idx].subscribers)
  }
}

///|
/// Advance the global revision counter and record which durability level changed.
/// Updates current_revision and all durability_last_changed entries up to dur_idx.
/// Callers must ensure this is only called outside of a batch (batch_depth == 0).
fn Runtime::advance_revision(self : Runtime, durability : Durability) -> Unit {
  self.current_revision = Revision::next(self.current_revision)
  let dur_idx = durability.index()
  for i = 0; i <= dur_idx; i = i + 1 {
    self.durability_last_changed[i] = self.current_revision
  }
}

///|
/// Mark an input cell as changed at the current revision.
/// Sets changed_at to current_revision on the PullSignalData entry.
/// Must be called after advance_revision so current_revision is already updated.
fn Runtime::mark_input_changed(self : Runtime, id : CellId) -> PullSignalData {
  let sig = self.get_pull_signal(id)
  sig.changed_at = self.current_revision
  sig
}

///|
/// Bumps the global revision counter and records which durability level changed.
///
/// This is called internally when a signal's value changes. The durability
/// parameter enables the durability shortcut: memos with higher durability
/// than the changed signal can skip verification.
///
/// During a batch, the actual bump is deferred until the batch ends.
///
/// # Parameters
///
/// - `durability`: The durability level of the signal that changed
fn Runtime::bump_revision(self : Runtime, durability : Durability) -> Unit {
  if self.batch_depth > 0 {
    // Track the maximum durability seen during this batch
    if durability > self.batch_max_durability {
      self.batch_max_durability = durability
    }
    return
  }
  self.advance_revision(durability)
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
  self.batch_depth = self.batch_depth + 1
  self.batch_frames.push(BatchFrame::new())
  f() catch {
    e => {
      self.batch_depth = self.batch_depth - 1
      if self.batch_depth < 0 {
        abort("batch_depth underflow: batch() nesting is unbalanced")
      }
      self.rollback_current_batch_frame()
      raise e
    }
  }
  self.batch_depth = self.batch_depth - 1
  // Defense-in-depth: batch_depth is priv, but guard future modifications to mutation sites
  if self.batch_depth < 0 {
    abort("batch_depth underflow: batch() nesting is unbalanced")
  }
  self.complete_batch_frame_success()
  if self.batch_depth == 0 {
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
  match self.batch_frames.pop() {
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
  match self.batch_frames.pop() {
    Some(frame) => {
      if self.batch_frames.length() == 0 {
        return
      }
      let parent = self.batch_frames[self.batch_frames.length() - 1]
      for entry in frame.undo_entries {
        if not(parent.has_undo_for(entry.cell_id)) {
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
  while self.batch_pending_signals.length() > 0 {
    // Phase 1: commit pending values and collect which actually changed
    let changed_ids : Array[CellId] = []
    for id in self.batch_pending_signals {
      let sig = self.get_pull_signal(id)
      match sig.rollback_pending {
        Some(_) => ()
        None =>
          abort(
            "Batched signal missing rollback_pending — internal invariant violated",
          )
      }
      match sig.commit_pending {
        Some(commit_fn) => {
          if commit_fn() {
            changed_ids.push(id)
          }
          sig.commit_pending = None
          sig.rollback_pending = None
        }
        None =>
          abort(
            "Batched signal missing commit_pending — internal invariant violated",
          )
      }
    }
    self.batch_pending_signals.clear()
    // Phase 2: if any value actually changed, do a single revision bump
    if changed_ids.length() > 0 {
      any_changed = true
      self.advance_revision(self.batch_max_durability)
      // Sweep changed signals and collect callbacks in a single pass.
      let callbacks : Array[() -> Unit] = []
      for id in changed_ids {
        let sig = self.mark_input_changed(id)
        match sig.on_change {
          Some(f) => callbacks.push(f)
          None => ()
        }
      }
      self.batch_max_durability = Low
      // Raise batch_depth while invoking callbacks so that any signal.set()
      // inside a callback takes the batch path instead of set_unconditional,
      // preventing re-entrant fire_on_change() calls.
      // If callbacks queue more signals, the while loop will process them.
      self.batch_depth = self.batch_depth + 1
      for cb in callbacks {
        cb()
      }
      self.batch_depth = self.batch_depth - 1
    } else {
      self.batch_max_durability = Low
    }
  }
  self.batch_max_durability = Low
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
/// - `cell_id`: The ID of the signal with a pending change
fn Runtime::record_batch_signal(self : Runtime, cell_id : CellId) -> Unit {
  self.batch_pending_signals.push(cell_id)
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
  if self.batch_frames.length() == 0 {
    return
  }
  let frame = self.batch_frames[self.batch_frames.length() - 1]
  if frame.has_undo_for(cell_id) {
    return
  }
  frame.undo_entries.push({ cell_id, rollback })
  frame.undo_ids.add(cell_id)
}

///|
/// Removes one pending signal registration by id.
fn Runtime::remove_batch_signal(self : Runtime, cell_id : CellId) -> Unit {
  let kept : Array[CellId] = []
  let mut removed = false
  for id in self.batch_pending_signals {
    if not(removed) && id == cell_id {
      removed = true
    } else {
      kept.push(id)
    }
  }
  self.batch_pending_signals.clear()
  for id in kept {
    self.batch_pending_signals.push(id)
  }
}

///|
/// Recompute max durability from currently pending signals.
fn Runtime::recompute_batch_max_durability(self : Runtime) -> Unit {
  let mut max_durability : Durability = Low
  for id in self.batch_pending_signals {
    let durability = self.get_pull_signal(id).durability
    if durability > max_durability {
      max_durability = durability
    }
  }
  self.batch_max_durability = max_durability
}

///|
/// Records a dependency from the currently computing memo to the given cell.
///
/// Called internally by `Signal::get` and `Memo::get` when inside a memo's
/// compute function. If no memo is currently computing (tracking stack is
/// empty), this is a no-op.
///
/// # Parameters
///
/// - `dep`: The cell ID that the current memo depends on
fn Runtime::record_dependency(self : Runtime, dep : CellId) -> Unit {
  let len = self.tracking_stack.length()
  if len > 0 {
    self.tracking_stack[len - 1].record(dep)
  }
}

///|
/// Pushes a new dependency tracking frame for a memo computation.
///
/// Called internally at the start of a memo's recomputation. All subsequent
/// `get()` calls will be recorded as dependencies until `pop_tracking` is called.
///
/// # Parameters
///
/// - `cell_id`: The ID of the memo being computed
fn Runtime::push_tracking(self : Runtime, cell_id : CellId) -> Unit {
  current_computing_runtime_id.val = self.runtime_id
  self.tracking_stack.push(ActiveQuery(cell_id))
}

///|
/// Pops the tracking frame and returns the collected dependencies.
///
/// Called internally at the end of a memo's recomputation. The returned
/// dependency list is stored on the memo's cell metadata.
///
/// # Returns
///
/// The list of cell IDs that were read during the computation
///
/// # Panics
///
/// Aborts if the tracking stack is empty (unbalanced push/pop)
fn Runtime::pop_tracking(
  self : Runtime,
) -> (Array[CellId], @hashset.HashSet[CellId]) {
  match self.tracking_stack.pop() {
    Some(query) => {
      if self.tracking_stack.length() == 0 {
        current_computing_runtime_id.val = -1
      }
      (query.dependencies, query.seen)
    }
    None => abort("Tracking stack underflow")
  }
}

///|
/// Pushes a fresh tracking frame for the given cell (Phase 2 API).
///
/// Equivalent to `push_tracking`. Provided as a stable helper name for
/// Phase 3+ cell types that manage their own tracking lifecycle outside of
/// `force_recompute`.
fn Runtime::begin_tracking(self : Runtime, cell_id : CellId) -> Unit {
  self.push_tracking(cell_id)
}

///|
/// Pops the tracking frame and returns only the collected dependency list.
///
/// Simplified form of `pop_tracking` used by Phase 3+ cell types that do not
/// need the pre-built `seen` set (they call `finish_tracking` separately).
///
/// # Panics
///
/// Aborts if the tracking stack is empty.
fn Runtime::end_tracking(self : Runtime) -> Array[CellId] {
  let (deps, _seen) = self.pop_tracking()
  deps
}

///|
/// Updates subscriber links after a cell recomputes with a new dependency set.
///
/// Diffs `old_deps` against `new_deps` and:
/// - removes `cell_id` from the subscriber set of every dropped dependency
/// - adds `cell_id` to the subscriber set of every newly added dependency
///
/// This is the canonical subscriber-maintenance helper for Phase 3+ cell types.
/// `Memo::force_recompute` performs an equivalent diff inline (with the
/// optimisation of reusing the `seen` set from `pop_tracking`); Phase 3 cell
/// types use this helper instead.
fn Runtime::finish_tracking(
  self : Runtime,
  cell_id : CellId,
  old_deps : Array[CellId],
  new_deps : Array[CellId],
) -> Unit {
  if old_deps.length() == 0 && new_deps.length() == 0 {
    return
  }
  let new_seen : @hashset.HashSet[CellId] = @hashset.new()
  for dep in new_deps {
    new_seen.add(dep)
  }
  let old_seen : @hashset.HashSet[CellId] = @hashset.new()
  for dep in old_deps {
    old_seen.add(dep)
    if not(new_seen.contains(dep)) {
      self.remove_subscriber(dep, cell_id)
    }
  }
  for dep in new_deps {
    if not(old_seen.contains(dep)) {
      self.add_subscriber(dep, cell_id)
    }
  }
}

///|
/// Collect cell IDs from the current tracking stack.
///
/// Returns the cell IDs of all active computation frames in order,
/// for use in cycle error diagnostics. Does not modify the stack.
fn Runtime::collect_tracking_path(self : Runtime) -> Array[CellId] {
  let path : Array[CellId] = []
  for frame in self.tracking_stack {
    path.push(frame.cell_id)
  }
  path
}
