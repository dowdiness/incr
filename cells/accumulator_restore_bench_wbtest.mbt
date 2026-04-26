///|
/// Microbenchmark for `memo_restore_on_abort` (cells/accumulator.mbt:277).
///
/// Validates the open performance TODO: the inner `for p in
/// prev_contributions` linear scan during `touched` iteration is
/// O(|touched| × |prev|). The TODO claims this is negligible at
/// single-digit accumulator counts. This bench checks that across
/// N = 5 / 20 / 100, with `prev` and `touched` disjoint (worst case
/// for the inner scan: every iteration walks the full `prev` array
/// before invoking `clear_new_run_buffer`).
///
/// Setup: N "prev" accumulators primed via a successful memo run, then
/// the same memo's tracking frame is re-entered manually with N
/// "touched" accumulator ids stuffed into `touched_accumulator_slots`,
/// and `memo_restore_on_abort` is invoked directly. Public abort path
/// can't be benched because `Memo::get_result` converts compute-Failure
/// into a hard `abort` at the API boundary.
///
/// Whitebox: depends on package-private `memo_restore_on_abort`,
/// `begin_tracking`, `pop_tracking_full` and on `pub(all)` field
/// `ActiveQuery.touched_accumulator_slots`.

///|
fn bench_restore(b : @bench.T, n : Int) -> Unit {
  let rt = Runtime::new()
  // Two disjoint sets of accumulators.
  let prev_accs : Array[Accumulator[Int]] = []
  let touched_accs : Array[Accumulator[Int]] = []
  for _ in 0..<n {
    prev_accs.push(Accumulator::new(rt~))
    touched_accs.push(Accumulator::new(rt~))
  }
  // Prime: run a memo that pushes to all prev accumulators so that
  // every prev slot has a real per_memo[cell_id] buffer to restore.
  let m = Memo::new(rt, () => {
    for acc in prev_accs {
      acc.push(1)
    }
    0
  })
  ignore(rt.read(m))
  let prev_ids = prev_accs.map(fn(a) { a.id() })
  let touched_ids = touched_accs.map(fn(a) { a.id() })
  // Each iteration: re-enter the memo's tracking frame, populate the
  // touched set with the disjoint accumulator ids, run the function
  // under test, then pop the frame to restore baseline.
  let m_id = m.id()
  b.bench(fn() {
    Runtime::begin_tracking(rt, m_id)
    match @kernel.top_active_query(rt.core) {
      Some(q) =>
        for tid in touched_ids {
          q.touched_accumulator_slots.add(tid)
        }
      None =>
        abort("bench setup: tracking frame not present after begin_tracking")
    }
    memo_restore_on_abort(rt, m_id, prev_ids)
    let _ = Runtime::pop_tracking_full(rt)
  })
}

///|
test "accumulator restore on abort: N=5 (claimed negligible)" (b : @bench.T) {
  bench_restore(b, 5)
}

///|
test "accumulator restore on abort: N=20 (medium driver load)" (b : @bench.T) {
  bench_restore(b, 20)
}

///|
test "accumulator restore on abort: N=100 (worst case)" (b : @bench.T) {
  bench_restore(b, 100)
}
