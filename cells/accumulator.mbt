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
/// Constructs the typed buffer state and the SlotMeta closures that the
/// runtime uses to drive snapshot/finalize/dispose phases.
pub fn[T : Eq] Accumulator::new(
  rt~ : Runtime,
  label? : String,
) -> Accumulator[T] {
  let per_memo : @hashmap.HashMap[CellId, Array[T]] = @hashmap.new()
  let prev_push_sets : @hashmap.HashMap[CellId, Array[T]] = @hashmap.new()
  let push_revised_at : @hashmap.HashMap[CellId, Revision] = @hashmap.new()

  // snapshot_and_clear: move current buffer into prev, replace per_memo[M]
  // with a fresh array. Called BEFORE_CLOSURE.
  let snapshot_and_clear = (m_id : CellId) => {
    match per_memo.get(m_id) {
      Some(current) => {
        prev_push_sets.set(m_id, current)
        per_memo.set(m_id, [])
      }
      None =>
        // Memo had no prior pushes; record empty prev so diff catches
        // first-ever pushes correctly.
        prev_push_sets.set(m_id, [])
    }
  }

  // restore_buffer: undo snapshot. Called ON_ABORT.
  let restore_buffer = (m_id : CellId) => {
    match prev_push_sets.get(m_id) {
      Some(prev) => {
        per_memo.set(m_id, prev)
        prev_push_sets.remove(m_id)
      }
      None =>
        // Shouldn't happen — BEFORE_CLOSURE always writes prev_push_sets.
        ()
    }
  }

  // finalize_memo: atomic commit-phase work. Compare prev vs current;
  // bump push_revised_at if different; drop snapshot; gc empty buffer.
  let finalize_memo = (m_id : CellId, rev : Revision) => {
    let prev = match prev_push_sets.get(m_id) {
      Some(p) => p
      None => []
    }
    let current = match per_memo.get(m_id) {
      Some(c) => c
      None => []
    }
    // Structural Array[T] equality (T : Eq in scope from outer fn).
    let same = arrays_eq(prev, current)
    if !same {
      push_revised_at.set(m_id, rev)
    }
    prev_push_sets.remove(m_id)
    if current.length() == 0 {
      per_memo.remove(m_id)
    }
  }

  // dispose_memo: remove memo's entries when the memo itself is disposed.
  let dispose_memo = (m_id : CellId) => {
    per_memo.remove(m_id)
    prev_push_sets.remove(m_id)
    push_revised_at.remove(m_id)
  }

  // clear_new_run_buffer: ON_ABORT cleanup for a slot touched in this run
  // that was NOT in prev_contributions. Drops the in-flight pushes but
  // keeps push_revised_at and prev_push_sets intact so a prior run's
  // revision marker survives the abort. prev_push_sets has no entry for
  // m_id in this case (snapshot_and_clear wasn't called this run), so
  // not touching it is correct.
  let clear_new_run_buffer = (m_id : CellId) => per_memo.remove(m_id)

  let push_revised_at_for = (m_id : CellId) => {
    match push_revised_at.get(m_id) {
      Some(r) => r
      None => Revision::initial()
    }
  }
  let has_buffer_for = (m_id : CellId) => {
    match per_memo.get(m_id) {
      Some(arr) => arr.length() > 0
      None => false
    }
  }
  let meta : SlotMeta = {
    label,
    disposed: false,
    snapshot_and_clear,
    restore_buffer,
    finalize_memo,
    dispose_memo,
    clear_new_run_buffer,
    push_revised_at_for,
    has_buffer_for,
  }
  let slot_id = rt.register_accumulator_slot(meta)
  { rt, slot_id, label, per_memo, prev_push_sets, push_revised_at }
}

///|
/// Structural equality over Array[T] where T : Eq.
fn[T : Eq] arrays_eq(a : Array[T], b : Array[T]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
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
/// Appends a value to this accumulator, keyed by the currently-computing
/// memo's CellId.
///
/// # Errors
///
/// - `fail` if called outside a tracked compute context
/// - `fail` if the top tracking frame is not a Memo (MVP restriction)
/// - `fail` if this accumulator has been disposed
/// - `abort` (via `check_cross_runtime`) if slot belongs to a different runtime
pub fn[T] Accumulator::push(
  self : Accumulator[T],
  value : T,
) -> Unit raise Failure {
  // Cross-runtime check (abort — pre-existing pattern).
  self.rt.check_cross_runtime(self.slot_id.runtime_id, "Accumulator")
  let slot = self.rt.accumulator_slots[self.slot_id.id]
  if slot.disposed {
    fail("Accumulator::push to disposed accumulator")
  }
  // Top-frame check.
  let frame = match self.rt.top_active_query() {
    Some(q) => q
    None => fail("Accumulator::push called outside a tracked compute")
  }
  let m_id = frame.cell_id
  // Top-frame must be a PullMemo / HybridMemo cell.
  match self.rt.core.cell_index[m_id.id] {
    PullMemo(_) | HybridMemo(_) => ()
    _ => fail("Accumulator::push only valid inside Memo compute")
  }
  // Append to typed buffer.
  let buf = match self.per_memo.get(m_id) {
    Some(existing) => existing
    None => {
      let fresh : Array[T] = []
      self.per_memo.set(m_id, fresh)
      fresh
    }
  }
  buf.push(value)
  // Stage touched slot on ActiveQuery (committed in AFTER_CLOSURE in Task 10).
  frame.touched_accumulator_slots.add(self.slot_id)
}

///|
/// Untracked read: returns the accumulated values pushed by `self` during
/// its last successful compute. Does NOT force verification and does NOT
/// record a dependency. Returns a defensive copy.
///
/// Permissive on disposal: returns `[]` if the accumulator or target memo
/// is disposed. Matches Signal::peek semantics.
pub fn[T, A] Memo::accumulated_peek(
  self : Memo[T],
  acc : Accumulator[A],
) -> Array[A] {
  // Cross-runtime guards: both self (the memo) and acc (the accumulator)
  // must belong to self.rt. The second check is load-bearing — without it,
  // `acc.slot_id.id` indexes self.rt.accumulator_slots with an ID from a
  // different runtime and either silently returns the wrong slot or panics
  // with an unhelpful bounds error.
  self.rt.check_cross_runtime(self.rt.core.runtime_id, "Memo::accumulated_peek")
  self.rt.check_cross_runtime(
    acc.slot_id.runtime_id,
    "Memo::accumulated_peek (Accumulator)",
  )
  let slot = self.rt.accumulator_slots[acc.slot_id.id]
  if slot.disposed {
    return []
  }
  if self.rt.is_cell_disposed(self.cell_id) {
    return []
  }
  match acc.per_memo.get(self.cell_id) {
    Some(vs) => vs.copy()
    None => []
  }
}

///|
/// Tracked read: returns the accumulated values pushed by `self` during
/// its last successful compute, records a synthetic dep on the current
/// compute frame, and forces verification of `self` via
/// `ensure_computed_untracked`.
///
/// # Errors
///
/// Raises `Failure` on any error (disposal, cycle, or target memo's own
/// raised compute). The type is unified into `Failure` because memo
/// compute closures are `() -> T raise Failure`, and `accumulated` is
/// designed to be called from within a compute closure. Use
/// `accumulated_result` for Result-style cycle handling.
pub fn[T, A] Memo::accumulated(
  self : Memo[T],
  acc : Accumulator[A],
) -> Array[A] raise Failure {
  self.rt.check_cross_runtime(self.rt.core.runtime_id, "Memo::accumulated")
  self.rt.check_cross_runtime(
    acc.slot_id.runtime_id,
    "Memo::accumulated (Accumulator)",
  )
  let slot = self.rt.accumulator_slots[acc.slot_id.id]
  if slot.disposed {
    fail("Memo::accumulated called on disposed Accumulator")
  }
  if self.rt.is_cell_disposed(self.cell_id) {
    fail("Memo::accumulated called on disposed target memo")
  }
  // Force verification of target memo without recording an ordinary dep.
  match self.rt.ensure_computed_untracked(self.cell_id) {
    Ok(_) => ()
    Err(e) => fail("Memo::accumulated: " + e.format_path())
  }
  // Stage synthetic read on current frame (if any).
  let current_rev = (slot.push_revised_at_for)(self.cell_id)
  match self.rt.top_active_query() {
    Some(frame) =>
      frame.accumulator_reads.set((acc.slot_id, self.cell_id), current_rev)
    None => ()
  }
  // Return defensive copy of buffer.
  match acc.per_memo.get(self.cell_id) {
    Some(vs) => vs.copy()
    None => []
  }
}

///|
/// Result-style variant of `accumulated` that converts `CycleError` to
/// `Err(...)` while still raising `Failure` on disposed accumulator /
/// target (those are defects, not recoverable signals).
pub fn[T, A] Memo::accumulated_result(
  self : Memo[T],
  acc : Accumulator[A],
) -> Result[Array[A], CycleError] raise Failure {
  self.rt.check_cross_runtime(
    self.rt.core.runtime_id,
    "Memo::accumulated_result",
  )
  self.rt.check_cross_runtime(
    acc.slot_id.runtime_id,
    "Memo::accumulated_result (Accumulator)",
  )
  let slot = self.rt.accumulator_slots[acc.slot_id.id]
  if slot.disposed {
    fail("Memo::accumulated_result called on disposed Accumulator")
  }
  if self.rt.is_cell_disposed(self.cell_id) {
    fail("Memo::accumulated_result called on disposed target memo")
  }
  match self.rt.ensure_computed_untracked(self.cell_id) {
    Err(e) => Err(e)
    Ok(_) => {
      let current_rev = (slot.push_revised_at_for)(self.cell_id)
      match self.rt.top_active_query() {
        Some(frame) =>
          frame.accumulator_reads.set((acc.slot_id, self.cell_id), current_rev)
        None => ()
      }
      let vs = match acc.per_memo.get(self.cell_id) {
        Some(arr) => arr.copy()
        None => []
      }
      Ok(vs)
    }
  }
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
