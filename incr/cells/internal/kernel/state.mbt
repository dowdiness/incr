///|
using @incr_types {
  type CellId,
  type Durability,
  type Revision,
  type RuntimeId,
  type ListenerId,
}

///|
using @shared {type CellRef, trait CellOps, trait Committable}

///|
/// Global counter for assigning unique IDs to Runtime instances.
///
/// Each Runtime gets a unique ID to prevent CellIds from different
/// runtimes being incorrectly queried against each other.
let next_runtime_id : Ref[Int] = { val: 0 }

///|
/// Tracks the runtime currently executing a memo computation.
/// `None` means no computation is active.
///
/// Single-threaded assumption: MoonBit currently targets WebAssembly
/// (inherently single-threaded) and a single-threaded native runtime, so a
/// plain `Ref` is safe here. If parallel execution is ever introduced
/// (e.g. native threads or shared-memory WASM), this must be replaced with a
/// thread-local or an atomic.
let current_computing_runtime_id : Ref[RuntimeId?] = { val: None }

///|
/// Allocates a fresh runtime id and advances the global counter.
pub fn alloc_runtime_id() -> RuntimeId {
  let id = next_runtime_id.val
  next_runtime_id.val = id + 1
  RuntimeId(id)
}

///|
/// Allocates a fresh listener id from the runtime's monotonic counter. Shared
/// by both the on-change and derived-event registries, so ids are unique
/// per-runtime across the two hook surfaces.
pub fn alloc_listener_id(core : RuntimeCore) -> ListenerId {
  let id = core.next_listener_id
  core.next_listener_id = id + 1
  ListenerId(core.runtime_id, id)
}

///|
/// Returns the runtime currently executing a tracked computation, or `None`
/// if none.
pub fn get_current_computing_runtime_id() -> RuntimeId? {
  current_computing_runtime_id.val
}

///|
/// Sets the runtime currently executing a tracked computation. Pass `None` to
/// clear.
pub fn set_current_computing_runtime_id(v : RuntimeId?) -> Unit {
  current_computing_runtime_id.val = v
}

///|
/// Mutually exclusive runtime phases for cross-engine guards.
///
/// These phases are never active simultaneously. `batch.depth` is
/// orthogonal — batches compose with any propagation phase (e.g.
/// commit_batch temporarily raises batch.depth during callbacks
/// while the propagation phase is Idle).
pub(all) enum PropagationPhase {
  Idle
  PushPropagating
  InFixpoint
  GarbageCollecting
} derive(Eq, Debug)

///|
pub impl Show for PropagationPhase with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// A dependency recording frame pushed onto the runtime's tracking stack
/// when a memo is being computed. Owns the per-recompute dependency set
/// only; commit-phase hooks own any state they need keyed by `cell_id`.
pub(all) struct ActiveQuery {
  cell_id : CellId
  dependencies : Array[CellId]
  seen : @hashset.HashSet[CellId]
}

///|
/// Constructor-syntax alias of `ActiveQuery::new`.
pub fn ActiveQuery::ActiveQuery(cell_id : CellId) -> ActiveQuery {
  ActiveQuery::new(cell_id)
}

///|
/// Creates a new active query with an empty dependency set.
pub fn ActiveQuery::new(cell_id : CellId) -> ActiveQuery {
  { cell_id, dependencies: [], seen: @hashset.HashSet([]) }
}

///|
/// Records that the currently computing memo depends on the given cell.
pub fn ActiveQuery::record(self : ActiveQuery, dep : CellId) -> Unit {
  if self.seen.contains(dep) {
    return
  }
  self.seen.add(dep)
  self.dependencies.push(dep)
}

///|
/// Undo entry for one signal touched by a batch frame.
pub(all) struct BatchUndo {
  cell_id : CellId
  rollback : () -> Unit
}

///|
/// Per-batch-frame rollback log for nested batch semantics.
pub(all) struct BatchFrame {
  undo_entries : Array[BatchUndo]
  undo_ids : @hashset.HashSet[CellId]
}

///|
/// Constructor-syntax alias of `BatchFrame::new`.
pub fn BatchFrame::BatchFrame() -> BatchFrame {
  BatchFrame::new()
}

///|
pub fn BatchFrame::new() -> BatchFrame {
  { undo_entries: [], undo_ids: @hashset.HashSet([]) }
}

///|
pub fn BatchFrame::has_undo_for(self : BatchFrame, cell_id : CellId) -> Bool {
  self.undo_ids.contains(cell_id)
}

///|
/// Batch update management: deferred signal writes and rollback.
pub(all) struct BatchState {
  mut depth : Int
  pending : Array[&Committable]
  frames : Array[BatchFrame]
  mut max_durability : Durability
}

///|
/// Dependency tracking: recording which cells are read during computation.
pub(all) struct TrackingState {
  stack : Array[ActiveQuery]
}

///|
/// Revision tracking: global clock and per-durability change timestamps.
pub(all) struct RevisionState {
  mut current_revision : Revision
  durability_last_changed : FixedArray[Revision]
}

///|
/// Pull-mode SoA storage (lazy verification).
pub(all) struct PullState {
  inputs : Array[@pull.PullInputData]
  memos : Array[@pull.MemoData]
  free_inputs : Array[Int]
  free_memos : Array[Int]
}

///|
/// Push-mode SoA storage (eager propagation).
pub(all) struct PushState {
  reactives : Array[@push.PushReactiveData]
  effects : Array[@push.PushEffectData]
  free_reactives : Array[Int]
  free_effects : Array[Int]
  /// Count of live push cells (reactives + effects only).
  /// HybridMemo does NOT contribute to this count — it relies on
  /// verified_at staleness detection rather than push propagation.
  mut node_count : Int
}

///|
/// Datalog SoA storage (fixpoint evaluation).
pub(all) struct DatalogState {
  relations : Array[@datalog.RelationData]
  functional_relations : Array[@datalog.FunctionalRelationData]
  rules : Array[@datalog.RuleData]
}

///|
/// Core runtime state: identity, revision tracking, batch management,
/// unified dispatch tables, and cross-engine guards.
///
/// NOTE: `cell_lifecycle` intentionally lives on Runtime (cells/runtime.mbt),
/// not here. The CellLifecycle trait references Runtime directly (dispose
/// semantics) which would create a cycle if moved into kernel.
pub(all) struct RuntimeCore {
  runtime_id : RuntimeId
  revision : RevisionState
  mut next_cell_id : Int
  tracking : TrackingState
  batch : BatchState
  mut callback_depth : Int
  /// Composable runtime-global on-change listeners. The `set_on_change`
  /// singleton API maps onto the registry's reserved slot; `add_on_change_listener`
  /// appends additive listeners. Fired (as a snapshot) by `fire_on_change`.
  on_change_listeners : ListenerRegistry[() -> Unit]
  /// Monotonic counter for `ListenerId` allocation, shared across both the
  /// on-change and derived-event registries so every listener id is unique
  /// within this runtime.
  mut next_listener_id : Int
  cell_index : Array[CellRef]
  cell_ops : Array[&CellOps]
  mut phase : PropagationPhase
  /// Reference counts for observed cells. Key = observed CellId,
  /// value = number of live Observer handles. on_unobserve fires only
  /// when count reaches 0.
  gc_root_counts : @hashmap.HashMap[CellId, Int]
}

///|
/// Builds an empty `RuntimeCore` with a freshly allocated runtime id.
///
/// This is the single source of truth for core-state initialization: both the
/// `Runtime::Runtime` coordinator constructor in `cells/` and kernel whitebox
/// tests call `RuntimeCore()`, so no call site duplicates the initialization literal and a
/// new `RuntimeCore` field can never silently drift between them.
pub fn RuntimeCore::RuntimeCore() -> RuntimeCore {
  {
    runtime_id: alloc_runtime_id(),
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
    on_change_listeners: ListenerRegistry::new(),
    next_listener_id: 0,
    cell_index: [],
    cell_ops: [],
    phase: Idle,
    gc_root_counts: @hashmap.HashMap([]),
  }
}

///|
/// Transitions to a new propagation phase.
///
/// Aborts if the current phase is not `Idle` — phases are mutually
/// exclusive, so every active phase must be wound back to `Idle` before
/// a new one is entered. To return to `Idle` from any active phase use
/// `leave_phase` (the finally-style unwind path), not this function.
pub fn enter_phase(core : RuntimeCore, next : PropagationPhase) -> Unit {
  guard core.phase is Idle else {
    abort(
      "enter_phase: cannot enter " +
      next.to_string() +
      " while in " +
      core.phase.to_string(),
    )
  }
  core.phase = next
}

///|
/// Returns to the Idle phase. Unconditional — always succeeds.
pub fn leave_phase(core : RuntimeCore) -> Unit {
  core.phase = Idle
}
