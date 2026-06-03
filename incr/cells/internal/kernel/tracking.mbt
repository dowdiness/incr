///|
/// Dependency tracking primitives: push/pop frames on the tracking stack,
/// record a dep from the top frame, collect path diagnostics.
/// Runtime-side wrappers live in cells/tracking.mbt as thin delegators.

///|
/// Pushes a new dependency tracking frame for a memo computation.
pub fn push_tracking(core : RuntimeCore, cell_id : CellId) -> Unit {
  set_current_computing_runtime_id(Some(core.runtime_id))
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
        set_current_computing_runtime_id(None)
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
        set_current_computing_runtime_id(None)
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
/// Shared comparison/message core for the cross-runtime guards. Clears the
/// global sentinel, then aborts: a cell owned by `cell_runtime_id` was read
/// inside an active computation on `active_rt`.
pub fn abort_cross_runtime(
  kind : String,
  cell_runtime_id : RuntimeId,
  active_rt : RuntimeId,
) -> Unit {
  set_current_computing_runtime_id(None)
  abort(
    "Cross-runtime dependency: " +
    kind +
    " belongs to Runtime " +
    cell_runtime_id.to_string() +
    " but is read inside a computation on Runtime " +
    active_rt.to_string(),
  )
}

///|
/// Strict, stack-agnostic cross-runtime guard. Aborts if the
/// currently-computing runtime is not the one that owns `cell_runtime_id`.
/// Used by the `read_honest` / `.get()` read paths as a pre-check.
pub fn check_cross_runtime_strict(
  cell_runtime_id : RuntimeId,
  kind : String,
) -> Unit {
  guard get_current_computing_runtime_id() is Some(active_rt) else { return }
  if active_rt != cell_runtime_id {
    abort_cross_runtime(kind, cell_runtime_id, active_rt)
  }
}

///|
/// Repair (cleanup-only) variant for the *direct* read paths
/// (`read_permissive`, `MemoMap::read_honest` / `DerivedMap::read`) that bypass
/// the strict pre-check. A *foreign* active sentinel always aborts — exactly
/// like the strict guard — regardless of this runtime's tracking stack. Only a
/// stale *own-runtime* sentinel (sentinel is this runtime, but its tracking
/// stack is empty, so no computation is actually live) is cleared and the read
/// allowed to proceed. This `Some(self)`-only repair is a backstop for sentinels
/// left by aborted or static-derived computations — never a cross-runtime read
/// policy.
pub fn repair_stale_runtime_sentinel_for_untracked_read(
  core : RuntimeCore,
  kind : String,
) -> Unit {
  guard get_current_computing_runtime_id() is Some(active_rt) else { return }
  if active_rt != core.runtime_id {
    abort_cross_runtime(kind, core.runtime_id, active_rt)
  } else if core.tracking.stack.is_empty() {
    set_current_computing_runtime_id(None)
  }
}
