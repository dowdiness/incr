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
/// unified dispatch tables, and cross-engine guards.
///
/// Groups fields that are accessed by all propagation modes: revision tracking
/// (RevisionState), batch management (BatchState), dependency tracking
/// (TrackingState), unified dispatch tables, and cross-engine guards
/// (PropagationPhase).
///
/// # Pointer chase tradeoff
///
/// All sub-struct field accesses (e.g. `self.core.revision.current_revision`) require
/// one extra pointer dereference compared to the old flat layout. MoonBit
/// structs are heap-allocated, so RuntimeCore is a separate heap object.
/// In hot loops (verify dep-walk, push propagation), the sub-struct pointers
/// are cache-hot since they are dereferenced on every iteration. Profile
/// with `moon bench --release` if regressions are suspected.

///|
/// Mutually exclusive runtime phases for cross-engine guards.
///
/// These phases are never active simultaneously. `batch.depth` is
/// orthogonal — batches compose with any propagation phase (e.g.
/// commit_batch temporarily raises batch.depth during callbacks
/// while the propagation phase is Idle).
priv enum PropagationPhase {
  Idle
  PushPropagating
  InFixpoint
  GarbageCollecting
} derive(Eq, Debug)

///|
impl Show for PropagationPhase with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Batch update management: deferred signal writes and rollback.
priv struct BatchState {
  mut depth : Int
  pending : Array[&Committable]
  frames : Array[BatchFrame]
  mut max_durability : Durability
}

///|
/// Dependency tracking: recording which cells are read during computation.
priv struct TrackingState {
  stack : Array[ActiveQuery]
}

///|
/// Revision tracking: global clock and per-durability change timestamps.
priv struct RevisionState {
  mut current_revision : Revision
  durability_last_changed : FixedArray[Revision]
}

///|
priv struct RuntimeCore {
  runtime_id : Int
  revision : RevisionState
  mut next_cell_id : Int
  tracking : TrackingState
  batch : BatchState
  mut on_change : (() -> Unit)?
  cell_index : Array[CellRef]
  cell_ops : Array[&CellOps]
  cell_lifecycle : Array[&CellLifecycle]
  mut phase : PropagationPhase
  /// Reference counts for observed cells. Key = observed CellId,
  /// value = number of live Observer handles. on_unobserve fires only
  /// when count reaches 0.
  gc_root_counts : @hashmap.HashMap[CellId, Int]
}

///|
/// Pull-mode SoA storage (lazy verification).
priv struct PullState {
  signals : Array[PullSignalData]
  memos : Array[MemoData]
  free_signals : Array[Int]
  free_memos : Array[Int]
}

///|
/// Push-mode SoA storage (eager propagation).
priv struct PushState {
  reactives : Array[PushReactiveData]
  effects : Array[PushEffectData]
  free_reactives : Array[Int]
  free_effects : Array[Int]
  /// Count of live push cells (reactives + effects only).
  /// HybridMemo does NOT contribute to this count — it relies on
  /// verified_at staleness detection rather than push propagation.
  /// Used as an O(1) gate before push propagation.
  mut node_count : Int
}

///|
/// Datalog SoA storage (fixpoint evaluation).
priv struct DatalogState {
  relations : Array[RelationData]
  functional_relations : Array[FunctionalRelationData]
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

///|
pub(all) struct Runtime {
  priv core : RuntimeCore
  priv pull : PullState
  priv push : PushState
  priv datalog : DatalogState
  // Accumulator state. Monotonic array; disposed slots keep their index
  // (their `disposed` field is set true). No slot-id reuse.
  priv accumulator_slots : Array[SlotMeta]
  priv mut next_accumulator_id : Int
  // Reverse index: for each memo, which accumulator slots it has pushed to.
  // Populated on successful recompute commit; used for BEFORE_CLOSURE snapshot
  // iteration and memo disposal cleanup.
  priv accumulator_contributions : @hashmap.HashMap[
    @incr_types.CellId,
    @hashset.HashSet[@incr_types.AccumulatorId],
  ]

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
      revision: {
        current_revision: Revision::initial(),
        durability_last_changed: FixedArray::make(
          @incr_types.DURABILITY_COUNT,
          Revision::initial(),
        ),
      },
      next_cell_id: 0,
      tracking: { stack: [] },
      batch: { depth: 0, pending: [], frames: [], max_durability: Low },
      on_change,
      cell_index: [],
      cell_ops: [],
      cell_lifecycle: [],
      phase: Idle,
      gc_root_counts: @hashmap.new(),
    },
    pull: { signals: [], memos: [], free_signals: [], free_memos: [] },
    push: {
      reactives: [],
      effects: [],
      free_reactives: [],
      free_effects: [],
      node_count: 0,
    },
    datalog: { relations: [], functional_relations: [], rules: [] },
    accumulator_slots: [],
    next_accumulator_id: 0,
    accumulator_contributions: @hashmap.new(),
  }
}

///|
/// Transitions to a new propagation phase.
///
/// Aborts if the current phase is not `Idle` — phases are mutually
/// exclusive. The one exception is returning to `Idle`, which is
/// always allowed from any active phase (used in finally-style cleanup).
fn Runtime::enter_phase(self : Runtime, next : PropagationPhase) -> Unit {
  guard self.core.phase is Idle else {
    abort(
      "enter_phase: cannot enter " +
      next.to_string() +
      " while in " +
      self.core.phase.to_string(),
    )
  }
  self.core.phase = next
}

///|
/// Returns to the Idle phase. Unconditional — always succeeds.
fn Runtime::leave_phase(self : Runtime) -> Unit {
  self.core.phase = Idle
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
/// Installs a new cell into a reusable-slot SoA array and registers it in
/// the unified dispatch tables (`cell_ops`, `cell_lifecycle`). Shared by
/// Signal, Memo, Reactive, and Effect constructors.
///
/// Steps:
/// 1. Reuse a freed slot from `free_list` if available, else append.
/// 2. Allocate a fresh `CellId` with `make_ref(idx)` as its `CellRef`.
/// 3. Construct the SoA payload via `make_data(cell_id)` (the caller's
///    factory; given a cell_id so the payload's `meta.cell_id` can match).
/// 4. Write payload into slot; register trait objects in the dispatch tables.
///
/// Datalog cells do NOT use this path — their arrays are append-only
/// (no free-list, disposed slots are not reused).
fn[T : CellOps + CellLifecycle] Runtime::install_cell(
  self : Runtime,
  free_list : Array[Int],
  arr : Array[T],
  make_ref : (Int) -> CellRef,
  make_data : (CellId) -> T,
) -> (CellId, Int) {
  let idx = free_list.pop().unwrap_or(arr.length())
  let cell_id = self.alloc_cell_id(make_ref(idx))
  let data = make_data(cell_id)
  if idx < arr.length() {
    arr[idx] = data
  } else {
    arr.push(data)
  }
  self.core.cell_ops.push(arr[idx])
  self.core.cell_lifecycle.push(arr[idx])
  (cell_id, idx)
}

///|
/// Debug invariant: the three unified dispatch tables (`cell_index`,
/// `cell_ops`, `cell_lifecycle`) must stay index-aligned. Every cell
/// allocation pushes into all three; every disposal updates the slot
/// in-place. Whitebox tests call this after exercising allocation/disposal
/// paths to pin the invariant that `install_cell` + `dispose_cell` uphold.
fn Runtime::check_table_invariant(self : Runtime) -> Unit {
  let ci = self.core.cell_index.length()
  let co = self.core.cell_ops.length()
  let cl = self.core.cell_lifecycle.length()
  if ci != co || co != cl {
    abort(
      "Runtime dispatch tables out of sync: cell_index=" +
      ci.to_string() +
      ", cell_ops=" +
      co.to_string() +
      ", cell_lifecycle=" +
      cl.to_string(),
    )
  }
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
/// Returns true if a cell has been disposed or its id is out of bounds.
fn Runtime::is_cell_disposed(self : Runtime, cell_id : CellId) -> Bool {
  let id = cell_id.id
  id < 0 ||
  id >= self.core.cell_index.length() ||
  self.core.cell_index[id] is Disposed
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
    PullSignal(idx) => self.pull.signals[idx].meta.cell_id
    PullMemo(idx) => self.pull.memos[idx].meta.cell_id
    PushReactive(idx) => self.push.reactives[idx].meta.cell_id
    PushEffect(idx) => self.push.effects[idx].meta.cell_id
    HybridMemo(idx) => self.pull.memos[idx].meta.cell_id
    Disposed => abort("cell_id_for: cell has been disposed")
    Relation(idx) => self.datalog.relations[idx].meta.cell_id
    FunctionalRelation(idx) =>
      self.datalog.functional_relations[idx].meta.cell_id
    Rule(idx) => self.datalog.rules[idx].meta.cell_id
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
/// Returns the MemoData for a memo or hybrid memo cell.
///
/// # Panics
///
/// Aborts if the cell belongs to a different runtime or is not a memo.
fn Runtime::get_memo_data(self : Runtime, id : CellId) -> MemoData {
  self.validate_cell(id, "get_memo_data")
  match self.core.cell_index[id.id] {
    PullMemo(idx) | HybridMemo(idx) => self.pull.memos[idx]
    _ =>
      abort("Expected memo cell but found different kind: " + id.id.to_string())
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
/// Removes `subscriber` from the subscriber set of `dep` and decrements the
/// subscriber's push contribution from upstream cells.
///
/// Contribution is computed BEFORE the subscriber's CellRef can be set to
/// Disposed by the caller — this ordering is critical.
fn Runtime::remove_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  self.validate_cell(dep, "remove_subscriber(dep)")
  let contribution = self.push_contribution(subscriber)
  let removed = self.core.cell_ops[dep.id]
    .subscribers()
    .remove_and_check(subscriber)
  if removed && contribution > 0 {
    self.adjust_push_reachable([dep], -contribution)
  }
}

///|
/// Adds `subscriber` to the subscriber set of `dep` and propagates the
/// subscriber's push contribution upstream through the pull dep graph.
fn Runtime::add_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  self.validate_cell(dep, "add_subscriber(dep)")
  let subs = self.core.cell_ops[dep.id].subscribers()
  if subs.contains(subscriber) {
    return
  }
  subs.add(subscriber)
  let contribution = self.push_contribution(subscriber)
  if contribution > 0 {
    self.adjust_push_reachable([dep], contribution)
  }
}

///|
/// Returns the push-reachable contribution of `sub_id` as a subscriber.
///
/// - `PushReactive` / `PushEffect` -> 1 (they are push cells themselves)
/// - `PullMemo` / `HybridMemo` -> their current `push_reachable_count`
///   (they propagate their downstream push count upward)
/// - All other variants -> 0
fn Runtime::push_contribution(self : Runtime, sub_id : CellId) -> Int {
  if sub_id.id < 0 || sub_id.id >= self.core.cell_index.length() {
    return 0
  }
  match self.core.cell_index[sub_id.id] {
    PushReactive(_) | PushEffect(_) => 1
    PullMemo(i) | HybridMemo(i) => self.pull.memos[i].meta.push_reachable_count
    _ => 0
  }
}

///|
/// Collects all cells reachable upstream of `sources` through the pull
/// dependency graph.
///
/// Rules:
/// - `PullSignal` -> add to set, stop (leaf)
/// - `PullMemo` / `HybridMemo` -> add to set, recurse into `dependencies`
/// - `PushReactive`, `Relation`, `FunctionalRelation`, `Rule` ->
///     add to set, stop (leaf in count-propagation graph; do NOT recurse)
/// - `Disposed` -> skip
/// - Already-visited cells are skipped (handles diamond fan-in)
fn Runtime::collect_reachable_cells(
  self : Runtime,
  sources : Array[CellId],
) -> @hashset.HashSet[CellId] {
  let result : @hashset.HashSet[CellId] = @hashset.new()
  let worklist : Array[CellId] = []
  for id in sources {
    worklist.push(id)
  }
  let mut wi = 0
  while wi < worklist.length() {
    let id = worklist[wi]
    wi += 1
    if result.contains(id) {
      continue
    }
    if id.id < 0 || id.id >= self.core.cell_index.length() {
      continue
    }
    match self.core.cell_index[id.id] {
      Disposed => ()
      PullSignal(_) => result.add(id)
      PushReactive(_) | Relation(_) | FunctionalRelation(_) | Rule(_) =>
        result.add(id)
      PullMemo(i) | HybridMemo(i) => {
        result.add(id)
        for dep in self.pull.memos[i].dependencies {
          worklist.push(dep)
        }
      }
      PushEffect(_) => ()
    }
  }
  result
}

///|
/// Adjusts `push_reachable_count` by `delta` on every cell reachable upstream
/// of `sources` (including the sources themselves).
///
/// Asserts that no count goes negative.
fn Runtime::adjust_push_reachable(
  self : Runtime,
  sources : Array[CellId],
  delta : Int,
) -> Unit {
  let cells = self.collect_reachable_cells(sources)
  for id in cells {
    // CellMeta is heap-allocated — extracting it gives a mutable reference.
    let meta = match self.core.cell_index[id.id] {
      PullSignal(i) => self.pull.signals[i].meta
      PullMemo(i) | HybridMemo(i) => self.pull.memos[i].meta
      PushReactive(i) => self.push.reactives[i].meta
      PushEffect(i) => self.push.effects[i].meta
      Relation(i) => self.datalog.relations[i].meta
      FunctionalRelation(i) => self.datalog.functional_relations[i].meta
      Rule(i) => self.datalog.rules[i].meta
      Disposed => continue
    }
    let new_count = meta.push_reachable_count + delta
    if new_count < 0 {
      abort(
        "adjust_push_reachable: count went negative for cell " +
        id.id.to_string() +
        " (delta=" +
        delta.to_string() +
        ", was=" +
        meta.push_reachable_count.to_string() +
        ")",
      )
    }
    meta.push_reachable_count = new_count
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
/// Core propagation coordinator: advances the revision, stamps changed_at on
/// all changed cells, and runs push propagation if any push cells exist.
///
/// This is the single entry point for push propagation. All paths that notify
/// the runtime of cell value changes call this method. Callers handle their
/// own callback sequencing around it:
///
/// - `publish_cell_changes`: adds `fire_on_change()` (simple path for fixpoint)
/// - `commit_batch`: snapshots per-signal callbacks before, fires after
/// - `signal.set_unconditional`: snapshots per-signal callback before, fires after
fn Runtime::propagate_changes(
  self : Runtime,
  changed_ids : Array[CellId],
  durability : Durability,
) -> Unit {
  self.advance_revision(durability)
  for id in changed_ids {
    self.core.cell_ops[id.id].set_changed_at(
      self.core.revision.current_revision,
    )
  }
  if self.push.node_count > 0 {
    self.push_propagate_from(changed_ids)
  }
}

///|
/// Kernel notification protocol: notifies the runtime that a set of cells
/// has new values.
///
/// Delegates to `propagate_changes` for revision bump, changed_at stamping,
/// and push propagation, then fires the global `on_change` callback.
///
/// Use this for callers that don't need custom callback sequencing (e.g.
/// `fixpoint`). Callers that interleave per-cell callbacks with propagation
/// (e.g. `commit_batch`, `signal.set_unconditional`) call `propagate_changes`
/// directly and manage their own callback timing.
///
/// # Parameters
///
/// - `changed_ids`: The cell IDs whose values changed
/// - `durability`: Durability level of the change
fn Runtime::publish_cell_changes(
  self : Runtime,
  changed_ids : Array[CellId],
  durability : Durability,
) -> Unit {
  self.propagate_changes(changed_ids, durability)
  self.fire_on_change()
}

///|
/// Advance the global revision counter and record which durability level changed.
/// Updates current_revision and all durability_last_changed entries up to dur_idx.
/// Callers must ensure this is only called outside of a batch (batch_depth == 0).
impl RevisionManager for Runtime with advance_revision(self, durability) {
  self.core.revision.current_revision = Revision::next(
    self.core.revision.current_revision,
  )
  let dur_idx = durability.index()
  for i = 0; i <= dur_idx; i = i + 1 {
    self.core.revision.durability_last_changed[i] = self.core.revision.current_revision
  }
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
  if self.core.batch.depth > 0 {
    // Track the maximum durability seen during this batch
    if durability > self.core.batch.max_durability {
      self.core.batch.max_durability = durability
    }
    return
  }
  self.advance_revision(durability)
}

///|
/// Guards against disposing a cell during fixpoint or its own computation.
fn Runtime::guard_dispose(self : Runtime, cell_id : CellId) -> Unit {
  guard !(self.core.phase is InFixpoint) else {
    abort("dispose: cannot dispose cells during fixpoint()")
  }
  for aq in self.core.tracking.stack {
    guard aq.cell_id != cell_id else {
      abort("dispose: cannot dispose a cell during its own computation")
    }
  }
}

///|
/// Disposes a rule cell. Public because RuleId has no runtime reference,
/// so the user must call `rt.dispose_rule(rule_id)` directly.
pub fn Runtime::dispose_rule(
  self : Runtime,
  rule_id : @incr_types.RuleId,
) -> Unit {
  self.dispose_cell(rule_id.id)
}

///|
/// Disposes a cell by CellId, dispatching via CellLifecycle trait.
///
/// Validates runtime ownership, checks idempotency, and calls guard_dispose
/// before dispatching to the type-specific dispose implementation.
pub fn Runtime::dispose_cell(self : Runtime, cell_id : CellId) -> Unit {
  guard cell_id.runtime_id == self.core.runtime_id else {
    abort("dispose_cell: CellId belongs to a different Runtime")
  }
  guard !self.is_cell_disposed(cell_id) else { return }
  self.guard_dispose(cell_id)
  // Clean up gc_root_counts to prevent leaks when observed cells
  // are manually disposed before their observers.
  self.core.gc_root_counts.remove(cell_id)
  self.core.cell_lifecycle[cell_id.id].dispose_cell(self, cell_id)
}

///|
/// Increments the observer reference count for a cell.
/// Returns the previous count (0 means this is the first observer).
fn Runtime::add_gc_root(self : Runtime, id : CellId) -> Int {
  match self.core.gc_root_counts.get(id) {
    Some(n) => {
      self.core.gc_root_counts.set(id, n + 1)
      n
    }
    None => {
      self.core.gc_root_counts.set(id, 1)
      0
    }
  }
}

///|
/// Decrements the observer reference count for a cell.
/// Removes the entry when count reaches 0. Returns remaining count.
fn Runtime::remove_gc_root(self : Runtime, id : CellId) -> Int {
  match self.core.gc_root_counts.get(id) {
    Some(n) if n > 1 => {
      self.core.gc_root_counts.set(id, n - 1)
      n - 1
    }
    Some(_) => {
      self.core.gc_root_counts.remove(id)
      0
    }
    None => 0
  }
}

///|
/// Reconstructs a CellId from a cell_ops array index.
fn Runtime::cell_id_at(self : Runtime, i : Int) -> CellId {
  { runtime_id: self.core.runtime_id, id: i }
}

///|
/// Runs mark-and-sweep garbage collection on the dependency graph.
///
/// Disposes all Interior cells (Memo, HybridMemo, Reactive) that are
/// unreachable from any gc root (observed cells) or implicit root (Effect).
/// Source cells (Signal, Relation, FunctionalRelation, Rule) are never collected.
pub fn Runtime::gc(self : Runtime) -> Unit {
  guard self.core.tracking.stack.is_empty() else {
    // Clean up global state before aborting so panic tests don't
    // contaminate subsequent tests via current_computing_runtime_id.
    self.core.tracking.stack.clear()
    current_computing_runtime_id.val = -1
    abort("gc: cannot run during active computation")
  }
  guard self.core.batch.depth == 0 else { abort("gc: cannot run during batch") }
  guard self.core.phase is Idle else {
    abort("gc: cannot run during " + self.core.phase.to_string())
  }
  self.enter_phase(GarbageCollecting)
  self.gc_sweep()
  self.leave_phase()
}

///|
/// Collects all GC roots: explicitly observed cells + implicit roots (Effects).
fn Runtime::collect_gc_roots(self : Runtime) -> Array[CellId] {
  let roots : Array[CellId] = []
  for id, _ in self.core.gc_root_counts {
    roots.push(id)
  }
  // Implicit roots: live cells with gc_role == Root (Effects)
  for i = 0; i < self.core.cell_ops.length(); i = i + 1 {
    match self.core.cell_index[i] {
      Disposed => continue
      _ => ()
    }
    if self.core.cell_ops[i].gc_role() is Root {
      roots.push(self.cell_id_at(i))
    }
  }
  roots
}

///|
/// Marks all cells reachable from `roots` via gc_dependencies BFS.
fn Runtime::mark_reachable(
  self : Runtime,
  roots : Array[CellId],
) -> @hashset.HashSet[CellId] {
  let reachable : @hashset.HashSet[CellId] = @hashset.new()
  let worklist : Array[CellId] = Array::from_iter(roots.iter())
  let mut wi = 0
  while wi < worklist.length() {
    let id = worklist[wi]
    wi += 1
    if reachable.contains(id) {
      continue
    }
    match self.core.cell_index[id.id] {
      Disposed => continue
      _ => ()
    }
    reachable.add(id)
    for dep in self.core.cell_ops[id.id].gc_dependencies() {
      worklist.push(dep)
    }
  }
  reachable
}

///|
/// Sweep phase: dispose Interior cells not in the reachable set.
fn Runtime::gc_sweep(self : Runtime) -> Unit {
  let roots = self.collect_gc_roots()
  let reachable = self.mark_reachable(roots)
  for i = 0; i < self.core.cell_ops.length(); i = i + 1 {
    match self.core.cell_index[i] {
      Disposed => continue
      _ => ()
    }
    if self.core.cell_ops[i].gc_role() is Interior {
      let id = self.cell_id_at(i)
      if !reachable.contains(id) {
        self.dispose_cell(id)
      }
    }
  }
}
