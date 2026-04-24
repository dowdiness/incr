///|
/// Queue entry for level-sorted push propagation.
///
/// `@priority_queue.T[A]` is a max-heap (requires `A : Compare`).
/// Negating the level makes the lowest level sort highest in the heap,
/// giving min-level-first (topological-order) dequeue semantics.
priv struct PushEntry {
  neg_level : Int
  cell_ref : CellRef
}

///|
impl Eq for PushEntry with equal(self, other) {
  self.neg_level == other.neg_level
}

///|
impl Compare for PushEntry with compare(self, other) {
  self.neg_level.compare(other.neg_level)
}

///|
/// Returns the topological level of a cell from the push perspective.
///
/// Pull cells (signals and memos) are level 0 — they are inputs to the
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
fn propagate_level_change(
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
/// Eagerly propagates changes from `changed_sources` through the push
/// reactive graph in topological (level-ascending) order.
///
/// Moved from cells/push_propagate.mbt in R1 Stage 3f. Takes `datalog`
/// because the reactive/effect recompute path calls
/// `diff_and_update_subscribers`, which threads datalog through to
/// `adjust_push_reachable` for Relation/FunctionalRelation/Rule source
/// arms. (The Codex pre-review's (core, pull, push) suggestion missed
/// the transitive dispatch into adjust_push_reachable.)
pub fn push_propagate_from(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_sources : Array[CellId],
) -> Unit {
  enter_phase(core, PushPropagating)
  let update_queue : @priority_queue.PriorityQueue[PushEntry] = @priority_queue.new()
  // Reused across all enqueue_push_subscribers calls to avoid per-call allocation.
  let bfs_worklist : Array[CellId] = []

  fn enqueue_push_subscribers(source_id : CellId) -> Unit {
    // Per-source O(1) gate: if this source has no reachable push cells
    // (Reactive/Effect), skip the entire BFS. push_reachable_count is
    // maintained by add_subscriber/remove_subscriber via adjust_push_reachable.
    if source_id.id >= 0 &&
      source_id.id < core.cell_ops.length() &&
      core.cell_ops[source_id.id].push_reachable_count() == 0 {
      return
    }
    // BFS through pull/hybrid memos to reach downstream push nodes.
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
              })
            }
          PushEffect(i) =>
            if !push.effects[i].dirty {
              push.effects[i].dirty = true
              update_queue.push({
                neg_level: -push.effects[i].level,
                cell_ref: CellRef::PushEffect(i),
              })
            }
          HybridMemo(i) | PullMemo(i) =>
            // Inner pruning: skip memo branches with no downstream push cells.
            if pull.memos[i].meta.push_reachable_count > 0 {
              bfs_worklist.push(sub_id)
            }
          _ => ()
        }
      }
    }
  }

  for changed_id in changed_sources {
    enqueue_push_subscribers(changed_id)
  }

  while !update_queue.is_empty() {
    let entry = update_queue.pop().unwrap()
    let queued_level = -entry.neg_level
    match entry.cell_ref {
      PushReactive(idx) => {
        let reactive = push.reactives[idx]
        if queued_level != reactive.level {
          continue
        }
        match core.cell_index[reactive.meta.cell_id.id] {
          PushReactive(_) => ()
          _ => continue
        }
        if !reactive.dirty {
          continue
        }
        reactive.dirty = false
        let reactive_cell_id = reactive.meta.cell_id
        let old_sources = reactive.sources
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
          propagate_level_change(core, push, reactive_cell_id, update_queue)
        }
        if changed {
          reactive.meta.changed_at = core.revision.current_revision
          enqueue_push_subscribers(reactive_cell_id)
        }
      }
      PushEffect(idx) => {
        let effect = push.effects[idx]
        if queued_level != effect.level {
          continue
        }
        match core.cell_index[effect.meta.cell_id.id] {
          PushEffect(_) => ()
          _ => continue
        }
        if !effect.dirty {
          continue
        }
        effect.dirty = false
        let effect_cell_id = effect.meta.cell_id
        let old_sources = effect.sources
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
      }
      _ => ()
    }
  }
  leave_phase(core)
}
