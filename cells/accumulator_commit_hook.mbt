///|
/// Per-cell state for AccumulatorCommitHook between before_recompute and
/// after_success/after_abort. Snapshot of prev contributions + staged
/// touched slots and synthetic reads.
priv struct RecomputeState {
  prev_contributions : Array[@incr_types.AccumulatorId]
  mut touched : @hashset.HashSet[@incr_types.AccumulatorId]?
  mut reads : @hashmap.HashMap[
    (@incr_types.AccumulatorId, CellId),
    @incr_types.Revision,
  ]?
}

///|
/// MemoCommitPhase implementor that migrates the accumulator's three named
/// commit-path calls (memo_snapshot_*, memo_restore_*, memo_commit_*) into
/// trait-dispatched hooks. Per-cell state in `active` is keyed by the
/// currently-recomputing CellId — each `before_recompute(c)` creates an
/// entry, the matching `after_success(c)` or `after_abort(c)` removes it.
priv struct AccumulatorCommitHook {
  active : @hashmap.HashMap[CellId, RecomputeState]
}

///|
fn AccumulatorCommitHook::new() -> AccumulatorCommitHook {
  { active: @hashmap.HashMap([]) }
}

///|
/// Accessor for push paths in cells/accumulator.mbt — preserves the
/// "no entry → silent no-op" behavior at accumulator.mbt:540 / :581.
fn AccumulatorCommitHook::for_cell(
  self : AccumulatorCommitHook,
  cell_id : CellId,
) -> RecomputeState? {
  self.active.get(cell_id)
}

///|
fn RecomputeState::ensure_touched(
  self : RecomputeState,
) -> @hashset.HashSet[@incr_types.AccumulatorId] {
  match self.touched {
    Some(s) => s
    None => {
      let s = @hashset.HashSet([])
      self.touched = Some(s)
      s
    }
  }
}

///|
fn RecomputeState::ensure_reads(
  self : RecomputeState,
) -> @hashmap.HashMap[(@incr_types.AccumulatorId, CellId), @incr_types.Revision] {
  match self.reads {
    Some(m) => m
    None => {
      let m = @hashmap.HashMap([])
      self.reads = Some(m)
      m
    }
  }
}

///|
/// before_recompute: snapshot prev_contributions buffers (clear so this
/// run starts empty); create active entry keyed by recomputing cell.
impl MemoCommitPhase for AccumulatorCommitHook with before_recompute(
  self,
  rt,
  cell_id,
) {
  let prev : Array[@incr_types.AccumulatorId] = match
    rt.accumulator_contributions.get(cell_id) {
    Some(s) => s.to_array()
    None => []
  }
  for slot_id in prev {
    let slot = rt.accumulator_slots[slot_id.id]
    if !slot.disposed {
      (slot.snapshot_and_clear)(cell_id)
    }
  }
  self.active.set(cell_id, {
    prev_contributions: prev,
    touched: None,
    reads: None,
  })
}

///|
/// after_abort: restore prev snapshots; clear new-run buffer for
/// touched-not-prev slots (preserves push_revised_at).
impl MemoCommitPhase for AccumulatorCommitHook with after_abort(
  self,
  rt,
  cell_id,
) {
  // @hashmap.HashMap::remove returns Unit; read then remove.
  let state = self.active.get(cell_id).unwrap()
  self.active.remove(cell_id)
  let touched : Array[@incr_types.AccumulatorId] = match state.touched {
    Some(s) => s.to_array()
    None => []
  }
  for slot_id in state.prev_contributions {
    let slot = rt.accumulator_slots[slot_id.id]
    if !slot.disposed {
      (slot.restore_buffer)(cell_id)
    }
  }
  for slot_id in touched {
    let mut in_prev = false
    for p in state.prev_contributions {
      if p == slot_id {
        in_prev = true
        break
      }
    }
    if in_prev {
      continue
    }
    let slot = rt.accumulator_slots[slot_id.id]
    if !slot.disposed {
      (slot.clear_new_run_buffer)(cell_id)
    }
  }
}

///|
/// after_success: atomic per-slot finalize over prev ∪ touched; commit
/// staged reads + rebuilt contributions.
impl MemoCommitPhase for AccumulatorCommitHook with after_success(
  self,
  rt,
  cell_id,
) {
  let state = self.active.get(cell_id).unwrap()
  self.active.remove(cell_id)
  let cell = rt.get_memo_data(cell_id)
  let all_slots : @hashset.HashSet[@incr_types.AccumulatorId] = @hashset.HashSet([],
  )
  for s in state.prev_contributions {
    all_slots.add(s)
  }
  match state.touched {
    Some(t) =>
      for s in t {
        all_slots.add(s)
      }
    None => ()
  }
  let current_revision = rt.core.revision.current_revision
  let new_contributions : @hashset.HashSet[@incr_types.AccumulatorId] = @hashset.HashSet([],
  )
  for slot_id in all_slots {
    let slot = rt.accumulator_slots[slot_id.id]
    if slot.disposed {
      continue
    }
    (slot.finalize_memo)(cell_id, current_revision)
    if (slot.has_buffer_for)(cell_id) {
      new_contributions.add(slot_id)
    }
  }
  cell.accumulator_reads.clear()
  match state.reads {
    Some(reads) =>
      for k, v in reads {
        cell.accumulator_reads.set(k, v)
      }
    None => ()
  }
  if new_contributions.is_empty() {
    rt.accumulator_contributions.remove(cell_id)
  } else {
    rt.accumulator_contributions.set(cell_id, new_contributions)
  }
}
