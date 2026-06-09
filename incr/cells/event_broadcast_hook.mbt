///|
/// Per-cell event state captured between recompute entry and completion.
priv struct RecomputeStart {
  timer : @bench.Timestamp
  started_revision : Revision
}

///|
/// MemoCommitPhase implementor that buffers recompute events for later drain.
priv struct EventBroadcastPhaseHook {
  listeners : @kernel.ListenerRegistry[(DerivedEvent) -> Unit]
  mut draining : Bool
  active : @hashmap.HashMap[CellId, RecomputeStart]
  mut pending : Array[DerivedEvent]
}

///|
fn EventBroadcastPhaseHook::new() -> EventBroadcastPhaseHook {
  {
    listeners: @kernel.ListenerRegistry::new(),
    draining: false,
    active: @hashmap.HashMap([]),
    pending: [],
  }
}

///|
fn capture_now() -> @bench.Timestamp {
  @bench.monotonic_clock_start()
}

///|
fn elapsed_ns_from(ts : @bench.Timestamp) -> Int64 {
  (@bench.monotonic_clock_end(ts) * 1000.0).to_int64()
}

///|
impl MemoCommitPhase for EventBroadcastPhaseHook with fn before_recompute(
  self,
  rt,
  cell_id,
) {
  guard !self.listeners.is_empty() else { return }
  let start : RecomputeStart = {
    timer: capture_now(),
    started_revision: rt.core.revision.current_revision,
  }
  self.active.set(cell_id, start)
  self.pending.push(
    EnteringCompute({ cell_id, started_revision: start.started_revision }),
  )
}

///|
impl MemoCommitPhase for EventBroadcastPhaseHook with fn after_success(
  self,
  rt,
  cell_id,
) {
  guard !self.listeners.is_empty() else { return }
  let start = match self.active.get(cell_id) {
    Some(s) => s
    None => return
  }
  self.active.remove(cell_id)
  let elapsed_ns = elapsed_ns_from(start.timer)
  let cell = rt.get_memo_data(cell_id)
  let changed_at = cell.meta.changed_at
  let verified_at = cell.verified_at
  self.pending.push(
    Completed({
      cell_id,
      elapsed_ns,
      started_revision: start.started_revision,
      verified_at,
      changed_at,
      backdated: changed_at.value < verified_at.value,
    }),
  )
}

///|
impl MemoCommitPhase for EventBroadcastPhaseHook with fn after_abort(
  self,
  _rt,
  cell_id,
  error,
) {
  guard !self.listeners.is_empty() else { return }
  let start = match self.active.get(cell_id) {
    Some(s) => s
    None => return
  }
  self.active.remove(cell_id)
  let elapsed_ns = elapsed_ns_from(start.timer)
  self.pending.push(
    Aborted({
      cell_id,
      elapsed_ns,
      started_revision: start.started_revision,
      error,
    }),
  )
}

///|
/// Drains buffered derived events, including events queued by reentrant
/// callbacks, to every registered listener.
///
/// Delivery is **event-major**: for each buffered event (in pull-verification
/// traversal order), every listener fires in registration order before the next
/// event. The listener set is snapshotted once at drain entry; listener mutation
/// is forbidden while draining (the `draining` conjunct of
/// `is_listener_mutation_safe`), so the snapshot stays valid across reentrant
/// waves.
fn EventBroadcastPhaseHook::drain(self : EventBroadcastPhaseHook) -> Unit {
  if self.pending.is_empty() {
    return
  }
  if self.draining {
    return
  }
  if self.listeners.is_empty() {
    self.pending.clear()
    return
  }
  let listeners = self.listeners.snapshot()
  self.draining = true
  while !self.pending.is_empty() {
    let events = self.pending
    self.pending = []
    for evt in events {
      for f in listeners {
        f(evt)
      }
    }
  }
  self.draining = false
}
