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
  // cell_lifecycle is lifted out of RuntimeCore: the CellLifecycle trait
  // takes `Runtime` as a parameter (see cells/cell_ops.mbt), so moving it
  // into kernel would create a circular type reference.
  priv cell_lifecycle : Array[&CellLifecycle]
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

  fn new(on_change? : () -> Unit) -> Runtime
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
    cell_lifecycle: [],
    accumulator_slots: [],
    accumulator_snapshots: [],
    next_accumulator_id: 0,
    accumulator_contributions: @hashmap.new(),
  }
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
/// Registers a callback that fires whenever a revision bump occurs.
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
  @kernel.propagate_changes(
    self.core,
    self.pull,
    self.push,
    self.datalog,
    changed_ids,
    durability,
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
  @kernel.publish_cell_changes(
    self.core,
    self.pull,
    self.push,
    self.datalog,
    changed_ids,
    durability,
  )
}

///|
/// Advance the global revision counter and record which durability level changed.
impl RevisionManager for Runtime with advance_revision(self, durability) {
  @kernel.advance_revision(self.core, durability)
}

///|
/// Bumps the global revision counter and records which durability level changed.
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
/// Runs mark-and-sweep garbage collection on the dependency graph.
pub fn Runtime::gc(self : Runtime) -> Unit {
  guard self.core.tracking.stack.is_empty() else {
    // Clean up global state before aborting so panic tests don't
    // contaminate subsequent tests via current_computing_runtime_id.
    self.core.tracking.stack.clear()
    @kernel.set_current_computing_runtime_id(-1)
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
      roots.push(@kernel.cell_id_at(self.core, i))
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
      let id = @kernel.cell_id_at(self.core, i)
      if !reachable.contains(id) {
        self.dispose_cell(id)
      }
    }
  }
}
