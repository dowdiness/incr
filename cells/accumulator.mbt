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
  let per_memo : @hashmap.HashMap[CellId, Array[T]] = @hashmap.HashMap([])
  let prev_push_sets : @hashmap.HashMap[CellId, Array[T]] = @hashmap.HashMap([])
  let push_revised_at : @hashmap.HashMap[CellId, Revision] = @hashmap.HashMap([])

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
    if !prev.equal(current) {
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
/// Runtime-side metadata for an Accumulator slot. Holds type-erased closures
/// captured at Accumulator construction with `T : Eq` in scope; the typed
/// buffers live on the Accumulator[T] handle itself.
///
/// This struct is intentionally package-private — runtime code dispatches
/// through the closures; no outside caller needs to construct or read it.
priv struct SlotMeta {
  label : String?
  mut disposed : Bool
  // Phase closures (typed Accumulator handle captured at construction):
  snapshot_and_clear : (@incr_types.CellId) -> Unit
  restore_buffer : (@incr_types.CellId) -> Unit
  finalize_memo : (@incr_types.CellId, @incr_types.Revision) -> Unit
  dispose_memo : (@incr_types.CellId) -> Unit
  // ON_ABORT cleanup for slots this aborted run touched but that were
  // NOT in prev_contributions at BEFORE_CLOSURE. Clears per_memo[M]
  // (the in-flight pushes) while preserving push_revised_at[M], so a
  // prior run's revision marker is not rolled back. Without this,
  // consumers with a pre-existing stored read would miss invalidation.
  clear_new_run_buffer : (@incr_types.CellId) -> Unit
  // Verify-side typed data access:
  push_revised_at_for : (@incr_types.CellId) -> @incr_types.Revision
  // True iff the slot still has a non-empty per_memo[M] buffer. Used in
  // AFTER_CLOSURE to rebuild accumulator_contributions reverse index.
  has_buffer_for : (@incr_types.CellId) -> Bool
}

///|
/// Internal: register a new accumulator slot and return its ID.
/// Called by Accumulator::new. Monotonic — IDs never reused.
///
/// Pushes into `accumulator_slots` and the parallel
/// `accumulator_snapshots` cache so the two arrays stay index-aligned.
fn Runtime::register_accumulator_slot(
  self : Runtime,
  meta : SlotMeta,
) -> @incr_types.AccumulatorId {
  let id = self.next_accumulator_id
  self.next_accumulator_id = id + 1
  self.accumulator_slots.push(meta)
  self.accumulator_snapshots.push(meta)
  self.check_accumulator_cache_invariant()
  { runtime_id: self.core.runtime_id, id }
}

///|
/// Verify-side view of a SlotMeta's disposal flag.
impl @shared.SlotSnapshot for SlotMeta with fn disposed(self) -> Bool {
  self.disposed
}

///|
/// Verify-side accessor for the slot's per-memo push_revised_at revision.
///
/// The local binding is load-bearing: `self.push_revised_at_for` names
/// both the closure field on `SlotMeta` and this trait method, so
/// `self.push_revised_at_for(cell_id)` would be parsed as a recursive
/// trait-method call and infinite-loop. Binding the closure to a local
/// name disambiguates lexically — a parens-wrap `(self.field)(arg)`
/// works too but is a parser subtlety that's easy to break in a later
/// refactor.
impl @shared.SlotSnapshot for SlotMeta with fn push_revised_at_for(
  self,
  cell_id,
) -> Revision {
  let f = self.push_revised_at_for
  f(cell_id)
}

///|
/// Internal: guarantee a memo has been computed and is up-to-date in the
/// current revision, WITHOUT recording an ordinary dep on the caller's
/// tracking frame. Used by Memo::accumulated.
///
/// # Behavior
///
/// - If the cell is disposed, returns Ok(()) silently (caller handles
///   disposal separately; this is defense-in-depth for other call sites).
/// - If the memo has never been computed (verified_at == initial revision),
///   triggers the first compute via the memo's stored compute closure.
/// - Otherwise runs `pull_verify`, which may recompute if stale.
/// - Neither path calls `record_dependency`. The synthetic accumulator
///   dep is recorded separately in the accumulator read flow.
///
/// Both `data.compute()` and `pull_verify` push a fresh tracking frame
/// for the target memo while recomputing, so any `get()` calls inside the
/// target's closure record deps on the target's frame — never on the
/// caller's frame.
fn Runtime::ensure_computed_untracked(
  self : Runtime,
  cell_id : CellId,
) -> Result[Unit, CycleError] raise Failure {
  if self.is_cell_disposed(cell_id) {
    return Ok(())
  }
  let data = self.get_memo_data(cell_id)
  // "Never been computed" is tracked explicitly via has_been_computed
  // rather than via verified_at == Revision::initial() because a fresh
  // runtime starts at initial, so a successful first compute would leave
  // verified_at == initial, indistinguishable from "never computed".
  if !data.has_been_computed {
    match (data.compute)() {
      Ok(_) => Ok(())
      Err(e) => Err(e)
    }
  } else {
    match self.pull_verify(cell_id) {
      Ok(_) => Ok(())
      Err(e) => Err(e)
    }
  }
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
  if self.rt.static_recompute_depth > 0 {
    fail("Accumulator::push is unsupported inside static Derived recompute")
  }
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
  // Stage touched slot on AccumulatorCommitHook (committed in AFTER_CLOSURE).
  // ensure_for_cell lazy-creates the entry when before_recompute took its
  // fast-path (no slots existed at recompute-start time but this accumulator
  // was registered mid-recompute). The line-449 cell_index check above
  // guarantees we're inside a Memo/HybridMemo frame.
  self.rt.accumulator_commit_hook
  .ensure_for_cell(m_id)
  .ensure_touched()
  .add(self.slot_id)
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
  if self.rt.static_recompute_depth > 0 {
    abort(
      "Memo::accumulated_peek is unsupported inside static Derived recompute",
    )
  }
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
/// compute frame on success, and forces verification of `self` via
/// `ensure_computed_untracked`.
///
/// The read channel reports graph mechanism failures as `ReadError`: cycles
/// return `Err(Cycle(_))`, and a directly disposed target memo returns
/// `Err(Disposed(_))`. A target compute that raises `Failure` is a defect and
/// aborts, matching `Derived::read`.
///
/// Disposed accumulators and static-Derived recompute use are programmer
/// defects that raise `Failure`; cross-runtime misuse aborts via the runtime
/// guard rather than surfacing as `ReadError`.
pub fn[T, A] Memo::accumulated(
  self : Memo[T],
  acc : Accumulator[A],
) -> Result[Array[A], ReadError] raise Failure {
  self.rt.check_cross_runtime(self.rt.core.runtime_id, "Memo::accumulated")
  self.rt.check_cross_runtime(
    acc.slot_id.runtime_id,
    "Memo::accumulated (Accumulator)",
  )
  if self.rt.static_recompute_depth > 0 {
    fail("Memo::accumulated is unsupported inside static Derived recompute")
  }
  let slot = self.rt.accumulator_slots[acc.slot_id.id]
  if slot.disposed {
    fail("Memo::accumulated called on disposed Accumulator")
  }
  if self.rt.is_cell_disposed(self.cell_id) {
    return Err(ReadError::disposed(self.cell_id))
  }
  let verified = self.rt.ensure_computed_untracked(self.cell_id) catch {
    e => {
      self.rt.drain_pending_events_direct()
      abort("Memo::accumulated target compute raised: " + e.to_string())
    }
  }
  let result = match verified {
    Err(e) => Err(ReadError::cycle(e))
    Ok(_) => {
      // Stage synthetic read on current frame (if any).
      let current_rev = (slot.push_revised_at_for)(self.cell_id)
      match self.rt.top_active_query() {
        Some(frame) =>
          // Gate on memo-frame check: preserves silent-no-op for push-reactive
          // and effect frames calling accumulated. Inside a memo frame,
          // ensure_for_cell lazy-creates the entry if before_recompute skipped.
          match self.rt.core.cell_index[frame.cell_id.id] {
            PullMemo(_) | HybridMemo(_) =>
              self.rt.accumulator_commit_hook
              .ensure_for_cell(frame.cell_id)
              .ensure_reads()
              .set((acc.slot_id, self.cell_id), current_rev)
            _ => () // non-memo frame (push-reactive/effect) — silent no-op
          }
        None => ()
      }
      // Return defensive copy of buffer.
      let vs = match acc.per_memo.get(self.cell_id) {
        Some(arr) => arr.copy()
        None => []
      }
      Ok(vs)
    }
  }
  if self.rt.has_pending_events() {
    self.rt.drain_pending_events_if_idle()
  }
  result
}

///|
/// Tracked accumulator read that aborts on a graph mechanism failure.
pub fn[T, A] Memo::accumulated_or_abort(
  self : Memo[T],
  acc : Accumulator[A],
) -> Array[A] raise Failure {
  match self.accumulated(acc) {
    Ok(vs) => vs
    Err(e) => abort(e.format_path())
  }
}

///|
/// Compatibility alias for the Result-style accumulator read.
pub fn[T, A] Memo::accumulated_result(
  self : Memo[T],
  acc : Accumulator[A],
) -> Result[Array[A], ReadError] raise Failure {
  self.accumulated(acc)
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
