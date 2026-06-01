///|
/// Queue entry for level-sorted push propagation.
///
/// `@priority_queue.T[A]` is a max-heap (requires `A : Compare`).
/// Negating the level makes the lowest level sort highest in the heap,
/// giving min-level-first (topological-order) dequeue semantics.
priv struct PushEntry {
  neg_level : Int
  cell_ref : CellRef
  cell_id : CellId
}

///|
impl Eq for PushEntry with fn equal(self, other) {
  self.neg_level == other.neg_level && self.cell_id == other.cell_id
}

///|
impl Compare for PushEntry with fn compare(self, other) {
  self.neg_level.compare(other.neg_level)
}

///|
priv struct PushPropagationCounters {
  mut eager_derived_evaluation_count : Int
  mut effect_execution_count : Int
  mut skipped_queue_entry_count : Int
}

///|
fn PushPropagationCounters::new() -> PushPropagationCounters {
  {
    eager_derived_evaluation_count: 0,
    effect_execution_count: 0,
    skipped_queue_entry_count: 0,
  }
}

///|
/// Returns the topological level of a cell from the push perspective.
///
/// Pull cells (signals and derived cells) are level 0 — they are inputs to the
/// push graph. Push reactives use their stored `level`. Disposed cells
/// and effects return 0 (effects are leaf nodes, not read by others).
pub fn get_level(core : RuntimeCore, cell_id : CellId) -> Int {
  if cell_id.id < 0 || cell_id.id >= core.cell_ops.length() {
    return 0
  }
  core.cell_ops[cell_id.id].level()
}

///|
/// Computes the topological level for a cell given its current sources.
///
/// Level = max(source levels) + 1. Sources with no level (pull cells,
/// disposed cells) contribute 0. A cell with no sources gets level 1.
pub fn recompute_level(
  core : RuntimeCore,
  _cell_id : CellId,
  sources : Array[CellId],
) -> Int {
  let mut max_level = 0
  for s in sources {
    let l = get_level(core, s)
    if l > max_level {
      max_level = l
    }
  }
  max_level + 1
}

///|
/// Propagates a level change from `changed_cell` to all downstream push
/// nodes using a BFS worklist.
///
/// When a push reactive's sources change, its level may shift, requiring
/// downstream push nodes to recalculate their own levels. This function
/// updates levels lazily: re-queued dirty nodes get a fresh entry in
/// `update_queue` at the new level; the old stale entry is harmlessly
/// skipped by the dequeue loop's `queued_level != node.level` guard.
fn propagate_push_level_change(
  core : RuntimeCore,
  push : PushState,
  changed_cell : CellId,
  update_queue : @priority_queue.PriorityQueue[PushEntry],
) -> Unit {
  let worklist : Array[CellId] = [changed_cell]
  while worklist.length() > 0 {
    let parent = worklist.pop().unwrap()
    for sub_id in get_subscribers(core, parent) {
      match core.cell_index[sub_id.id] {
        PushReactive(i) => {
          let node = push.reactives[i]
          let new_level = recompute_level(core, sub_id, node.sources)
          if new_level != node.level {
            node.level = new_level
            if node.dirty {
              update_queue.push({
                neg_level: -new_level,
                cell_ref: CellRef::PushReactive(i),
                cell_id: sub_id,
              })
            }
            worklist.push(sub_id)
          }
        }
        PushEffect(i) => {
          let node = push.effects[i]
          let new_level = recompute_level(core, sub_id, node.sources)
          if new_level != node.level {
            node.level = new_level
            if node.dirty {
              update_queue.push({
                neg_level: -new_level,
                cell_ref: CellRef::PushEffect(i),
                cell_id: sub_id,
              })
            }
            // Effects are terminal nodes with empty subscriber sets.
          }
        }
        _ => ()
      }
    }
  }
}

///|
fn enqueue_reachable_push_subscribers(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  source_id : CellId,
  update_queue : @priority_queue.PriorityQueue[PushEntry],
  bfs_worklist : Array[CellId],
) -> Unit {
  // Per-source O(1) gate: if this source has no reachable push cells
  // (Reactive/Effect), skip the entire BFS. push_reachable_count is
  // maintained by add_subscriber/remove_subscriber via adjust_push_reachable.
  if source_id.id >= 0 &&
    source_id.id < core.cell_ops.length() &&
    core.cell_ops[source_id.id].push_reachable_count() == 0 {
    return
  }
  // BFS through pull/hybrid derived cells to reach downstream push nodes.
  bfs_worklist.clear()
  bfs_worklist.push(source_id)
  let mut wi = 0
  while wi < bfs_worklist.length() {
    let id = bfs_worklist[wi]
    wi += 1
    for sub_id in get_subscribers(core, id) {
      match core.cell_index[sub_id.id] {
        PushReactive(i) =>
          if !push.reactives[i].dirty {
            push.reactives[i].dirty = true
            update_queue.push({
              neg_level: -push.reactives[i].level,
              cell_ref: CellRef::PushReactive(i),
              cell_id: sub_id,
            })
          }
        PushEffect(i) =>
          if !push.effects[i].dirty {
            push.effects[i].dirty = true
            update_queue.push({
              neg_level: -push.effects[i].level,
              cell_ref: CellRef::PushEffect(i),
              cell_id: sub_id,
            })
          }
        HybridMemo(i) | PullMemo(i) =>
          // Inner pruning: skip derived branches with no downstream push cells.
          if pull.memos[i].meta.push_reachable_count > 0 {
            bfs_worklist.push(sub_id)
          }
        _ => ()
      }
    }
  }
}

///|
fn emit_queue_skip(
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
  counters : PushPropagationCounters?,
  cell_id : CellId,
  queued_level : Int,
  current_level : Int,
  reason : PushQueueSkipReason,
) -> Unit {
  match (event_sink, counters) {
    (Some(emit), Some(c)) => {
      c.skipped_queue_entry_count = c.skipped_queue_entry_count + 1
      emit(PushQueueSkipped({ cell_id, queued_level, current_level, reason }))
    }
    _ => ()
  }
}

///|
fn dequeue_push_evaluation(
  core : RuntimeCore,
  push : PushState,
  update_queue : @priority_queue.PriorityQueue[PushEntry],
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
  counters : PushPropagationCounters?,
) -> CellRef? {
  while !update_queue.is_empty() {
    let entry = update_queue.pop().unwrap()
    let queued_level = -entry.neg_level
    match entry.cell_ref {
      PushReactive(idx) => {
        guard validate_cell_soft(core, entry.cell_id) else {
          emit_queue_skip(
            event_sink,
            counters,
            entry.cell_id,
            queued_level,
            0,
            DisposedOrKindMismatch,
          )
          continue
        }
        match core.cell_index[entry.cell_id.id] {
          PushReactive(current_idx) =>
            if current_idx != idx {
              emit_queue_skip(
                event_sink,
                counters,
                entry.cell_id,
                queued_level,
                get_level(core, entry.cell_id),
                DisposedOrKindMismatch,
              )
              continue
            }
          _ => {
            emit_queue_skip(
              event_sink,
              counters,
              entry.cell_id,
              queued_level,
              get_level(core, entry.cell_id),
              DisposedOrKindMismatch,
            )
            continue
          }
        }
        let reactive = push.reactives[idx]
        if queued_level != reactive.level {
          emit_queue_skip(
            event_sink,
            counters,
            entry.cell_id,
            queued_level,
            reactive.level,
            StaleLevel,
          )
          continue
        }
        if !reactive.dirty {
          emit_queue_skip(
            event_sink,
            counters,
            entry.cell_id,
            queued_level,
            reactive.level,
            NotDirty,
          )
          continue
        }
        return Some(entry.cell_ref)
      }
      PushEffect(idx) => {
        guard validate_cell_soft(core, entry.cell_id) else {
          emit_queue_skip(
            event_sink,
            counters,
            entry.cell_id,
            queued_level,
            0,
            DisposedOrKindMismatch,
          )
          continue
        }
        match core.cell_index[entry.cell_id.id] {
          PushEffect(current_idx) =>
            if current_idx != idx {
              emit_queue_skip(
                event_sink,
                counters,
                entry.cell_id,
                queued_level,
                get_level(core, entry.cell_id),
                DisposedOrKindMismatch,
              )
              continue
            }
          _ => {
            emit_queue_skip(
              event_sink,
              counters,
              entry.cell_id,
              queued_level,
              get_level(core, entry.cell_id),
              DisposedOrKindMismatch,
            )
            continue
          }
        }
        let effect = push.effects[idx]
        if queued_level != effect.level {
          emit_queue_skip(
            event_sink,
            counters,
            entry.cell_id,
            queued_level,
            effect.level,
            StaleLevel,
          )
          continue
        }
        if !effect.dirty {
          emit_queue_skip(
            event_sink,
            counters,
            entry.cell_id,
            queued_level,
            effect.level,
            NotDirty,
          )
          continue
        }
        return Some(entry.cell_ref)
      }
      _ => ()
    }
  }
  None
}

///|
fn evaluate_push_reactive(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  idx : Int,
  update_queue : @priority_queue.PriorityQueue[PushEntry],
  bfs_worklist : Array[CellId],
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
  counters : PushPropagationCounters?,
) -> Unit {
  let reactive = push.reactives[idx]
  reactive.dirty = false
  match counters {
    Some(c) =>
      c.eager_derived_evaluation_count = c.eager_derived_evaluation_count + 1
    None => ()
  }
  let reactive_cell_id = reactive.meta.cell_id
  let level_before = reactive.level
  let changed_at_before = reactive.meta.changed_at
  let old_sources = reactive.sources
  let dependency_count_before = old_sources.length()
  push_tracking(core, reactive_cell_id)
  let changed = (reactive.compute)()
  let (new_sources, new_seen) = pop_tracking(core)
  diff_and_update_subscribers(
    core,
    pull,
    push,
    datalog,
    reactive_cell_id,
    old_sources,
    new_sources,
    new_seen~,
  )
  |> ignore
  reactive.sources = new_sources
  let new_level = recompute_level(core, reactive_cell_id, new_sources)
  if new_level != reactive.level {
    reactive.level = new_level
    propagate_push_level_change(core, push, reactive_cell_id, update_queue)
  }
  if changed {
    reactive.meta.changed_at = core.revision.current_revision
    enqueue_reachable_push_subscribers(
      core, pull, push, reactive_cell_id, update_queue, bfs_worklist,
    )
  }
  match event_sink {
    Some(emit) =>
      emit(
        EagerDerivedEvaluated({
          cell_id: reactive_cell_id,
          disposition: if changed {
            RecomputedChanged
          } else {
            RecomputedUnchanged
          },
          level_before,
          level_after: reactive.level,
          dependency_count_before,
          dependency_count_after: reactive.sources.length(),
          changed_at_before,
          changed_at_after: reactive.meta.changed_at,
        }),
      )
    None => ()
  }
}

///|
fn execute_push_effect(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  idx : Int,
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
  counters : PushPropagationCounters?,
) -> Unit {
  let effect = push.effects[idx]
  effect.dirty = false
  match counters {
    Some(c) => c.effect_execution_count = c.effect_execution_count + 1
    None => ()
  }
  let effect_cell_id = effect.meta.cell_id
  let level_before = effect.level
  let old_sources = effect.sources
  let dependency_count_before = old_sources.length()
  push_tracking(core, effect_cell_id)
  (effect.execute)()
  let (new_sources, new_seen) = pop_tracking(core)
  diff_and_update_subscribers(
    core,
    pull,
    push,
    datalog,
    effect_cell_id,
    old_sources,
    new_sources,
    new_seen~,
  )
  |> ignore
  effect.sources = new_sources
  effect.level = recompute_level(core, effect_cell_id, new_sources)
  match event_sink {
    Some(emit) =>
      emit(
        EffectExecuted({
          cell_id: effect_cell_id,
          level_before,
          level_after: effect.level,
          dependency_count_before,
          dependency_count_after: effect.sources.length(),
        }),
      )
    None => ()
  }
}

///|
fn finish_push_propagation(
  core : RuntimeCore,
  changed_source_count : Int,
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
  counters : PushPropagationCounters?,
) -> Unit {
  leave_phase(core)
  match (event_sink, counters) {
    (Some(emit), Some(c)) =>
      emit(
        PushPropagationCompleted({
          changed_source_count,
          eager_derived_evaluation_count: c.eager_derived_evaluation_count,
          effect_execution_count: c.effect_execution_count,
          skipped_queue_entry_count: c.skipped_queue_entry_count,
        }),
      )
    _ => ()
  }
}

///|
/// Eagerly propagates changes from `changed_sources` through the push
/// reactive graph in topological (level-ascending) order.
///
/// Takes `datalog` because the reactive/effect recompute path calls
/// `diff_and_update_subscribers`, which threads datalog through to
/// `adjust_push_reachable` for Relation/FunctionalRelation/Rule source arms.
pub fn push_propagate_from(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_sources : Array[CellId],
) -> Unit {
  push_propagate_from_with_events(
    core,
    pull,
    push,
    datalog,
    changed_sources,
    None,
  )
}

///|
pub fn push_propagate_from_with_events(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_sources : Array[CellId],
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
) -> Unit {
  enter_phase(core, PushPropagating)
  let update_queue : @priority_queue.PriorityQueue[PushEntry] = @priority_queue.PriorityQueue([],
  )
  // Reused across enqueue_reachable_push_subscribers calls to avoid per-call allocation.
  let bfs_worklist : Array[CellId] = []
  let counters = match event_sink {
    Some(_) => Some(PushPropagationCounters::new())
    None => None
  }

  for changed_id in changed_sources {
    enqueue_reachable_push_subscribers(
      core, pull, push, changed_id, update_queue, bfs_worklist,
    )
  }

  while !update_queue.is_empty() {
    match
      dequeue_push_evaluation(core, push, update_queue, event_sink, counters) {
      Some(PushReactive(idx)) =>
        evaluate_push_reactive(
          core, pull, push, datalog, idx, update_queue, bfs_worklist, event_sink,
          counters,
        )
      Some(PushEffect(idx)) =>
        execute_push_effect(
          core, pull, push, datalog, idx, event_sink, counters,
        )
      Some(_) | None => ()
    }
  }
  finish_push_propagation(core, changed_sources.length(), event_sink, counters)
}
