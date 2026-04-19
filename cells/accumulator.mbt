///|
/// A side-channel collector for values pushed by memo compute closures.
///
/// Typed buffers (`per_memo`, `prev_push_sets`) live on the handle; runtime
/// holds only type-erased closures in SlotMeta. See the design doc
/// `docs/superpowers/specs/2026-04-19-accumulator-api-design.md`.
pub struct Accumulator[T] {
  priv rt : Runtime
  priv slot_id : @incr_types.AccumulatorId
  priv label : String?
  // Typed per-memo buffer: the values this memo pushed in its latest
  // successful compute. Read by Memo::accumulated(_peek).
  priv per_memo : @hashmap.HashMap[CellId, Array[T]]
  // Snapshot of per_memo taken at BEFORE_CLOSURE; restored on ON_ABORT.
  priv prev_push_sets : @hashmap.HashMap[CellId, Array[T]]
  // Per-memo revision bumped in finalize_memo when push-set differs
  // across recomputes. Reader records this in its accumulator_reads.
  priv push_revised_at : @hashmap.HashMap[CellId, Revision]
}

///|
/// Creates a new accumulator bound to the given runtime.
///
/// The SlotMeta closures are stubs at this task — Task 9 wires them to the
/// typed buffers on the handle.
pub fn[T : Eq] Accumulator::new(
  rt~ : Runtime,
  label? : String,
) -> Accumulator[T] {
  let per_memo : @hashmap.HashMap[CellId, Array[T]] = @hashmap.new()
  let prev_push_sets : @hashmap.HashMap[CellId, Array[T]] = @hashmap.new()
  let push_revised_at : @hashmap.HashMap[CellId, Revision] = @hashmap.new()
  // Stub closures — Task 9 replaces these with real implementations.
  let meta : SlotMeta = {
    label,
    disposed: false,
    snapshot_and_clear: _ => (),
    restore_buffer: _ => (),
    finalize_memo: (_, _) => (),
    dispose_memo: _ => (),
    push_revised_at_for: _ => Revision::initial(),
  }
  let slot_id = rt.register_accumulator_slot(meta)
  { rt, slot_id, label, per_memo, prev_push_sets, push_revised_at }
}

///|
/// Returns the slot's unique ID.
pub fn[T] Accumulator::id(self : Accumulator[T]) -> @incr_types.AccumulatorId {
  self.slot_id
}

///|
/// Returns the optional label provided at construction.
pub fn[T] Accumulator::label(self : Accumulator[T]) -> String? {
  self.label
}

///|
/// Returns true iff this accumulator has been disposed.
pub fn[T] Accumulator::is_disposed(self : Accumulator[T]) -> Bool {
  self.rt.accumulator_slots[self.slot_id.id].disposed
}

///|
/// Disposes the accumulator. Idempotent. Clears typed buffers and removes
/// reverse-index entries from rt.accumulator_contributions. The slot_id
/// stays allocated — monotonic, never reused.
pub fn[T] Accumulator::dispose(self : Accumulator[T]) -> Unit {
  let slot = self.rt.accumulator_slots[self.slot_id.id]
  if slot.disposed {
    return
  }
  // Remove slot_id from every contributing memo's reverse index.
  for m_id in self.per_memo.keys() {
    match self.rt.accumulator_contributions.get(m_id) {
      Some(set) => {
        set.remove(self.slot_id)
        if set.is_empty() {
          self.rt.accumulator_contributions.remove(m_id)
        }
      }
      None => ()
    }
  }
  self.per_memo.clear()
  self.prev_push_sets.clear()
  self.push_revised_at.clear()
  slot.disposed = true
}

///|
/// Debug representation.
pub fn[T] Accumulator::debug(self : Accumulator[T]) -> String {
  let lbl = match self.label {
    Some(s) => "\"" + s + "\""
    None => "None"
  }
  "Accumulator(id=" +
  self.slot_id.id.to_string() +
  ", label=" +
  lbl +
  ", disposed=" +
  self.is_disposed().to_string() +
  ")"
}
