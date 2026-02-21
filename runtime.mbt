///|
/// Global counter for assigning unique IDs to Runtime instances.
///
/// Each Runtime gets a unique ID to prevent CellIds from different
/// runtimes being incorrectly queried against each other.
///
/// Note: This is a reference cell to enable mutable global state.
let next_runtime_id : Ref[Int] = { val: 0 }

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
/// let rt = Runtime::new()
///
/// let x = Signal::new(rt, 10)
///
/// let doubled = Memo::new(rt, fn() { x.get() * 2 })
/// ```
pub(all) struct Runtime {
  priv runtime_id : Int
  priv mut current_revision : Revision
  priv cells : Array[CellMeta?]
  priv mut next_cell_id : Int
  priv tracking_stack : Array[ActiveQuery]
  priv durability_last_changed : FixedArray[Revision]
  priv mut batch_depth : Int
  priv batch_pending_signals : Array[CellId]
  priv mut batch_max_durability : Durability
  priv mut on_change : (() -> Unit)?
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
/// let rt = Runtime::new()
///
/// let rt = Runtime::new(on_change=fn() { rerender() })
///
/// let x = Signal::new(rt, 10)
///
/// let doubled = Memo::new(rt, fn() { x.get() * 2 })
/// ```
pub fn Runtime::new(on_change? : () -> Unit) -> Runtime {
  let id = next_runtime_id.val
  next_runtime_id.val = next_runtime_id.val + 1
  {
    runtime_id: id,
    current_revision: Revision::initial(),
    cells: [],
    next_cell_id: 0,
    tracking_stack: [],
    durability_last_changed: FixedArray::make(
      DURABILITY_COUNT,
      Revision::initial(),
    ),
    batch_depth: 0,
    batch_pending_signals: [],
    batch_max_durability: Low,
    on_change,
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
}

///|
/// Registers cell metadata with the runtime.
///
/// This is called internally when creating signals and memos. Users typically
/// don't need to call this directly.
///
/// # Parameters
///
/// - `meta`: The cell metadata to register
fn Runtime::register_cell(self : Runtime, meta : CellMeta) -> Unit {
  let id = meta.id.id
  // Grow array if needed
  while self.cells.length() <= id {
    self.cells.push(None)
  }
  self.cells[id] = Some(meta)
}

///|
/// Allocates a fresh cell identifier.
///
/// This is called internally when creating signals and memos. Cell IDs are
/// monotonically increasing integers used for O(1) cell lookup.
///
/// # Returns
///
/// A new unique cell identifier
fn Runtime::alloc_cell_id(self : Runtime) -> CellId {
  let id = self.next_cell_id
  self.next_cell_id = id + 1
  { runtime_id: self.runtime_id, id }
}

///|
/// Retrieves cell metadata by ID.
///
/// This is called internally during verification and recomputation.
///
/// # Parameters
///
/// - `id`: The cell identifier
///
/// # Returns
///
/// The cell's metadata
///
/// # Panics
///
/// Aborts if no cell with the given ID exists
fn Runtime::get_cell(self : Runtime, id : CellId) -> CellMeta {
  if id.runtime_id != self.runtime_id {
    abort("Cell belongs to a different Runtime")
  }
  if id.id < 0 {
    abort("Invalid cell id: " + id.id.to_string())
  }
  if id.id < self.cells.length() {
    match self.cells[id.id] {
      Some(meta) => meta
      None => abort("Cell not found: " + id.id.to_string())
    }
  } else {
    abort("Cell not found: " + id.id.to_string())
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
/// let rt = Runtime::new()
/// let sig = Signal::new(rt, 42)
/// let memo = Memo::new(rt, fn() { sig.get() * 2 })
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
  // Validate runtime ownership - reject CellIds from other runtimes
  if id.runtime_id != self.runtime_id {
    return None
  }

  // Check bounds (both negative and out of range)
  if id.id < 0 || id.id >= self.cells.length() {
    return None
  }

  // Extract metadata
  match self.cells[id.id] {
    Some(meta) =>
      Some(CellInfo::{
        label: meta.label,
        id,
        changed_at: meta.changed_at,
        verified_at: meta.verified_at,
        durability: meta.durability,
        dependencies: meta.dependencies.copy(),
      })
    None => None
  }
}

///|
/// Advance the global revision counter and record which durability level changed.
/// Updates current_revision and all durability_last_changed entries up to dur_idx.
/// Callers must ensure this is only called outside of a batch (batch_depth == 0).
fn Runtime::advance_revision(self : Runtime, durability : Durability) -> Unit {
  self.current_revision = self.current_revision.next()
  let dur_idx = durability.index()
  for i = 0; i <= dur_idx; i = i + 1 {
    self.durability_last_changed[i] = self.current_revision
  }
}

///|
/// Mark an input cell as changed at the current revision.
/// Sets both changed_at and verified_at to current_revision.
/// Must be called after advance_revision so current_revision is already updated.
fn Runtime::mark_input_changed(self : Runtime, id : CellId) -> CellMeta {
  let meta = self.get_cell(id)
  meta.changed_at = self.current_revision
  meta.verified_at = self.current_revision
  meta
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
///
/// # Example
///
/// ```moonbit nocheck
/// rt.batch(fn() {
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
/// rt.batch(fn() {
///   x.set(5)   // Change from 0 to 5
///   x.set(0)   // Change back to 0
/// })
/// // No revision bump — net change is zero
/// ```
pub fn Runtime::batch(self : Runtime, f : () -> Unit) -> Unit {
  self.batch_depth = self.batch_depth + 1
  f()
  self.batch_depth = self.batch_depth - 1
  // Defense-in-depth: batch_depth is priv, but guard future modifications to mutation sites
  if self.batch_depth < 0 {
    abort("batch_depth underflow: batch() nesting is unbalanced")
  }
  if self.batch_depth == 0 {
    self.commit_batch()
  }
}

///|
/// Commit pending batch changes using two-phase values.
/// Phase 1: commit each signal's pending value, collecting which actually changed.
/// Phase 2: if any changed, single revision bump and metadata update.
fn Runtime::commit_batch(self : Runtime) -> Unit {
  if self.batch_pending_signals.length() == 0 {
    // Nothing changed during the batch, reset state
    self.batch_max_durability = Low
    return
  }
  // Phase 1: commit pending values and collect which actually changed
  let changed_ids : Array[CellId] = []
  for id in self.batch_pending_signals {
    let meta = self.get_cell(id)
    match meta.commit_pending {
      Some(commit_fn) => {
        if commit_fn() {
          changed_ids.push(id)
        }
        meta.commit_pending = None
      }
      None =>
        abort(
          "Batched signal missing commit_pending — internal invariant violated",
        )
    }
  }
  // Reset pending list by clearing directly
  self.batch_pending_signals.clear()
  // Phase 2: if any value actually changed, do a single revision bump
  if changed_ids.length() > 0 {
    self.advance_revision(self.batch_max_durability)
    // Sweep changed signals and collect callbacks in a single pass.
    let callbacks : Array[() -> Unit] = []
    for id in changed_ids {
      let meta = self.mark_input_changed(id)
      match meta.on_change {
        Some(f) => callbacks.push(f)
        None => ()
      }
    }
    self.batch_max_durability = Low
    // Raise batch_depth while invoking callbacks so that any signal.set()
    // inside a callback takes the batch path instead of set_unconditional,
    // preventing re-entrant fire_on_change() calls.
    self.batch_depth = self.batch_depth + 1
    for cb in callbacks {
      cb()
    }
    self.batch_depth = self.batch_depth - 1
    // Commit any signals set during callbacks, then fire global once.
    if self.batch_pending_signals.length() > 0 {
      self.commit_batch()
    }
    self.fire_on_change()
    return
  }
  self.batch_max_durability = Low
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
  self.tracking_stack.push(ActiveQuery::new(cell_id))
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
    Some(query) => (query.dependencies, query.seen)
    None => abort("Tracking stack underflow")
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
