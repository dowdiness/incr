///|
using @incr_types {
  type AccumulatorId,
  type CellId,
  type Durability,
  type Revision,
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
/// Tracks the runtime_id currently executing a memo computation.
/// -1 means no computation is active (sentinel; runtime IDs start at 0).
///
/// Single-threaded assumption: MoonBit currently targets WebAssembly
/// (inherently single-threaded) and a single-threaded native runtime, so a
/// plain `Ref[Int]` is safe here. If parallel execution is ever introduced
/// (e.g. native threads or shared-memory WASM), this sentinel must be
/// replaced with a thread-local or an atomic.
let current_computing_runtime_id : Ref[Int] = { val: -1 }

///|
/// Allocates a fresh runtime id and advances the global counter.
pub fn alloc_runtime_id() -> Int {
  let id = next_runtime_id.val
  next_runtime_id.val = id + 1
  id
}

///|
/// Returns the runtime_id of the Runtime currently executing a tracked
/// computation, or -1 if none.
pub fn get_current_computing_runtime_id() -> Int {
  current_computing_runtime_id.val
}

///|
/// Sets the runtime_id of the Runtime currently executing a tracked
/// computation. Pass -1 to clear.
pub fn set_current_computing_runtime_id(v : Int) -> Unit {
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
pub impl Show for PropagationPhase with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// A dependency recording frame pushed onto the runtime's tracking stack
/// when a memo is being computed.
pub(all) struct ActiveQuery {
  cell_id : CellId
  dependencies : Array[CellId]
  seen : @hashset.HashSet[CellId]
  // Synthetic accumulator reads staged during compute. On success, copied
  // to MemoData.accumulator_reads in the AFTER_CLOSURE phase. On abort,
  // discarded (transactional discipline matches ordinary-dep commit).
  accumulator_reads : @hashmap.HashMap[(AccumulatorId, CellId), Revision]
  // Accumulator slots this frame pushed to. Used in AFTER_CLOSURE to
  // iterate the set of slots needing a finalize_memo call, and in ON_ABORT
  // to identify new-run-only slots for cleanup.
  touched_accumulator_slots : @hashset.HashSet[AccumulatorId]

  fn new(cell_id : CellId) -> ActiveQuery
}

///|
/// Creates a new active query with an empty dependency set.
pub fn ActiveQuery::new(cell_id : CellId) -> ActiveQuery {
  {
    cell_id,
    dependencies: [],
    seen: @hashset.new(),
    accumulator_reads: @hashmap.new(),
    touched_accumulator_slots: @hashset.new(),
  }
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

  fn new() -> BatchFrame
}

///|
pub fn BatchFrame::new() -> BatchFrame {
  { undo_entries: [], undo_ids: @hashset.new() }
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
  signals : Array[@pull.PullSignalData]
  memos : Array[@pull.MemoData]
  free_signals : Array[Int]
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
  runtime_id : Int
  revision : RevisionState
  mut next_cell_id : Int
  tracking : TrackingState
  batch : BatchState
  mut on_change : (() -> Unit)?
  cell_index : Array[CellRef]
  cell_ops : Array[&CellOps]
  mut phase : PropagationPhase
  /// Reference counts for observed cells. Key = observed CellId,
  /// value = number of live Observer handles. on_unobserve fires only
  /// when count reaches 0.
  gc_root_counts : @hashmap.HashMap[CellId, Int]
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
