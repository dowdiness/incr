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
/// Core runtime state: identity, revision tracking, batch management,
/// and unified dispatch tables.
///
/// Groups fields that are accessed by all propagation modes. The `cell_index`
/// and `cell_ops` dispatch tables are the bridge between the two-layer
/// architecture (CellRef for structural observation, CellOps for behavioral
/// dispatch). `tracking_stack` lives here rather than in PullState because
/// push-mode cell types (Reactive, Effect) also use begin/end_tracking.
///
/// # Pointer chase tradeoff
///
/// All sub-struct field accesses (e.g. `self.core.current_revision`) require
/// one extra pointer dereference compared to the old flat layout. MoonBit
/// structs are heap-allocated, so RuntimeCore is a separate heap object.
/// In hot loops (verify dep-walk, push propagation), the sub-struct pointers
/// are cache-hot since they are dereferenced on every iteration. Profile
/// with `moon bench --release` if regressions are suspected.
priv struct RuntimeCore {
  runtime_id : Int
  mut current_revision : Revision
  mut next_cell_id : Int
  tracking_stack : Array[ActiveQuery]
  durability_last_changed : FixedArray[Revision]
  mut batch_depth : Int
  batch_pending : Array[&Committable]
  batch_frames : Array[BatchFrame]
  mut batch_max_durability : Durability
  mut on_change : (() -> Unit)?
  cell_index : Array[CellRef]
  cell_ops : Array[&CellOps]
}

///|
/// Pull-mode SoA storage (lazy verification).
priv struct PullState {
  signals : Array[PullSignalData]
  memos : Array[PullMemoData]
}

///|
/// Push-mode SoA storage (eager propagation).
///
/// `hybrid_memos` lives here despite HybridMemo participating in pull
/// verification (`pull_verify_hybrid`). The placement reflects that push
/// propagation is responsible for managing HybridMemo's `dirty` flag and
/// `node_count`, which are the hot-path fields. Pull verification accesses
/// `self.push.hybrid_memos` when verifying a HybridMemo dep — this is a
/// deliberate cross-boundary access, not a leak.
priv struct PushState {
  reactives : Array[PushReactiveData]
  effects : Array[PushEffectData]
  free_reactives : Array[Int]
  free_effects : Array[Int]
  /// Count of live push cells (reactives + effects + hybrid memos).
  /// Used as an O(1) gate before push propagation.
  mut node_count : Int
  hybrid_memos : Array[HybridMemoData]
  hybrid_dirty : Array[CellId]
}

///|
/// Datalog SoA storage (fixpoint evaluation).
priv struct DatalogState {
  mut in_fixpoint : Bool
  relations : Array[RelationData]
  rules : Array[RuleData]
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
  priv core : RuntimeCore
  priv pull : PullState
  priv push : PushState
  priv datalog : DatalogState

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
    core: {
      runtime_id: id,
      current_revision: Revision::initial(),
      next_cell_id: 0,
      tracking_stack: [],
      durability_last_changed: FixedArray::make(
        @incr_types.DURABILITY_COUNT,
        Revision::initial(),
      ),
      batch_depth: 0,
      batch_pending: [],
      batch_frames: [],
      batch_max_durability: Low,
      on_change,
      cell_index: [],
      cell_ops: [],
    },
    pull: { signals: [], memos: [] },
    push: {
      reactives: [],
      effects: [],
      free_reactives: [],
      free_effects: [],
      node_count: 0,
      hybrid_memos: [],
      hybrid_dirty: [],
    },
    datalog: { in_fixpoint: false, relations: [], rules: [] },
  }
}

///|
/// Allocates a raw cell identifier (internal helper).
///
/// Increments `next_cell_id` and returns the new CellId without touching
/// `cell_index`. Used by `alloc_cell_id(CellRef)`.
fn Runtime::alloc_next_id(self : Runtime) -> CellId {
  let id = self.core.next_cell_id
  self.core.next_cell_id = id + 1
  { runtime_id: self.core.runtime_id, id }
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
  self.core.cell_index.push(cell_ref)
  cell_id
}

///|
/// Allocates a new Pull Signal cell in the SoA layout.
///
/// Pushes a `PullSignalData` entry into `pull_signals` and registers
/// `PullSignal(idx)` in `cell_index` via `alloc_cell_id`.
///
/// The `on_change` and `commit_pending` closures start as `None` and are set
/// later by `Signal::on_change` and `Signal::set_batch`.
///
/// # Returns
///
/// The new cell's unique identifier
fn Runtime::new_signal_id(
  self : Runtime,
  durability : Durability,
  label : String?,
) -> CellId {
  let idx = self.pull.signals.length()
  let cell_id = self.alloc_cell_id(PullSignal(idx))
  self.pull.signals.push({
    cell_id,
    label,
    changed_at: Revision::initial(),
    durability,
    subscribers: @hashset.new(),
    on_change: None,
    commit_pending: None,
  })
  let ops : &CellOps = self.pull.signals[idx]
  self.core.cell_ops.push(ops)
  cell_id
}

///|
/// Validates that a CellId belongs to this runtime and is within bounds.
/// Aborts with a descriptive message on failure.
fn Runtime::validate_cell(self : Runtime, id : CellId, caller : String) -> Unit {
  if id.runtime_id != self.core.runtime_id {
    abort("Cell belongs to a different Runtime")
  }
  if id.id < 0 || id.id >= self.core.cell_ops.length() {
    abort(caller + ": cell_id out of bounds: " + id.id.to_string())
  }
}

///|
/// Returns true if the CellId belongs to this runtime and is within bounds.
/// Non-aborting variant for methods that return None/[] on invalid input.
fn Runtime::validate_cell_soft(self : Runtime, id : CellId) -> Bool {
  id.runtime_id == self.core.runtime_id &&
  id.id >= 0 &&
  id.id < self.core.cell_ops.length()
}

///|
/// Returns the `changed_at` revision for any cell, dispatching via cell_index.
///
/// Covers PullSignal and PullMemo; aborts on unknown or out-of-bounds IDs.
fn Runtime::get_changed_at(self : Runtime, id : CellId) -> Revision {
  self.validate_cell(id, "get_changed_at")
  self.core.cell_ops[id.id].changed_at()
}

///|
/// Returns the `durability` for any cell, dispatching via cell_index.
fn Runtime::get_durability(self : Runtime, id : CellId) -> Durability {
  self.validate_cell(id, "get_durability")
  self.core.cell_ops[id.id].durability()
}

///|
/// Returns the CellId stored in the given SoA entry (reverse lookup).
///
/// Each SoA data struct caches its own CellId so we can round-trip from a
/// CellRef index back to the unified CellId without an extra map.
fn Runtime::cell_id_for(self : Runtime, cell_ref : CellRef) -> CellId {
  match cell_ref {
    PullSignal(idx) => self.pull.signals[idx].cell_id
    PullMemo(idx) => self.pull.memos[idx].cell_id
    PushReactive(idx) => self.push.reactives[idx].cell_id
    PushEffect(idx) => self.push.effects[idx].cell_id
    HybridMemo(idx) => self.push.hybrid_memos[idx].cell_id
    Disposed => abort("cell_id_for: cell has been disposed")
    Relation(idx) => self.datalog.relations[idx].cell_id
    Rule(idx) => self.datalog.rules[idx].cell_id
  }
}

///|
/// Returns the PullSignalData for a signal cell.
///
/// # Panics
///
/// Aborts if the cell belongs to a different runtime or is not a signal.
fn Runtime::get_pull_signal(self : Runtime, id : CellId) -> PullSignalData {
  self.validate_cell(id, "get_pull_signal")
  match self.core.cell_index[id.id] {
    PullSignal(idx) => self.pull.signals[idx]
    _ =>
      abort(
        "Expected signal cell but found different kind: " + id.id.to_string(),
      )
  }
}

///|
/// Returns the PullMemoData for a memo cell.
///
/// # Panics
///
/// Aborts if the cell belongs to a different runtime or is not a memo.
fn Runtime::get_pull_memo(self : Runtime, id : CellId) -> PullMemoData {
  self.validate_cell(id, "get_pull_memo")
  match self.core.cell_index[id.id] {
    PullMemo(idx) => self.pull.memos[idx]
    _ =>
      abort("Expected memo cell but found different kind: " + id.id.to_string())
  }
}

///|
/// Returns the HybridMemoData for a hybrid memo cell.
fn Runtime::get_hybrid_memo(self : Runtime, id : CellId) -> HybridMemoData {
  self.validate_cell(id, "get_hybrid_memo")
  match self.core.cell_index[id.id] {
    HybridMemo(idx) => self.push.hybrid_memos[idx]
    _ =>
      abort(
        "Expected hybrid memo cell but found different kind: " +
        id.id.to_string(),
      )
  }
}

///|
/// Returns an iterator over the subscriber IDs for the given cell.
///
/// Used by Phase 3 push propagation to enumerate cells that must be
/// notified when a cell's value changes. Phase 3 extends this with
/// `PushReactive`, `PushEffect`, and `Disposed` arms.
fn Runtime::get_subscribers(self : Runtime, cell_id : CellId) -> Iter[CellId] {
  self.validate_cell(cell_id, "get_subscribers")
  self.core.cell_ops[cell_id.id].subscribers().iter()
}

///|
/// Removes `subscriber` from the subscriber set of `dep`.
fn Runtime::remove_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  self.validate_cell(dep, "remove_subscriber(dep)")
  self.core.cell_ops[dep.id].subscribers().remove(subscriber)
}

///|
/// Adds `subscriber` to the subscriber set of `dep`.
fn Runtime::add_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  self.validate_cell(dep, "add_subscriber(dep)")
  self.core.cell_ops[dep.id].subscribers().add(subscriber)
}

///|
/// Registers a callback that fires whenever a revision bump occurs.
/// During a batch, it fires once at batch end (only if values actually changed).
///
/// # Parameters
///
/// - `f`: The callback to invoke on change
pub fn Runtime::set_on_change(self : Runtime, f : () -> Unit) -> Unit {
  self.core.on_change = Some(f)
}

///|
/// Removes the on_change callback.
pub fn Runtime::clear_on_change(self : Runtime) -> Unit {
  self.core.on_change = None
}

///|
/// Fires the on_change callback if one is registered.
fn Runtime::fire_on_change(self : Runtime) -> Unit {
  match self.core.on_change {
    Some(f) => f()
    None => ()
  }
}

///|
/// Advance the global revision counter and record which durability level changed.
/// Updates current_revision and all durability_last_changed entries up to dur_idx.
/// Callers must ensure this is only called outside of a batch (batch_depth == 0).
impl RevisionManager for Runtime with advance_revision(self, durability) {
  self.core.current_revision = Revision::next(self.core.current_revision)
  let dur_idx = durability.index()
  for i = 0; i <= dur_idx; i = i + 1 {
    self.core.durability_last_changed[i] = self.core.current_revision
  }
}

///|
/// Mark an input cell as changed at the current revision.
/// Sets changed_at to current_revision on the PullSignalData entry.
/// Must be called after advance_revision so current_revision is already updated.
fn Runtime::mark_input_changed(self : Runtime, id : CellId) -> PullSignalData {
  let sig = self.get_pull_signal(id)
  sig.changed_at = self.core.current_revision
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
impl RevisionManager for Runtime with bump_revision(self, durability) {
  if self.core.batch_depth > 0 {
    // Track the maximum durability seen during this batch
    if durability > self.core.batch_max_durability {
      self.core.batch_max_durability = durability
    }
    return
  }
  self.advance_revision(durability)
}

///|
/// Disposes a push reactive cell, removing it from all subscriber sets
/// and marking its cell_index slot as Disposed.
///
/// See `Reactive::dispose` and Task 7 for the full implementation.
fn Runtime::dispose_reactive(self : Runtime, cell_id : CellId) -> Unit {
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    return
  }
  match self.core.cell_index[cell_id.id] {
    PushReactive(idx) => {
      let reactive = self.push.reactives[idx]
      for dep in reactive.sources {
        self.remove_subscriber(dep, cell_id)
      }
      self.core.cell_index[cell_id.id] = Disposed
      reactive.clear_slot()
      self.push.free_reactives.push(idx)
      self.push.node_count = self.push.node_count - 1
    }
    _ => ()
  }
}

///|
/// Disposes a push effect cell, removing it from all subscriber sets
/// and marking its cell_index slot as Disposed.
fn Runtime::dispose_effect(self : Runtime, cell_id : CellId) -> Unit {
  if cell_id.id < 0 || cell_id.id >= self.core.cell_index.length() {
    return
  }
  match self.core.cell_index[cell_id.id] {
    PushEffect(idx) => {
      let effect = self.push.effects[idx]
      for dep in effect.sources {
        self.remove_subscriber(dep, cell_id)
      }
      self.core.cell_index[cell_id.id] = Disposed
      effect.clear_slot()
      self.push.free_effects.push(idx)
      self.push.node_count = self.push.node_count - 1
    }
    _ => ()
  }
}
