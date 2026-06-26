///|
/// Central coordinator for the incremental computation framework.
///
/// The Runtime manages all bookkeeping for dependency tracking, revision
/// counting, and batch operations. Every Signal and Memo is associated
/// with exactly one Runtime.
///
/// # Pointer chase tradeoff
///
/// All sub-struct field accesses (e.g. `self.core.revision.current_revision`)
/// require one extra pointer dereference compared to the old flat layout.
/// MoonBit structs are heap-allocated, so RuntimeCore is a separate heap
/// object. In hot loops (verify dep-walk, push propagation), the sub-struct
/// pointers are cache-hot since they are dereferenced on every iteration.
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
  priv mut evaluation_strategies : EvaluationStrategies
  // cell_lifecycle is lifted out of RuntimeCore: the CellLifecycle trait
  // takes `Runtime` as a parameter (see cells/cell_ops.mbt), so moving it
  // into kernel would create a circular type reference.
  priv cell_lifecycle : Array[&CellLifecycle]
  // Commit-phase hooks for pull-mode memo recomputes, dispatched from
  // `memo_force_recompute`. Same placement rationale as cell_lifecycle:
  // MemoCommitPhase takes Runtime as a parameter (see
  // cells/memo_commit_phase.mbt), so the array cannot live in kernel.
  priv commit_hooks : Array[&MemoCommitPhase]
  priv mut static_recompute_depth : Int
  priv static_recompute_tracking_floors : Array[Int]
  priv static_recompute_previous_runtime_ids : Array[@incr_types.RuntimeId?]
  priv accumulator_commit_hook : AccumulatorCommitHook
  priv event_broadcast_hook : EventBroadcastPhaseHook
  priv event_broadcast_hook_index : Int
  priv runtime_evaluation_event_hook : RuntimeEvaluationEventHook
  priv runtime_evaluation_event_hook_index : Int
  // Accumulator state. Monotonic array; disposed slots keep their index
  // (their `disposed` field is set true). No slot-id reuse.
  priv accumulator_slots : Array[SlotMeta]
  // Cached trait-object view of `accumulator_slots`, kept index-aligned
  // by `register_accumulator_slot`. Runtime returns this array directly
  // from `slot_snapshots()` so kernel-side verify code does not allocate
  // per call.
  priv accumulator_snapshots : Array[&@shared.SlotSnapshot]
  priv mut next_accumulator_id : Int
  // Reverse index: for each memo, which accumulator slots it has pushed to.
  // Populated on successful recompute commit; used for BEFORE_CLOSURE snapshot
  // iteration and memo disposal cleanup.
  priv accumulator_contributions : @hashmap.HashMap[
    @incr_types.CellId,
    @hashset.HashSet[@incr_types.AccumulatorId],
  ]
}

///|
/// Constructor-syntax alias of `Runtime::new`. Enables `Runtime()` /
/// `Runtime(on_change=...)` call sites.
pub fn Runtime::Runtime(on_change? : () -> Unit) -> Runtime {
  Runtime::new(on_change?)
}

///|
/// Returns this runtime's identity.
///
/// Use it to ask "are these two runtimes the same?" (`a.id() == b.id()`)
/// without allocating a probe cell to read a `CellId`'s `runtime_id`. A
/// `RuntimeId` is a debug / introspection identity, not a stable application
/// key — see `RuntimeId`.
pub fn Runtime::id(self : Runtime) -> @incr_types.RuntimeId {
  self.core.runtime_id
}

///|
/// Creates a new runtime with an empty dependency graph.
///
/// # Parameters
///
/// - `on_change`: Optional callback invoked whenever any signal changes
///   (or at the end of a batch if values actually changed).
pub fn Runtime::new(on_change? : () -> Unit) -> Runtime {
  let id = @kernel.alloc_runtime_id()
  let accumulator_hook = AccumulatorCommitHook::new()
  let event_hook = EventBroadcastPhaseHook::new()
  let runtime_event_hook = RuntimeEvaluationEventHook::new()
  let rt : Runtime = {
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
      callback_depth: 0,
      on_change_listeners: @kernel.ListenerRegistry::new(),
      next_listener_id: 0,
      cell_index: [],
      cell_ops: [],
      phase: Idle,
      gc_root_counts: @hashmap.HashMap([]),
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
    evaluation_strategies: EvaluationStrategies::default(),
    cell_lifecycle: [],
    commit_hooks: [],
    static_recompute_depth: 0,
    static_recompute_tracking_floors: [],
    static_recompute_previous_runtime_ids: [],
    accumulator_commit_hook: accumulator_hook,
    event_broadcast_hook: event_hook,
    event_broadcast_hook_index: 1,
    runtime_evaluation_event_hook: runtime_event_hook,
    runtime_evaluation_event_hook_index: 2,
    accumulator_slots: [],
    accumulator_snapshots: [],
    next_accumulator_id: 0,
    accumulator_contributions: @hashmap.HashMap([]),
  }
  // Register the same hook objects in dispatch order.
  rt.commit_hooks.push(accumulator_hook)
  rt.commit_hooks.push(event_hook)
  rt.commit_hooks.push(runtime_event_hook)
  // Seed the optional constructor on_change callback through the registry's
  // singleton slot, preserving `Runtime(on_change=...)` semantics.
  match on_change {
    Some(f) => rt.set_on_change(f)
    None => ()
  }
  rt
}

///|
/// Replaces the sealed internal evaluation strategy bundle.
fn Runtime::install_evaluation_strategies(
  self : Runtime,
  strategies : EvaluationStrategies,
) -> Unit {
  self.runtime_evaluation_event_hook.trace_recorder = strategies.trace_recorder()
  self.evaluation_strategies = strategies
}

///|
fn Runtime::event_broadcast_enabled(self : Runtime) -> Bool {
  !self.event_broadcast_hook.listeners.is_empty()
}

///|
/// Allocates a fresh listener id (shared counter across both registries).
fn Runtime::alloc_listener_id(self : Runtime) -> ListenerId {
  @kernel.alloc_listener_id(self.core)
}

///|
fn Runtime::runtime_evaluation_events_enabled(self : Runtime) -> Bool {
  self.runtime_evaluation_event_hook.enabled()
}

///|
fn Runtime::has_pending_events(self : Runtime) -> Bool {
  !self.event_broadcast_hook.pending.is_empty() ||
  !self.runtime_evaluation_event_hook.pending.is_empty()
}

///|
fn Runtime::runtime_evaluation_event_sink(
  self : Runtime,
) -> ((@kernel.RuntimeEvaluationEvent) -> Unit)? {
  if self.runtime_evaluation_event_hook.listener_enabled() {
    Some(fn(event) { self.runtime_evaluation_event_hook.push_event(event) })
  } else {
    None
  }
}

///|
fn Runtime::is_listener_mutation_safe(self : Runtime) -> Bool {
  self.core.phase is Idle &&
  self.core.callback_depth == 0 &&
  self.core.tracking.stack.is_empty() &&
  self.core.batch.depth == 0 &&
  self.static_recompute_depth == 0 &&
  !self.has_pending_events() &&
  !self.event_broadcast_hook.draining &&
  !self.runtime_evaluation_event_hook.draining
}

///|
fn Runtime::derived_event_listener_busy_message(operation : String) -> String {
  operation +
  " cannot be called while an operation is in flight: drain in progress, " +
  "events buffered, callback active, batch open, recompute active, or non-Idle phase " +
  "(PushPropagating/InFixpoint/GarbageCollecting)"
}

///|
/// Registers the singleton derived recompute lifecycle event listener.
///
/// Re-registering replaces the previous singleton listener in place (its
/// registration position is preserved). Coexists with any additive listeners
/// registered via `add_derived_event_listener`. Raises `Failure` unless the
/// runtime is between operations (see `is_listener_mutation_safe`).
pub fn Runtime::on_derived_event(
  self : Runtime,
  f : (DerivedEvent) -> Unit,
) -> Unit raise Failure {
  guard self.is_listener_mutation_safe() else {
    fail(
      Runtime::derived_event_listener_busy_message("Runtime::on_derived_event"),
    )
  }
  self.event_broadcast_hook.listeners.set_singleton(
    () => self.alloc_listener_id(),
    f,
  )
}

///|
/// Clears the singleton derived recompute lifecycle event listener. Idempotent;
/// additive listeners are unaffected. Raises `Failure` unless the runtime is
/// between operations.
pub fn Runtime::clear_derived_event_listener(
  self : Runtime,
) -> Unit raise Failure {
  guard self.is_listener_mutation_safe() else {
    fail(
      Runtime::derived_event_listener_busy_message(
        "Runtime::clear_derived_event_listener",
      ),
    )
  }
  self.event_broadcast_hook.listeners.clear_singleton()
}

///|
/// Adds a composable derived-event listener and returns its `ListenerId`.
///
/// Multiple additive listeners (and the singleton) coexist on one runtime and
/// fire event-major in registration order. Remove a specific listener with
/// `remove_derived_event_listener`. Raises `Failure` unless the runtime is
/// between operations (same idle guard as `on_derived_event`): the derived-event
/// hook buffers events, so registration must not race a buffered/draining
/// window.
pub fn Runtime::add_derived_event_listener(
  self : Runtime,
  f : (DerivedEvent) -> Unit,
) -> ListenerId raise Failure {
  guard self.is_listener_mutation_safe() else {
    fail(
      Runtime::derived_event_listener_busy_message(
        "Runtime::add_derived_event_listener",
      ),
    )
  }
  let id = self.alloc_listener_id()
  self.event_broadcast_hook.listeners.add(id, f)
  id
}

///|
/// Removes the additive derived-event listener with `id`. Idempotent — an
/// unknown or already-removed id is a no-op. Raises `Failure` unless the runtime
/// is between operations (same idle guard rationale as registration).
pub fn Runtime::remove_derived_event_listener(
  self : Runtime,
  id : ListenerId,
) -> Unit raise Failure {
  guard self.is_listener_mutation_safe() else {
    fail(
      Runtime::derived_event_listener_busy_message(
        "Runtime::remove_derived_event_listener",
      ),
    )
  }
  self.event_broadcast_hook.listeners.remove(id) |> ignore
}

///|
fn Runtime::dispatch_before_recompute_hooks(
  self : Runtime,
  cell_id : CellId,
) -> Unit {
  let event_enabled = self.event_broadcast_enabled()
  let runtime_event_enabled = self.runtime_evaluation_events_enabled()
  if !event_enabled &&
    !runtime_event_enabled &&
    self.commit_hooks.length() == self.runtime_evaluation_event_hook_index + 1 {
    self.accumulator_commit_hook.before_recompute(self, cell_id)
    return
  }
  for i = 0; i < self.commit_hooks.length(); i = i + 1 {
    if (event_enabled || i != self.event_broadcast_hook_index) &&
      (runtime_event_enabled || i != self.runtime_evaluation_event_hook_index) {
      self.commit_hooks[i].before_recompute(self, cell_id)
    }
  }
}

///|
fn Runtime::dispatch_after_abort_hooks(
  self : Runtime,
  cell_id : CellId,
  error : Error,
) -> Unit {
  let event_enabled = self.event_broadcast_enabled()
  let runtime_event_enabled = self.runtime_evaluation_events_enabled()
  if !event_enabled &&
    !runtime_event_enabled &&
    self.commit_hooks.length() == self.runtime_evaluation_event_hook_index + 1 {
    self.accumulator_commit_hook.after_abort(self, cell_id, error)
    return
  }
  for i = 0; i < self.commit_hooks.length(); i = i + 1 {
    if (event_enabled || i != self.event_broadcast_hook_index) &&
      (runtime_event_enabled || i != self.runtime_evaluation_event_hook_index) {
      self.commit_hooks[i].after_abort(self, cell_id, error)
    }
  }
}

///|
fn Runtime::dispatch_after_success_hooks(
  self : Runtime,
  cell_id : CellId,
) -> Unit {
  let event_enabled = self.event_broadcast_enabled()
  let runtime_event_enabled = self.runtime_evaluation_events_enabled()
  if !event_enabled &&
    !runtime_event_enabled &&
    self.commit_hooks.length() == self.runtime_evaluation_event_hook_index + 1 {
    self.accumulator_commit_hook.after_success(self, cell_id)
    return
  }
  for i = 0; i < self.commit_hooks.length(); i = i + 1 {
    if (event_enabled || i != self.event_broadcast_hook_index) &&
      (runtime_event_enabled || i != self.runtime_evaluation_event_hook_index) {
      self.commit_hooks[i].after_success(self, cell_id)
    }
  }
}

///|
fn Runtime::drain_pending_events_direct(self : Runtime) -> Unit {
  if self.static_recompute_depth != 0 {
    return
  }
  let mut progressed = true
  while self.has_pending_events() && progressed {
    progressed = false
    if !self.event_broadcast_hook.pending.is_empty() &&
      !self.event_broadcast_hook.draining {
      self.event_broadcast_hook.drain()
      progressed = true
    }
    if !self.runtime_evaluation_event_hook.pending.is_empty() &&
      !self.runtime_evaluation_event_hook.draining {
      self.runtime_evaluation_event_hook.drain()
      progressed = true
    }
  }
}

///|
/// Drains pending events when no recompute frame or callback is active.
fn Runtime::drain_pending_events_if_idle(self : Runtime) -> Unit {
  if self.core.callback_depth != 0 ||
    !self.core.tracking.stack.is_empty() ||
    self.static_recompute_depth != 0 {
    return
  }
  self.drain_pending_events_direct()
}

///|
/// Transitions to a new propagation phase. Delegates to `@kernel.enter_phase`.
fn Runtime::enter_phase(self : Runtime, next : PropagationPhase) -> Unit {
  @kernel.enter_phase(self.core, next)
}

///|
/// Returns to the Idle phase. Delegates to `@kernel.leave_phase`.
fn Runtime::leave_phase(self : Runtime) -> Unit {
  @kernel.leave_phase(self.core)
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
fn Runtime::alloc_cell_id(self : Runtime, cell_ref : CellRef) -> CellId {
  let cell_id = self.alloc_next_id()
  self.core.cell_index.push(cell_ref)
  cell_id
}

///|
/// Installs a new cell into a reusable-slot SoA array and registers it in
/// the unified dispatch tables (`cell_ops`, `cell_lifecycle`). Shared by
/// Signal, Memo, Reactive, and Effect constructors.
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
  self.cell_lifecycle.push(arr[idx])
  (cell_id, idx)
}

///|
/// Debug invariant: the three unified dispatch tables (`cell_index`,
/// `cell_ops`, `cell_lifecycle`) must stay index-aligned.
fn Runtime::check_table_invariant(self : Runtime) -> Unit {
  let ci = self.core.cell_index.length()
  let co = self.core.cell_ops.length()
  let cl = self.cell_lifecycle.length()
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
/// Debug invariant: `accumulator_slots` and `accumulator_snapshots` must
/// stay index-aligned. Only `register_accumulator_slot` writes both; this
/// assertion exists to catch a future mutation path that forgets to
/// update the cached trait-object view (Stage 3+ may add one).
fn Runtime::check_accumulator_cache_invariant(self : Runtime) -> Unit {
  let a = self.accumulator_slots.length()
  let b = self.accumulator_snapshots.length()
  if a != b {
    abort(
      "accumulator cache out of sync: slots=" +
      a.to_string() +
      ", snapshots=" +
      b.to_string(),
    )
  }
}

///|
/// Validates that a CellId belongs to this runtime and is within bounds.
/// Aborts with a descriptive message on failure.
fn Runtime::validate_cell(self : Runtime, id : CellId, caller : String) -> Unit {
  @kernel.validate_cell(self.core, id, caller)
}

///|
/// Returns true if the CellId belongs to this runtime and is within bounds.
/// Non-aborting variant for methods that return None/[] on invalid input.
fn Runtime::validate_cell_soft(self : Runtime, id : CellId) -> Bool {
  @kernel.validate_cell_soft(self.core, id)
}

///|
/// Returns true if a cell has been disposed or its id is out of bounds.
fn Runtime::is_cell_disposed(self : Runtime, cell_id : CellId) -> Bool {
  @kernel.is_cell_disposed(self.core, cell_id)
}

///|
/// Returns the `changed_at` revision for any cell, dispatching via cell_index.
fn Runtime::get_changed_at(self : Runtime, id : CellId) -> Revision {
  @kernel.get_changed_at(self.core, id)
}

///|
/// Returns the `durability` for any cell, dispatching via cell_index.
fn Runtime::get_durability(self : Runtime, id : CellId) -> Durability {
  @kernel.get_durability(self.core, id)
}

///|
/// Returns the PullSignalData for a signal cell.
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
fn Runtime::get_subscribers(self : Runtime, cell_id : CellId) -> Iter[CellId] {
  @kernel.get_subscribers(self.core, cell_id)
}

///|
/// Returns the cached trait-object view of accumulator slots.
///
/// Stage 2 adds this accessor so forthcoming kernel algorithms can reach
/// slot state through the `SlotSnapshot` trait without depending on the
/// concrete (private) `SlotMeta` struct. The array is kept index-aligned
/// with `accumulator_slots` by `register_accumulator_slot`.
///
/// The returned array aliases the runtime's cached field — callers must
/// treat it as read-only. Pushing, removing, or replacing entries would
/// break the `accumulator_slots` ↔ `accumulator_snapshots` alignment
/// asserted by `check_accumulator_cache_invariant`.
fn Runtime::slot_snapshots(self : Runtime) -> Array[&@shared.SlotSnapshot] {
  self.accumulator_snapshots
}

///|
/// Removes `subscriber` from the subscriber set of `dep` and decrements the
/// subscriber's push contribution from upstream cells.
fn Runtime::remove_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  @kernel.remove_subscriber(
    self.core,
    self.pull,
    self.push,
    self.datalog,
    dep,
    subscriber,
  )
}

///|
/// Adds `subscriber` to the subscriber set of `dep` and propagates the
/// subscriber's push contribution upstream through the pull dep graph.
fn Runtime::add_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  @kernel.add_subscriber(
    self.core,
    self.pull,
    self.push,
    self.datalog,
    dep,
    subscriber,
  )
}

///|
/// Registers the singleton on-change callback that fires whenever a revision
/// bump occurs.
///
/// Re-registering replaces the previous singleton in place (registration
/// position preserved). Coexists with additive listeners registered via
/// `add_on_change_listener`. Unlike the derived-event hook, on-change has no
/// buffer/drain state and is read as a snapshot at one well-defined point, so
/// registration is not phase-guarded.
pub fn Runtime::set_on_change(self : Runtime, f : () -> Unit) -> Unit {
  self.core.on_change_listeners.set_singleton(() => self.alloc_listener_id(), f)
}

///|
/// Removes the singleton on-change callback. Idempotent; additive listeners are
/// unaffected.
pub fn Runtime::clear_on_change(self : Runtime) -> Unit {
  self.core.on_change_listeners.clear_singleton()
}

///|
/// Adds a composable on-change listener and returns its `ListenerId`.
///
/// Multiple additive listeners (and the singleton) coexist and fire in
/// registration order on every revision bump. Remove a specific listener with
/// `remove_on_change_listener`. Not phase-guarded (see `set_on_change`).
pub fn Runtime::add_on_change_listener(
  self : Runtime,
  f : () -> Unit,
) -> ListenerId {
  let id = self.alloc_listener_id()
  self.core.on_change_listeners.add(id, f)
  id
}

///|
/// Removes the additive on-change listener with `id`. Idempotent — an unknown or
/// already-removed id is a no-op.
pub fn Runtime::remove_on_change_listener(
  self : Runtime,
  id : ListenerId,
) -> Unit {
  self.core.on_change_listeners.remove(id) |> ignore
}

///|
/// Fires the on_change callback if one is registered.
fn Runtime::fire_on_change(self : Runtime) -> Unit {
  @kernel.fire_on_change(self.core)
}

///|
/// Core propagation coordinator: advances the revision, stamps changed_at on
/// all changed cells, and runs push propagation if any push cells exist.
fn Runtime::propagate_changes(
  self : Runtime,
  changed_ids : Array[CellId],
  durability : Durability,
) -> Unit {
  self.evaluation_strategies.propagate_changes(
    self.core,
    self.pull,
    self.push,
    self.datalog,
    changed_ids,
    durability,
    self.runtime_evaluation_event_sink(),
  )
}

///|
/// Kernel notification protocol: notifies the runtime that a set of cells
/// has new values.
fn Runtime::publish_cell_changes(
  self : Runtime,
  changed_ids : Array[CellId],
  durability : Durability,
) -> Unit {
  self.evaluation_strategies.publish_cell_changes(
    self.core,
    self.pull,
    self.push,
    self.datalog,
    changed_ids,
    durability,
    self.runtime_evaluation_event_sink(),
  )
}

///|
/// Advance the global revision counter and record which durability level changed.
impl RevisionManager for Runtime with fn advance_revision(self, durability) {
  @kernel.advance_revision(self.core, durability)
}

///|
/// Bumps the global revision counter and records which durability level changed.
impl RevisionManager for Runtime with fn bump_revision(self, durability) {
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
/// Pure-state guards (cross-runtime, already-disposed, phase/tracking, and
/// gc_root_counts cleanup) live in `@kernel`; the trait dispatch on
/// `self.cell_lifecycle` stays on Runtime because the CellLifecycle trait
/// is defined over Runtime (out of R1 scope to retype).
pub fn Runtime::dispose_cell(self : Runtime, cell_id : CellId) -> Unit {
  guard @kernel.validate_cell_for_dispose(self.core, cell_id) else { return }
  @kernel.check_dispose_guard(self.core, cell_id)
  @kernel.drop_gc_root(self.core, cell_id)
  self.cell_lifecycle[cell_id.id].dispose_cell(self, cell_id)
}

///|
/// Increments the observer reference count for a cell.
/// Returns the previous count (0 means this is the first observer).
fn Runtime::add_gc_root(self : Runtime, id : CellId) -> Int {
  @kernel.add_gc_root(self.core, id)
}

///|
/// Decrements the observer reference count for a cell.
/// Removes the entry when count reaches 0. Returns remaining count.
fn Runtime::remove_gc_root(self : Runtime, id : CellId) -> Int {
  @kernel.remove_gc_root(self.core, id)
}

///|
/// Runs mark-and-sweep garbage collection on the dependency graph.
///
/// Dispose dispatch is injected as a closure closing over
/// `self.dispose_cell`, so per-kind CellLifecycle dispatch remains
/// reachable from the kernel sweep loop.
pub fn Runtime::gc(self : Runtime) -> Unit {
  guard self.static_recompute_depth == 0 else {
    abort("gc: cannot run during static Derived recompute")
  }
  @kernel.gc(self.core, fn(id) { self.dispose_cell(id) })
  if self.has_pending_events() {
    self.drain_pending_events_if_idle()
  }
}
