///|
/// Baseline: signal with N hybrid memo subscribers, no push nodes anywhere.
/// node_count == 0 → push_propagate_from is skipped by the O(1) gate.
test "push efficiency: signal set, 100 hybrid subs, no push nodes (baseline)" (
  b : @bench.T,
) {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let multiplier = i + 1
    let h = HybridMemo::new(rt, () => s.get() * multiplier)
    ignore(h.get())
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    s.set(v)
  })
}

///|
/// Mixed graph: same signal + hybrid memo fan-out, but a distant reactive
/// on a separate signal keeps node_count > 0.
/// push_propagate_from BFS traverses all 100 hybrid subscribers, finds no
/// push node downstream of s — the claimed unnecessary traversal.
test "push efficiency: signal set, 100 hybrid subs, distant reactive (mixed)" (
  b : @bench.T,
) {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let multiplier = i + 1
    let h = HybridMemo::new(rt, () => s.get() * multiplier)
    ignore(h.get())
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
    ignore(h.get())
  }
  let s2 = Signal::new(rt, 0)
  let _r = Reactive::new(rt, () => s2.get() + 1)
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    s.set(v)
  })
}
