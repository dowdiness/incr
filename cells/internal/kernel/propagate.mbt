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
/// Fires the on_change callback if one is registered.
pub fn fire_on_change(core : RuntimeCore) -> Unit {
  match core.on_change {
    Some(f) => f()
    None => ()
  }
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
  advance_revision(core, durability)
  for id in changed_ids {
    core.cell_ops[id.id].set_changed_at(core.revision.current_revision)
  }
  if push.node_count > 0 {
    push_propagate_from(core, pull, push, datalog, changed_ids)
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
  propagate_changes(core, pull, push, datalog, changed_ids, durability)
  fire_on_change(core)
}
