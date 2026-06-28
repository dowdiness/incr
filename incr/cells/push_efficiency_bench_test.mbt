///|
/// Baseline: input with N reachable derived subscribers, no push nodes anywhere.
/// node_count == 0 → push_propagate_from is skipped entirely by the existing
/// node_count gate before the per-source push_reachable_count gate is reached.
test "push efficiency: input set, 100 reachable derived subs, no push nodes (baseline)" (
  b : @bench.T,
) {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let multiplier = i + 1
    let rd = ReachableDerived::ReachableDerived(rt, () => s.get() * multiplier)
    ignore(rd.read_or_abort())
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    s.set(v)
  })
}

///|
/// Mixed graph: same input + reachable derived fan-out, but a distant reactive
/// on a separate input keeps node_count > 0. Without this PR,
/// push_propagate_from BFS would traverse all 100 reachable derived subscribers
/// of s finding no push node — the unnecessary traversal. With this PR, the
/// per-source push_reachable_count gate in enqueue_push_subscribers skips the
/// reachable derived subscriber walk entirely for s (its count is 0).
test "push efficiency: input set, 100 reachable derived subs, distant reactive (mixed)" (
  b : @bench.T,
) {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let multiplier = i + 1
    let rd = ReachableDerived::ReachableDerived(rt, () => s.get() * multiplier)
    ignore(rd.read_or_abort())
  }
  let s2 = Input::Input(rt, 0)
  let _r = Reactive::new(rt, () => s2.get() + 1)
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    s.set(v)
  })
}

///|
/// Scale: 1000 reachable derived subscribers, distant reactive.
test "push efficiency: input set, 1000 reachable derived subs, distant reactive (mixed)" (
  b : @bench.T,
) {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  for i = 0; i < 1000; i = i + 1 {
    let multiplier = i + 1
    let rd = ReachableDerived::ReachableDerived(rt, () => s.get() * multiplier)
    ignore(rd.read_or_abort())
  }
  let s2 = Input::Input(rt, 0)
  let _r = Reactive::new(rt, () => s2.get() + 1)
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    s.set(v)
  })
}
