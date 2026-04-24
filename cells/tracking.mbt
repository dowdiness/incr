///|
/// Records a dependency from the currently computing memo to the given cell.
///
/// Called internally by `Signal::get` and `Memo::get` when inside a memo's
/// compute function. If no memo is currently computing (tracking stack is
/// empty), this is a no-op.
impl Tracker for Runtime with record_dependency(self, dep) {
  @kernel.record_dep(self.core, dep)
}

///|
/// Pushes a new dependency tracking frame for a memo computation.
///
/// Called internally at the start of a memo's recomputation. All subsequent
/// `get()` calls will be recorded as dependencies until `pop_tracking` is
/// called.
impl Tracker for Runtime with push_tracking(self, cell_id) {
  @kernel.push_tracking(self.core, cell_id)
}

///|
/// Pops the tracking frame and returns the collected dependencies.
impl Tracker for Runtime with pop_tracking(self) {
  @kernel.pop_tracking(self.core)
}

///|
/// Pushes a fresh tracking frame for the given cell (Phase 2 API).
fn Runtime::begin_tracking(self : Runtime, cell_id : CellId) -> Unit {
  @kernel.push_tracking(self.core, cell_id)
}

///|
/// Pops the tracking frame and returns the collected dependencies and seen set.
fn Runtime::end_tracking(
  self : Runtime,
) -> (Array[CellId], @hashset.HashSet[CellId]) {
  @kernel.pop_tracking(self.core)
}

///|
/// Updates subscriber links after a cell recomputes with a new dependency set.
fn Runtime::finish_tracking(
  self : Runtime,
  cell_id : CellId,
  old_deps : Array[CellId],
  new_deps : Array[CellId],
  new_seen : @hashset.HashSet[CellId],
) -> Unit {
  @kernel.diff_and_update_subscribers(
    self.core,
    self.pull,
    self.push,
    self.datalog,
    cell_id,
    old_deps,
    new_deps,
    new_seen~,
  )
  |> ignore
}

///|
/// Guards a cell read from occurring inside a computation on a different
/// runtime. Centralizes the cross-runtime check that was previously
/// duplicated across Signal, Memo (outer), HybridMemo, Reactive, Relation,
/// and FunctionalRelation read paths.
fn Runtime::check_cross_runtime(
  _self : Runtime,
  cell_runtime_id : Int,
  kind : String,
) -> Unit {
  @kernel.check_cross_runtime(cell_runtime_id, kind)
}

///|
/// Internal: returns a reference to the top ActiveQuery frame, if any.
fn Runtime::top_active_query(self : Runtime) -> ActiveQuery? {
  @kernel.top_active_query(self.core)
}

///|
/// Internal: pops the tracking frame and returns the full ActiveQuery for
/// callers that need staged accumulator state.
fn Runtime::pop_tracking_full(self : Runtime) -> ActiveQuery {
  @kernel.pop_tracking_full(self.core)
}

///|
/// Collect cell IDs from the current tracking stack for cycle diagnostics.
fn Runtime::collect_tracking_path(self : Runtime) -> Array[CellId] {
  @kernel.collect_tracking_path(self.core)
}
