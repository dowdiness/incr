///|
/// Propagation coordinator primitives: revision advancement, on_change
/// notification, and the propagate/publish pipeline.
///
/// All functions take kernel state references explicitly. Runtime retains
/// thin wrappers for public/high-fan-out call-sites (per D8).

///|
/// Advance the global revision counter and record which durability level changed.
pub fn advance_revision(core : RuntimeCore, durability : Durability) -> Unit {
  core.revision.current_revision = Revision::next(
    core.revision.current_revision,
  )
  let dur_idx = durability.index()
  for i = 0; i <= dur_idx; i = i + 1 {
    core.revision.durability_last_changed[i] = core.revision.current_revision
  }
}

///|
/// Runs a user callback while marking listener drains as deferred.
pub fn run_callback(core : RuntimeCore, f : () -> Unit raise?) -> Unit raise? {
  core.callback_depth = core.callback_depth + 1
  f() catch {
    e => {
      core.callback_depth = core.callback_depth - 1
      raise e
    }
  }
  core.callback_depth = core.callback_depth - 1
}

///|
/// Fires all registered on-change listeners, in registration order.
///
/// The listener list is snapshotted before firing so that a listener which
/// adds or removes on-change listeners affects only the *next* fire, never the
/// in-flight dispatch (the snapshot-before-fire invariant, extended from one
/// handler to N). All listeners run under a single `run_callback` so the
/// callback-depth guard behaves exactly as it did for the singleton handler.
pub fn fire_on_change(core : RuntimeCore) -> Unit {
  if core.on_change_listeners.is_empty() {
    return
  }
  let listeners = core.on_change_listeners.snapshot()
  run_callback(core, fn() {
    for f in listeners {
      f()
    }
  })
}

///|
/// Core propagation coordinator: advances the revision, stamps changed_at on
/// all changed cells, and runs push propagation if any push cells exist.
pub fn propagate_changes(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_ids : Array[CellId],
  durability : Durability,
) -> Unit {
  propagate_changes_with_events(
    core,
    pull,
    push,
    datalog,
    changed_ids,
    durability,
    None,
  )
}

///|
pub fn propagate_changes_with_events(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_ids : Array[CellId],
  durability : Durability,
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
) -> Unit {
  advance_revision(core, durability)
  for id in changed_ids {
    core.cell_ops[id.id].set_changed_at(core.revision.current_revision)
  }
  if push.node_count > 0 {
    push_propagate_from_with_events(
      core, pull, push, datalog, changed_ids, event_sink,
    )
  }
}

///|
/// Kernel notification protocol: notifies the runtime that a set of cells
/// has new values.
pub fn publish_cell_changes(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_ids : Array[CellId],
  durability : Durability,
) -> Unit {
  publish_cell_changes_with_events(
    core,
    pull,
    push,
    datalog,
    changed_ids,
    durability,
    None,
  )
}

///|
pub fn publish_cell_changes_with_events(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_ids : Array[CellId],
  durability : Durability,
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
) -> Unit {
  propagate_changes_with_events(
    core, pull, push, datalog, changed_ids, durability, event_sink,
  )
  fire_on_change(core)
}
