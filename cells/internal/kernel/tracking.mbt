///|
/// Dependency tracking primitives: push/pop frames on the tracking stack,
/// record a dep from the top frame, collect path diagnostics.
///
/// Moved from cells/tracking.mbt + cells/introspection.mbt in R1 Stage 3d.
/// Runtime-side wrappers (begin_tracking/end_tracking/finish_tracking,
/// Tracker trait impls) stay in cells/tracking.mbt as thin delegators.

///|
/// Pushes a new dependency tracking frame for a memo computation.
pub fn push_tracking(core : RuntimeCore, cell_id : CellId) -> Unit {
  set_current_computing_runtime_id(core.runtime_id)
  core.tracking.stack.push(ActiveQuery::new(cell_id))
}

///|
/// Pops the tracking frame and returns (dependencies, seen).
pub fn pop_tracking(
  core : RuntimeCore,
) -> (Array[CellId], @hashset.HashSet[CellId]) {
  match core.tracking.stack.pop() {
    Some(query) => {
      if core.tracking.stack.length() == 0 {
        set_current_computing_runtime_id(-1)
      }
      (query.dependencies, query.seen)
    }
    None => abort("Tracking stack underflow")
  }
}

///|
/// Pops the tracking frame and returns the full ActiveQuery for callers
/// that need staged accumulator state (memo_force_recompute epilogue).
pub fn pop_tracking_full(core : RuntimeCore) -> ActiveQuery {
  match core.tracking.stack.pop() {
    Some(query) => {
      if core.tracking.stack.length() == 0 {
        set_current_computing_runtime_id(-1)
      }
      query
    }
    None => abort("pop_tracking_full: tracking stack is empty")
  }
}

///|
/// Records a dependency from the currently computing memo to `dep`.
/// No-op if no frame is active.
pub fn record_dep(core : RuntimeCore, dep : CellId) -> Unit {
  let len = core.tracking.stack.length()
  if len > 0 {
    core.tracking.stack[len - 1].record(dep)
  }
}

///|
/// Returns a reference to the top ActiveQuery frame, if any.
pub fn top_active_query(core : RuntimeCore) -> ActiveQuery? {
  let len = core.tracking.stack.length()
  if len == 0 {
    None
  } else {
    Some(core.tracking.stack[len - 1])
  }
}

///|
/// Collect cell IDs from the current tracking stack for cycle diagnostics.
pub fn collect_tracking_path(core : RuntimeCore) -> Array[CellId] {
  let path : Array[CellId] = []
  for frame in core.tracking.stack {
    path.push(frame.cell_id)
  }
  path
}

///|
/// Collect cell IDs for pull memos with `in_progress = true`.
/// Used by pull_verify for root-level cycle path reconstruction.
pub fn collect_in_progress_path(pull : PullState) -> Array[CellId] {
  let path : Array[CellId] = []
  for memo in pull.memos {
    if memo.in_progress {
      path.push(memo.meta.cell_id)
    }
  }
  path
}

///|
/// Guards a cell read against occurring inside a computation on a different
/// runtime. Aborts (after clearing global state) if the currently-computing
/// runtime is not the one that owns `cell_runtime_id`.
pub fn check_cross_runtime(cell_runtime_id : Int, kind : String) -> Unit {
  let active_rt = get_current_computing_runtime_id()
  if active_rt >= 0 && active_rt != cell_runtime_id {
    set_current_computing_runtime_id(-1)
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
