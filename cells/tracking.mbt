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
  { cell_id, dependencies: [], seen: @hashset.new() }
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
