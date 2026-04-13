///|
/// Baseline: signal with N hybrid memo subscribers, no push nodes anywhere.
/// node_count == 0 → push_propagate_from is skipped entirely by the existing
/// node_count gate before the per-source push_reachable_count gate is reached.
test "push efficiency: signal set, 100 hybrid subs, no push nodes (baseline)" (
  b : @bench.T,
) {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let multiplier = i + 1
    let h = HybridMemo::new(rt, () => s.get() * multiplier)
    ignore(rt.read_hybrid(h))
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    s.set(v)
  })
}

///|
/// Mixed graph: same signal + hybrid memo fan-out, but a distant reactive
/// on a separate signal keeps node_count > 0. Without this PR,
/// push_propagate_from BFS would traverse all 100 hybrid memo subscribers of
/// s finding no push node — the unnecessary traversal. With this PR, the
/// per-source push_reachable_count gate in enqueue_push_subscribers skips the
/// hybrid memo subscriber walk entirely for s (its count is 0).
test "push efficiency: signal set, 100 hybrid subs, distant reactive (mixed)" (
  b : @bench.T,
) {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let multiplier = i + 1
    let h = HybridMemo::new(rt, () => s.get() * multiplier)
    ignore(rt.read_hybrid(h))
  }
  let s2 = Signal::new(rt, 0)
  let _r = Reactive::new(rt, () => s2.get() + 1)
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    s.set(v)
  })
}

///|
/// Scale: 1000 hybrid subscribers, distant reactive.
test "push efficiency: signal set, 1000 hybrid subs, distant reactive (mixed)" (
  b : @bench.T,
) {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  for i = 0; i < 1000; i = i + 1 {
    let multiplier = i + 1
    let h = HybridMemo::new(rt, () => s.get() * multiplier)
    ignore(rt.read_hybrid(h))
  }
  let s2 = Signal::new(rt, 0)
  let _r = Reactive::new(rt, () => s2.get() + 1)
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    s.set(v)
  })
}
