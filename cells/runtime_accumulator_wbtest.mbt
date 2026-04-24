///|
test "ensure_computed_untracked: first-read on never-computed memo triggers compute" {
  let rt = Runtime::new()
  let signal = Signal::new(rt, 7)
  let mut compute_count = 0
  let memo = Memo::new(rt, () => {
    compute_count = compute_count + 1
    signal.get() * 2
  })
  let data = rt.get_memo_data(memo.id())
  // Fresh memo has never been computed.
  inspect(data.verified_at == Revision::initial(), content="true")
  // Note: `compute_count` will only hold 1 after ensure fires the first
  // compute — on a fresh runtime verify has nothing to do, so the plan's
  // `data.compute()` branch is the interesting one.
  let _ = rt.ensure_computed_untracked(memo.id())
  inspect(compute_count, content="1")
  // Second call should not re-run the closure (pull_verify branch sees fresh).
  let _ = rt.ensure_computed_untracked(memo.id())
  inspect(compute_count, content="1")
}

///|
test "ensure_computed_untracked: does not record ordinary dep on caller frame" {
  let rt = Runtime::new()
  let signal = Signal::new(rt, 1)
  let inner = Memo::new(rt, () => signal.get() * 10)
  // Pre-compute inner outside tracking.
  let _ = rt.ensure_computed_untracked(inner.id())

  // Outer memo calls ensure_computed_untracked on inner but must NOT
  // record inner as an ordinary dep.
  let outer = Memo::new(rt, () => {
    let _ = rt.ensure_computed_untracked(inner.id())
    42
  })
  let _ = outer.observe().get()
  let outer_data = rt.get_memo_data(outer.id())
  inspect(outer_data.dependencies.contains(inner.id()), content="false")
}

///|
/// Pins that `Runtime::slot_snapshots()` returns a live view of
/// `accumulator_slots`: the cached `&SlotSnapshot` entries are references
/// (not value copies), so mutation of the underlying `SlotMeta` is
/// observable through the trait object. Stage 3 kernel-side verify code
/// relies on this aliasing.
test "slot_snapshots: cache observes SlotMeta mutation" {
  let rt = Runtime::new()
  let acc : Accumulator[Int] = Accumulator::new(rt~)
  let snaps = rt.slot_snapshots()
  inspect(snaps.length(), content="1")
  inspect(snaps[0].disposed(), content="false")
  acc.dispose()
  // Same trait-object entry must now reflect disposed=true.
  inspect(snaps[0].disposed(), content="true")
  // Index stays stable post-dispose (monotonic, no reuse).
  inspect(rt.slot_snapshots().length(), content="1")
}

///|
/// Exercises `SlotSnapshot::push_revised_at_for` through the trait
/// dispatch path (not the concrete `SlotMeta.push_revised_at_for`
/// closure field). Pins Codex correction #1: the parenthesised
/// `(self.push_revised_at_for)(cell_id)` in the impl body is genuinely
/// non-recursive — without parens MoonBit would parse it as a call to
/// the trait method itself and infinite-loop. If this test returns
/// (with any Revision value), the parens-wrap held.
test "slot_snapshots: push_revised_at_for via trait dispatch is non-recursive" {
  let rt = Runtime::new()
  let _acc : Accumulator[Int] = Accumulator::new(rt~)
  let snaps = rt.slot_snapshots()
  let some_cell : @incr_types.CellId = { runtime_id: 0, id: 0 }
  // No memo has pushed to this slot, so the slot's push_revised_at map
  // has no entry for any cell — the closure returns Revision::initial().
  let rev = snaps[0].push_revised_at_for(some_cell)
  inspect(rev == Revision::initial(), content="true")
}

///|
/// Pins that `register_accumulator_slot` keeps the two arrays
/// index-aligned and that the invariant check is invoked.
test "slot_snapshots: invariant holds across multiple registrations" {
  let rt = Runtime::new()
  let _a : Accumulator[Int] = Accumulator::new(rt~)
  rt.check_accumulator_cache_invariant()
  let _b : Accumulator[String] = Accumulator::new(rt~)
  rt.check_accumulator_cache_invariant()
  let _c : Accumulator[Int] = Accumulator::new(rt~)
  rt.check_accumulator_cache_invariant()
  inspect(rt.slot_snapshots().length(), content="3")
}
