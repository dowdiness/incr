///|
/// Records a dependency from the currently computing memo to the given cell.
///
/// Called internally by `Signal::get` and `Memo::get` when inside a memo's
/// compute function. If no memo is currently computing (tracking stack is
/// empty), this is a no-op.
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
impl Tracker for Runtime with push_tracking(self, cell_id) {
  @kernel.set_current_computing_runtime_id(self.core.runtime_id)
  self.core.tracking.stack.push(ActiveQuery::new(cell_id))
}

///|
/// Pops the tracking frame and returns the collected dependencies.
impl Tracker for Runtime with pop_tracking(self) {
  match self.core.tracking.stack.pop() {
    Some(query) => {
      if self.core.tracking.stack.length() == 0 {
        @kernel.set_current_computing_runtime_id(-1)
      }
      (query.dependencies, query.seen)
    }
    None => abort("Tracking stack underflow")
  }
}

///|
/// Pushes a fresh tracking frame for the given cell (Phase 2 API).
fn Runtime::begin_tracking(self : Runtime, cell_id : CellId) -> Unit {
  self.push_tracking(cell_id)
}

///|
/// Pops the tracking frame and returns the collected dependencies and seen set.
fn Runtime::end_tracking(
  self : Runtime,
) -> (Array[CellId], @hashset.HashSet[CellId]) {
  self.pop_tracking()
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
  self.diff_and_update_subscribers(cell_id, old_deps, new_deps, new_seen~)
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
  let active_rt = @kernel.get_current_computing_runtime_id()
  if active_rt >= 0 && active_rt != cell_runtime_id {
    @kernel.set_current_computing_runtime_id(-1)
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
fn Runtime::top_active_query(self : Runtime) -> ActiveQuery? {
  let len = self.core.tracking.stack.length()
  if len == 0 {
    None
  } else {
    Some(self.core.tracking.stack[len - 1])
  }
}

///|
/// Internal: pops the tracking frame and returns the full ActiveQuery for
/// callers that need staged accumulator state.
fn Runtime::pop_tracking_full(self : Runtime) -> ActiveQuery {
  match self.core.tracking.stack.pop() {
    Some(query) => {
      if self.core.tracking.stack.length() == 0 {
        @kernel.set_current_computing_runtime_id(-1)
      }
      query
    }
    None => abort("pop_tracking_full: tracking stack is empty")
  }
}

///|
/// Collect cell IDs from the current tracking stack for cycle diagnostics.
fn Runtime::collect_tracking_path(self : Runtime) -> Array[CellId] {
  let path : Array[CellId] = []
  for frame in self.core.tracking.stack {
    path.push(frame.cell_id)
  }
  path
}
