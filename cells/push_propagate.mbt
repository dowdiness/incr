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
fn Runtime::get_level(self : Runtime, cell_id : CellId) -> Int {
  if cell_id.id < 0 || cell_id.id >= self.core.cell_ops.length() {
    return 0
  }
  self.core.cell_ops[cell_id.id].level()
}

///|
/// Computes the topological level for a cell given its current sources.
///
/// Level = max(source levels) + 1. Sources with no level (pull cells,
/// disposed cells) contribute 0. A cell with no sources gets level 1.
fn Runtime::recompute_level(
  self : Runtime,
  _cell_id : CellId,
  sources : Array[CellId],
) -> Int {
  let mut max_level = 0
  for s in sources {
    let l = self.get_level(s)
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
fn Runtime::propagate_level_change(
  self : Runtime,
  changed_cell : CellId,
  update_queue : @priority_queue.PriorityQueue[PushEntry],
) -> Unit {
  let worklist : Array[CellId] = [changed_cell]
  while worklist.length() > 0 {
    let parent = worklist.pop().unwrap()
    for sub_id in self.get_subscribers(parent) {
      match self.core.cell_index[sub_id.id] {
        PushReactive(i) => {
          let node = self.push.reactives[i]
          let new_level = self.recompute_level(sub_id, node.sources)
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
          let node = self.push.effects[i]
          let new_level = self.recompute_level(sub_id, node.sources)
          if new_level != node.level {
            node.level = new_level
            if node.dirty {
              update_queue.push({
                neg_level: -new_level,
                cell_ref: CellRef::PushEffect(i),
              })
            }
            // Effects are terminal nodes with empty subscriber sets, so no
            // worklist.push(sub_id) is needed — there is nothing downstream.
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
/// # Algorithm
///
/// 1. Seed the queue: mark push subscribers of each changed source as dirty
///    and enqueue them at their current level.
/// 2. Dequeue min-level entries first (glitch-free topological order).
/// 3. For each PushReactive: recompute, update subscriber links and level,
///    propagate level changes downstream, then enqueue its own push
///    subscribers if its value changed (early cutoff on unchanged values).
/// 4. For each PushEffect: execute, update subscriber links and level.
///
/// Called by `commit_batch` (after signal changes) and `fixpoint` (after
/// relation changes).
fn Runtime::push_propagate_from(
  self : Runtime,
  changed_sources : Array[CellId],
) -> Unit {
  let update_queue : @priority_queue.PriorityQueue[PushEntry] = @priority_queue.new()
  // Reused across all enqueue_push_subscribers calls to avoid per-call allocation.
  let bfs_worklist : Array[CellId] = []

  fn enqueue_push_subscribers(source_id : CellId) -> Unit {
    // O(1) gate: skip BFS entirely if no push cell is downstream of this source.
    // push_reachable_count > 0 iff at least one live Reactive/Effect is reachable.
    if source_id.id >= 0 &&
      source_id.id < self.core.cell_ops.length() &&
      self.core.cell_ops[source_id.id].push_reachable_count() == 0 {
      return
    }
    // BFS through pull/hybrid memos to reach downstream push nodes.
    // Pull and hybrid memos verify lazily, but push reactives/effects that
    // transitively depend on them must be eagerly re-run on upstream changes.
    bfs_worklist.clear()
    bfs_worklist.push(source_id)
    let mut wi = 0
    while wi < bfs_worklist.length() {
      let id = bfs_worklist[wi]
      wi += 1
      for sub_id in self.get_subscribers(id) {
        match self.core.cell_index[sub_id.id] {
          PushReactive(i) =>
            if not(self.push.reactives[i].dirty) {
              self.push.reactives[i].dirty = true
              update_queue.push({
                neg_level: -self.push.reactives[i].level,
                cell_ref: CellRef::PushReactive(i),
              })
            }
          PushEffect(i) =>
            if not(self.push.effects[i].dirty) {
              self.push.effects[i].dirty = true
              update_queue.push({
                neg_level: -self.push.effects[i].level,
                cell_ref: CellRef::PushEffect(i),
              })
            }
          HybridMemo(i) =>
            if self.pull.memos[i].meta.push_reachable_count > 0 {
              bfs_worklist.push(sub_id)
            }
          PullMemo(i) =>
            if self.pull.memos[i].meta.push_reachable_count > 0 {
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

  while not(update_queue.is_empty()) {
    let entry = update_queue.pop().unwrap()
    let queued_level = -entry.neg_level
    match entry.cell_ref {
      PushReactive(idx) => {
        let reactive = self.push.reactives[idx]
        // Stale entry check: level may have been updated by propagate_level_change
        if queued_level != reactive.level {
          continue
        }
        // Disposal check: another node may have disposed this reactive mid-wave
        match self.core.cell_index[reactive.meta.cell_id.id] {
          PushReactive(_) => ()
          _ => continue
        }
        // Dirty check: skip if not dirty (stale entry from a previous wave, or
        // from slot reuse — a newly allocated cell at the same SoA index starts
        // with dirty=false, so a lingering queue entry from the old cell is
        // harmlessly skipped here).
        if not(reactive.dirty) {
          continue
        }
        reactive.dirty = false
        let reactive_cell_id = reactive.meta.cell_id
        let old_sources = reactive.sources
        self.begin_tracking(reactive_cell_id)
        let changed = (reactive.compute)()
        let new_sources = self.end_tracking()
        self.finish_tracking(reactive_cell_id, old_sources, new_sources)
        reactive.sources = new_sources
        let new_level = self.recompute_level(reactive_cell_id, new_sources)
        if new_level != reactive.level {
          reactive.level = new_level
          self.propagate_level_change(reactive_cell_id, update_queue)
        }
        if changed {
          reactive.meta.changed_at = self.core.current_revision
          enqueue_push_subscribers(reactive_cell_id)
        }
      }
      PushEffect(idx) => {
        let effect = self.push.effects[idx]
        if queued_level != effect.level {
          continue
        }
        // Disposal check: another node may have disposed this effect mid-wave
        match self.core.cell_index[effect.meta.cell_id.id] {
          PushEffect(_) => ()
          _ => continue
        }
        // Dirty check: same guard as PushReactive — skip stale or reused-slot entries.
        if not(effect.dirty) {
          continue
        }
        effect.dirty = false
        let effect_cell_id = effect.meta.cell_id
        let old_sources = effect.sources
        self.begin_tracking(effect_cell_id)
        (effect.execute)()
        let new_sources = self.end_tracking()
        self.finish_tracking(effect_cell_id, old_sources, new_sources)
        effect.sources = new_sources
        effect.level = self.recompute_level(effect_cell_id, new_sources)
      }
      _ => ()
    }
  }
}
