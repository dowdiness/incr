///|
using @pull {type MemoData}

///|
/// CellLifecycle impl for MemoData (pull memos and hybrid memos).
/// Lives here rather than in internal/pull/ because it references Runtime,
/// which cannot leak into an internal package.
impl CellLifecycle for MemoData with dispose_cell(self, rt, cell_id) -> Unit {
  match rt.core.cell_index[cell_id.id] {
    PullMemo(idx) | HybridMemo(idx) => {
      for dep in self.dependencies {
        rt.remove_subscriber(dep, cell_id)
      }
      self.dependencies = []
      self.meta.subscribers.clear()
      self.meta.label = None
      self.on_change = None
      self.verified_at = Revision::initial()
      self.in_progress = false
      // Clean up accumulator contributions — each slot that this memo pushed
      // to must drop its per_memo[M] buffer and push_revised_at[M] entry.
      match rt.accumulator_contributions.get(cell_id) {
        Some(slot_set) =>
          for slot_id in slot_set {
            if slot_id.id < rt.accumulator_slots.length() {
              let slot = rt.accumulator_slots[slot_id.id]
              if !slot.disposed {
                (slot.dispose_memo)(cell_id)
              }
            }
          }
        None => ()
      }
      rt.accumulator_contributions.remove(cell_id)
      self.accumulator_reads.clear()
      rt.core.cell_index[cell_id.id] = Disposed
      rt.pull.free_memos.push(idx)
    }
    _ => ()
  }
}
