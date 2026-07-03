///|
/// Whitebox invariant tests for the MemoCommitPhase dispatch contract.
///
/// Three invariants pinned by the T1b refactor:
///   A. Forward dispatch order on both success and abort — hooks fire in
///      registration order; AccumulatorCommitHook is registered first in
///      `Runtime::new`, so any other hook observes its effects.
///   B. Non-memo-frame preservation — when a push reactive's compute
///      reads derived accumulator state, the hook leaves no per-reactive
///      entry behind (the `cell_index` gate in cells/accumulator.mbt).
///   C. Nested recompute correctness — when an inner derived cell aborts during
///      an outer derived cell's recompute, the inner's hook entry is removed
///      before the outer's catch arm fires.

///|
/// Sentinel MemoCommitPhase implementor that records, at each fire,
/// whether the named cell's entry is still in
/// `rt.accumulator_commit_hook.active` (proves the accumulator hook ran
/// first under forward iteration) plus a snapshot of the active map's
/// keys (proves nested lifecycle).
priv struct SentinelHook {
  before_log : Array[(CellId, Bool, Array[CellId])]
  success_log : Array[(CellId, Bool, Array[CellId])]
  abort_log : Array[(CellId, Bool, Array[CellId])]
}

///|
fn SentinelHook::new() -> SentinelHook {
  { before_log: [], success_log: [], abort_log: [] }
}

///|
fn snapshot_active_keys(rt : Runtime) -> Array[CellId] {
  let keys : Array[CellId] = []
  for k, _ in rt.accumulator_commit_hook.active {
    keys.push(k)
  }
  keys
}

///|
fn entry_present(rt : Runtime, cell_id : CellId) -> Bool {
  match rt.accumulator_commit_hook.active.get(cell_id) {
    Some(_) => true
    None => false
  }
}

///|
impl MemoCommitPhase for SentinelHook with fn before_recompute(
  self,
  rt,
  cell_id,
) {
  self.before_log.push(
    (cell_id, entry_present(rt, cell_id), snapshot_active_keys(rt)),
  )
}

///|
impl MemoCommitPhase for SentinelHook with fn after_success(self, rt, cell_id) {
  self.success_log.push(
    (cell_id, entry_present(rt, cell_id), snapshot_active_keys(rt)),
  )
}

///|
impl MemoCommitPhase for SentinelHook with fn after_abort(self, rt, cell_id, _e) {
  self.abort_log.push(
    (cell_id, entry_present(rt, cell_id), snapshot_active_keys(rt)),
  )
}

///|
/// Test A — Dispatch order on success.
/// Sentinel registered after AccumulatorCommitHook observes:
///   - before_recompute: entry present (accumulator installed it first)
///   - after_success:    entry absent  (accumulator removed it first)
test "MemoCommitPhase: forward dispatch order on success" {
  let rt = Runtime::Runtime()
  let sentinel = SentinelHook::new()
  rt.commit_hooks.push(sentinel)
  // Real accumulator slot disables the AccumulatorCommitHook fast-path so
  // entries are actually installed/removed during recompute.
  let acc : Accumulator[Int] = Accumulator::new(rt~)
  let m = Derived(rt, () => {
    acc.push(1)
    42
  })
  ignore(m.read_or_abort())
  let m_id = m.id()
  inspect(sentinel.before_log.length(), content="1")
  inspect(sentinel.before_log[0].0 == m_id, content="true")
  inspect(sentinel.before_log[0].1, content="true")
  inspect(sentinel.success_log.length(), content="1")
  inspect(sentinel.success_log[0].0 == m_id, content="true")
  inspect(sentinel.success_log[0].1, content="false")
  inspect(sentinel.abort_log.length(), content="0")
}

///|
/// Test A — Dispatch order on abort.
/// Uses `Derived::force_recompute` (package-private) to bypass `read`,
/// which would return `Err` on a raised Failure instead of aborting.
test "MemoCommitPhase: forward dispatch order on abort" {
  let rt = Runtime::Runtime()
  let sentinel = SentinelHook::new()
  rt.commit_hooks.push(sentinel)
  let _acc : Accumulator[Int] = Accumulator::new(rt~)
  let m : Derived[Int] = Derived(rt, () => raise Failure("test abort"))
  try m.force_recompute() catch {
    _ => ()
  } noraise {
    _ => ()
  }
  let m_id = m.id()
  inspect(sentinel.before_log.length(), content="1")
  inspect(sentinel.before_log[0].0 == m_id, content="true")
  inspect(sentinel.before_log[0].1, content="true")
  inspect(sentinel.abort_log.length(), content="1")
  inspect(sentinel.abort_log[0].0 == m_id, content="true")
  inspect(sentinel.abort_log[0].1, content="false")
  inspect(sentinel.success_log.length(), content="0")
}

///|
/// Test B — Non-memo-frame preservation.
/// A push Reactive whose compute reads `Memo::accumulated*` must not
/// leave any state keyed by its own cell. The cell_index gate in the
/// accumulator push paths is what enforces the silent no-op.
test "MemoCommitPhase: Memo::accumulated from a reactive frame leaves no entry" {
  let rt = Runtime::Runtime()
  let acc : Accumulator[Int] = Accumulator::new(rt~)
  let m = Derived(rt, () => {
    acc.push(7)
    1
  })
  ignore(m.read_or_abort())
  // EagerDerived::EagerDerived runs the initial compute synchronously inside a
  // PushReactive tracking frame. The accumulator reads should be silent
  // no-ops for the non-memo tracking frame. If misuse errors occur,
  // return Err from `accumulated` and keep the invariant checks focused
  // on hook cleanup behavior.
  let _r = EagerDerived::EagerDerived(rt, () => {
    try m.accumulated(acc) catch {
      _ => ()
    } noraise {
      _ => ()
    }
    try m.accumulated_result(acc) catch {
      _ => ()
    } noraise {
      _ => ()
    }
    0
  })
  inspect(rt.accumulator_commit_hook.active.is_empty(), content="true")
}

///|
/// Test C — Nested recompute correctness.
/// M1 reads M2; M2 aborts. Observed hook sequence:
///   1. before_recompute(m1) — accumulator installs active[m1]
///   2. before_recompute(m2) — accumulator installs active[m2] (nested)
///   3. m2 compute raises
///   4. after_abort(m2)      — accumulator removes active[m2]
///   5. m1 propagates raise
///   6. after_abort(m1)      — accumulator removes active[m1]
/// Sentinel snapshots prove the order: at each abort fire, the
/// just-named entry is already gone and the active map's key set
/// matches the remaining outer-frame depth.
test "MemoCommitPhase: nested recompute aborts clean up both entries" {
  let rt = Runtime::Runtime()
  let sentinel = SentinelHook::new()
  rt.commit_hooks.push(sentinel)
  let _acc : Accumulator[Int] = Accumulator::new(rt~)
  let m2 : Derived[Int] = Derived(rt, () => raise Failure("inner abort"))
  let m1 = Derived(rt, () => {
    let _ = m2.get_result_inner()
    0
  })
  try m1.force_recompute() catch {
    _ => ()
  } noraise {
    _ => ()
  }
  let m1_id = m1.id()
  let m2_id = m2.id()
  inspect(sentinel.before_log.length(), content="2")
  inspect(sentinel.before_log[0].0 == m1_id, content="true")
  inspect(sentinel.before_log[0].2.length(), content="1")
  inspect(sentinel.before_log[1].0 == m2_id, content="true")
  inspect(sentinel.before_log[1].2.length(), content="2")
  inspect(sentinel.abort_log.length(), content="2")
  inspect(sentinel.abort_log[0].0 == m2_id, content="true")
  inspect(sentinel.abort_log[0].1, content="false")
  inspect(sentinel.abort_log[0].2.length(), content="1")
  inspect(sentinel.abort_log[1].0 == m1_id, content="true")
  inspect(sentinel.abort_log[1].1, content="false")
  inspect(sentinel.abort_log[1].2.length(), content="0")
  inspect(rt.accumulator_commit_hook.active.is_empty(), content="true")
  inspect(sentinel.success_log.length(), content="0")
}

///|
/// Test D — Lazy entry creation via `ensure_for_cell`.
/// When `accumulator_slots.is_empty()` at recompute start, the accumulator
/// hook's `before_recompute` fast-path returns without installing an
/// `active[cell_id]` entry. If the recomputing memo then registers an
/// accumulator mid-compute and pushes to it, `Accumulator::push` reaches
/// `ensure_for_cell`, which must lazy-create the entry so `after_success`
/// has staged state to finalize. Verifies the push outcome (peek reads
/// the value back) and that `after_success` cleaned up the lazy entry.
test "MemoCommitPhase: ensure_for_cell lazy-creates entry when fast-path took before_recompute" {
  let rt = Runtime::Runtime()
  // No Accumulator exists at memo construction time → at recompute start,
  // `accumulator_slots.is_empty()` is true and the hook's before_recompute
  // takes its fast-path. The Ref lets the memo's compute register the
  // accumulator on first run and reuse it on subsequent runs.
  let acc_ref : Ref[Accumulator[Int]?] = { val: None }
  let m = Derived(rt, () => {
    let acc = match acc_ref.val {
      Some(a) => a
      None => {
        let a : Accumulator[Int] = Accumulator::new(rt~)
        acc_ref.val = Some(a)
        a
      }
    }
    acc.push(42)
    0
  })
  inspect(rt.accumulator_commit_hook.active.is_empty(), content="true")
  ignore(m.read_or_abort())
  // after_success cleaned up the entry that ensure_for_cell lazy-created
  // during the push.
  inspect(rt.accumulator_commit_hook.active.is_empty(), content="true")
  let acc = match acc_ref.val {
    Some(a) => a
    None => abort("accumulator was not registered during compute")
  }
  // accumulator_contributions[m] now records the lazily-discovered slot,
  // and peek reads back the pushed value.
  match rt.accumulator_contributions.get(m.id()) {
    Some(slots) => inspect(slots.length(), content="1")
    None => abort("no contribution recorded for m")
  }
  let peeked = m.accumulated_peek(acc)
  inspect(peeked.length(), content="1")
  inspect(peeked[0], content="42")
}
