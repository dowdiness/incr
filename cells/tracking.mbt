///|
/// A dependency recording frame pushed onto the runtime's tracking stack
/// when a memo is being computed.
///
/// During a memo's compute function, every `Signal::get()` or `Memo::get()`
/// call records a dependency in the active query. When the computation
/// finishes, the collected dependencies are stored on the memo's cell metadata.
///
/// Dependencies are deduplicated using a HashSet for O(1) membership checks.
priv struct ActiveQuery {
  cell_id : CellId
  dependencies : Array[CellId]
  seen : @hashset.HashSet[CellId]
  // Synthetic accumulator reads staged during compute. On success, copied
  // to MemoData.accumulator_reads in the AFTER_CLOSURE phase. On abort,
  // discarded (transactional discipline matches ordinary-dep commit).
  accumulator_reads : @hashmap.HashMap[
    (@incr_types.AccumulatorId, CellId),
    @incr_types.Revision,
  ]
  // Accumulator slots this frame pushed to. Used in AFTER_CLOSURE to
  // iterate the set of slots needing a finalize_memo call, and in ON_ABORT
  // to identify new-run-only slots for cleanup.
  touched_accumulator_slots : @hashset.HashSet[@incr_types.AccumulatorId]

  fn new(cell_id : CellId) -> ActiveQuery
}

///|
/// Creates a new active query.
///
/// # Parameters
///
/// - `cell_id`: The cell ID of the memo being computed
///
/// # Returns
///
/// A new active query with an empty dependency set
fn ActiveQuery::new(cell_id : CellId) -> ActiveQuery {
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
///
/// If the cell has already been recorded as a dependency, this is a no-op
/// (deduplication via HashSet). This ensures the dependency list is minimal
/// and order-preserving.
///
/// # Parameters
///
/// - `dep`: The cell ID to record as a dependency
fn ActiveQuery::record(self : ActiveQuery, dep : CellId) -> Unit {
  if self.seen.contains(dep) {
    return
  }
  self.seen.add(dep)
  self.dependencies.push(dep)
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
impl Tracker for Runtime with record_dependency(self, dep) {
  let len = self.core.tracking.stack.length()
  if len > 0 {
    self.core.tracking.stack[len - 1].record(dep)
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
impl Tracker for Runtime with push_tracking(self, cell_id) {
  current_computing_runtime_id.val = self.core.runtime_id
  self.core.tracking.stack.push(ActiveQuery(cell_id))
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
impl Tracker for Runtime with pop_tracking(self) {
  match self.core.tracking.stack.pop() {
    Some(query) => {
      if self.core.tracking.stack.length() == 0 {
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
/// Pops the tracking frame and returns the collected dependencies and seen set.
///
/// Used by Phase 3+ cell types that call `finish_tracking` to update
/// subscriber links. Returns both deps and seen so `finish_tracking` can
/// forward the pre-built seen set to `diff_and_update_subscribers`.
///
/// # Panics
///
/// Aborts if the tracking stack is empty.
fn Runtime::end_tracking(
  self : Runtime,
) -> (Array[CellId], @hashset.HashSet[CellId]) {
  self.pop_tracking()
}

///|
/// Updates subscriber links after a cell recomputes with a new dependency set.
///
/// Diffs `old_deps` against `new_deps` using the pre-built `new_seen` set
/// from `end_tracking` to avoid rebuilding it.
fn Runtime::finish_tracking(
  self : Runtime,
  cell_id : CellId,
  old_deps : Array[CellId],
  new_deps : Array[CellId],
  new_seen : @hashset.HashSet[CellId],
) -> Unit {
  self.diff_and_update_subscribers(cell_id, old_deps, new_deps, new_seen~)
  |> ignore
}

///|
/// Guards a cell read from occurring inside a computation on a different
/// runtime. Centralizes the cross-runtime check that was previously
/// duplicated across Signal, Memo (outer), HybridMemo, Reactive, Relation,
/// and FunctionalRelation read paths.
///
/// Resets `current_computing_runtime_id` before aborting so a caught
/// panic does not leak dirty global state to subsequent reads.
///
/// Does NOT attempt stale-state repair — distinguishing "stale from prior
/// abort" from "legitimate cross-runtime" requires the active runtime's
/// stack length, which is not accessible here without a global runtime
/// registry. Same-runtime stale repair is handled separately in
/// `Memo::get_result_inner` for paths that bypass the outer guard.
fn Runtime::check_cross_runtime(
  _self : Runtime,
  cell_runtime_id : Int,
  kind : String,
) -> Unit {
  let active_rt = current_computing_runtime_id.val
  if active_rt >= 0 && active_rt != cell_runtime_id {
    current_computing_runtime_id.val = -1
    abort(
      "Cross-runtime dependency: " +
      kind +
      " belongs to Runtime " +
      cell_runtime_id.to_string() +
      " but is read inside a computation on Runtime " +
      active_rt.to_string(),
    )
  }
}

///|
/// Internal: returns a reference to the top ActiveQuery frame, if any.
/// Used by Accumulator::push to stage touched_accumulator_slots entries
/// and by memo_force_recompute to inspect touched slots on abort.
fn Runtime::top_active_query(self : Runtime) -> ActiveQuery? {
  let len = self.core.tracking.stack.length()
  if len == 0 {
    None
  } else {
    Some(self.core.tracking.stack[len - 1])
  }
}

///|
/// Collect cell IDs from the current tracking stack.
///
/// Returns the cell IDs of all active computation frames in order,
/// for use in cycle error diagnostics. Does not modify the stack.
fn Runtime::collect_tracking_path(self : Runtime) -> Array[CellId] {
  let path : Array[CellId] = []
  for frame in self.core.tracking.stack {
    path.push(frame.cell_id)
  }
  path
}
