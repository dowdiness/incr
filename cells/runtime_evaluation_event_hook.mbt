///|
priv struct DerivedRebuildStart {
  dependency_count_before : Int
  changed_at_before : Revision
  verified_at_before : Revision
  had_been_computed_before : Bool
}

///|
priv struct RuntimeEvaluationEventHook {
  mut listener : ((@kernel.RuntimeEvaluationEvent) -> Unit)?
  mut draining : Bool
  active : @hashmap.HashMap[CellId, DerivedRebuildStart]
  mut pending : Array[@kernel.RuntimeEvaluationEvent]
}

///|
fn RuntimeEvaluationEventHook::new() -> RuntimeEvaluationEventHook {
  { listener: None, draining: false, active: @hashmap.HashMap([]), pending: [] }
}

///|
fn RuntimeEvaluationEventHook::enabled(
  self : RuntimeEvaluationEventHook,
) -> Bool {
  match self.listener {
    Some(_) => true
    None => false
  }
}

///|
fn RuntimeEvaluationEventHook::push_event(
  self : RuntimeEvaluationEventHook,
  event : @kernel.RuntimeEvaluationEvent,
) -> Unit {
  guard self.enabled() else { return }
  self.pending.push(event)
}

///|
impl MemoCommitPhase for RuntimeEvaluationEventHook with fn before_recompute(
  self,
  rt,
  cell_id,
) {
  guard self.enabled() else { return }
  let cell = rt.get_memo_data(cell_id)
  self.active.set(cell_id, {
    dependency_count_before: cell.dependencies.length(),
    changed_at_before: cell.meta.changed_at,
    verified_at_before: cell.verified_at,
    had_been_computed_before: cell.has_been_computed,
  })
}

///|
impl MemoCommitPhase for RuntimeEvaluationEventHook with fn after_success(
  self,
  rt,
  cell_id,
) {
  let start = match self.active.get(cell_id) {
    Some(s) => s
    None => return
  }
  self.active.remove(cell_id)
  guard self.enabled() else { return }
  let cell = rt.get_memo_data(cell_id)
  let changed_at_after = cell.meta.changed_at
  let disposition = if !start.had_been_computed_before ||
    changed_at_after != start.changed_at_before {
    @kernel.DerivedRebuildDisposition::RecomputedChanged
  } else {
    @kernel.DerivedRebuildDisposition::RecomputedBackdated
  }
  self.pending.push(
    DerivedRebuilt({
      cell_id,
      disposition,
      dependency_count_before: start.dependency_count_before,
      dependency_count_after: cell.dependencies.length(),
      changed_at_before: start.changed_at_before,
      changed_at_after,
      verified_at: cell.verified_at,
      had_synthetic_accumulator_reads: !cell.accumulator_reads.is_empty(),
    }),
  )
}

///|
impl MemoCommitPhase for RuntimeEvaluationEventHook with fn after_abort(
  self,
  _rt,
  cell_id,
  error,
) {
  let start = match self.active.get(cell_id) {
    Some(s) => s
    None => return
  }
  self.active.remove(cell_id)
  guard self.enabled() else { return }
  self.pending.push(
    DerivedRebuildAborted({
      cell_id,
      dependency_count_before: start.dependency_count_before,
      changed_at_before: start.changed_at_before,
      verified_at_before: start.verified_at_before,
      error: error.to_string(),
    }),
  )
}

///|
fn RuntimeEvaluationEventHook::drain(self : RuntimeEvaluationEventHook) -> Unit {
  if self.pending.is_empty() {
    return
  }
  if self.draining {
    return
  }
  guard self.listener is Some(f) else {
    self.pending.clear()
    return
  }
  self.draining = true
  while !self.pending.is_empty() {
    let events = self.pending
    self.pending = []
    for event in events {
      f(event)
    }
  }
  self.draining = false
}
