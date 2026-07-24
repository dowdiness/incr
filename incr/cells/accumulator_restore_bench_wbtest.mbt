///|
/// Microbenchmark for `AccumulatorCommitHook::after_abort`.
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
/// `AccumulatorCommitHook::after_abort` is invoked directly with a
/// manually populated RecomputeState. Public abort path can't be benched
/// because `Memo::get_result` converts compute-Failure into a hard
/// `abort` at the API boundary.
///
/// Whitebox: depends on `AccumulatorCommitHook`, `RecomputeState`, and
/// the typed `rt.accumulator_commit_hook` field.

///|
fn bench_restore(b : @bench.T, n : Int) -> Unit {
  let rt = Runtime::Runtime()
  // Two disjoint sets of accumulators.
  let prev_accs : Array[Accumulator[Int]] = []
  let touched_accs : Array[Accumulator[Int]] = []
  for _ in 0..<n {
    prev_accs.push(Accumulator(rt))
    touched_accs.push(Accumulator(rt))
  }
  // Prime: run a memo that pushes to all prev accumulators so that
  // every prev slot has a real per_memo[cell_id] buffer to restore.
  let m = Derived(rt, () => {
    for acc in prev_accs {
      acc.push(1)
    }
    0
  })
  ignore(m.read_or_abort())
  let prev_ids = prev_accs.map(fn(a) { a.id() })
  let touched_ids = touched_accs.map(fn(a) { a.id() })
  let m_id = m.id()
  let abort_error : Error = fail("bench abort") catch { e => e }
  b.bench(fn() {
    // Set up the hook entry directly (bypasses before_recompute, which would
    // snapshot prev buffers — bench measures the restore path, not snapshot).
    let touched : @hashset.HashSet[@incr_types.AccumulatorId] = @hashset.HashSet([],
    )
    for tid in touched_ids {
      touched.add(tid)
    }
    let state : RecomputeState = {
      prev_contributions: prev_ids,
      touched: Some(touched),
      reads: None,
    }
    rt.accumulator_commit_hook.active.set(m_id, state)
    MemoCommitPhase::after_abort(
      rt.accumulator_commit_hook,
      rt,
      m_id,
      abort_error,
    )
    // after_abort removed active[m_id]; next iteration repopulates.
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
