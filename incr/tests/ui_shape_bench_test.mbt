///|
/// One-shot UI-workload investigation (2026-05-18).
///
/// Purpose: validate / refute the claim that incr's push engine — tuned for
/// parser-shaped workloads — can drive a UI-library tree of ~1000 nodes
/// at 60 Hz (16.67 ms / frame budget).
///
/// Five benchmark scenarios:
///  - flat:    1 Input → N Reactives (N ∈ {100, 1000})
///  - layered: Input → 1 Memo (derived state) → 1000 Reactives (DOM-writing
///             effects). Closest analogue to a component tree where leaves
///             react to a memoized projection of root state.
///  - sparse:  1000 Reactives total but only 10 subscribed to the mutated
///             input — the typical per-frame case (hover/scroll).
///  - tree:    balanced binary tree of 1023 Memos (depth 10) with a
///             EagerDerived at each of the 512 deepest nodes.
///
/// Each bench measures one "root input mutation" — the worst-case UI event
/// (router change, theme switch, store-wide update). Subscription patterns
/// matter more than total cell count: see `flat 1000, sparse subscription`
/// for the typical hover/scroll case where 1000 cells exist but only a few
/// depend on the mutated input.
///
test "ui: flat 100 reactives (root mutation)" (b : @bench.T) {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 0)
  let reactives : Array[@incr.EagerDerived[Int]] = []
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    reactives.push(
      @incr.EagerDerived::EagerDerived(rt, fn() { sig.get() + idx }),
    )
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
  })
  ignore(reactives)
}

///|
test "ui: flat 1000 reactives (root mutation)" (b : @bench.T) {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 0)
  let reactives : Array[@incr.EagerDerived[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let idx = i
    reactives.push(
      @incr.EagerDerived::EagerDerived(rt, fn() { sig.get() + idx }),
    )
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
  })
  ignore(reactives)
}

///|
/// Realistic UI shape: state → derived → effect.
/// 1000 leaf Reactives each read a single shared Memo (a derived value
/// computed once from the root input). Mirrors a component tree where
/// children consume a Context-style selector.
test "ui: layered 1000 reactives via 1 memo (root mutation)" (b : @bench.T) {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 0)
  let derived = @incr.Derived::Derived(rt, fn() { sig.get() * 2 })
  let reactives : Array[@incr.EagerDerived[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let idx = i
    reactives.push(
      @incr.EagerDerived::EagerDerived(rt, fn() { derived.get_or_abort() + idx }),
    )
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
  })
  ignore(reactives)
}

///|
/// Sparse subscription: 1000 reactives exist (the rest of the app's UI tree)
/// but only 10 actually depend on the mutated input. This is the typical
/// per-frame case — hover state, scroll position, single-component local
/// state. Total cell population should be amortized; only the live
/// subscription set should cost.
test "ui: flat 1000 reactives, only 10 subscribed (sparse mutation)" (
  b : @bench.T,
) {
  let rt = @incr.Runtime()
  let hot_sig = @incr.Input(rt, 0)
  let cold_sig = @incr.Input(rt, 0)
  let reactives : Array[@incr.EagerDerived[Int]] = []
  // 10 reactives subscribed to the hot input
  for i = 0; i < 10; i = i + 1 {
    let idx = i
    reactives.push(
      @incr.EagerDerived::EagerDerived(rt, fn() { hot_sig.get() + idx }),
    )
  }
  // 990 reactives subscribed to an unrelated cold input (other UI state)
  for i = 0; i < 990; i = i + 1 {
    let idx = i
    reactives.push(
      @incr.EagerDerived::EagerDerived(rt, fn() { cold_sig.get() + idx }),
    )
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    hot_sig.set(v)
  })
  ignore(reactives)
}

///|
/// Tree shape: balanced binary tree of 1023 Memos (depth 10) with a
/// EagerDerived at each of the 512 deepest nodes. Each non-root Memo depends
/// on its parent — analogue of a component tree where each component
/// reads its own slice of props derived from a parent's projection.
/// Memos are used for the interior because EagerDerived cannot be `.get()`-ed
/// from a downstream cell; the leaf Reactives represent "DOM updates."
test "ui: tree 1023 memos + 512 leaf reactives (root mutation)" (b : @bench.T) {
  let rt = @incr.Runtime()
  let sig = @incr.Input(rt, 0)
  // Build balanced binary tree of Memos, 1023 nodes total (depth 10)
  let nodes : Array[@incr.Derived[Int]] = []
  nodes.push(@incr.Derived::Derived(rt, fn() { sig.get() })) // root @ idx 0
  for i = 0; i < 511; i = i + 1 {
    let parent = nodes[i]
    let li = 2 * i + 1
    let ri = 2 * i + 2
    nodes.push(@incr.Derived::Derived(rt, fn() { parent.get_or_abort() + li }))
    nodes.push(@incr.Derived::Derived(rt, fn() { parent.get_or_abort() + ri }))
  }
  // Attach a leaf EagerDerived to each of the 512 deepest nodes (indices 511..1022)
  let leaves : Array[@incr.EagerDerived[Int]] = []
  for i = 511; i < 1023; i = i + 1 {
    let node = nodes[i]
    leaves.push(
      @incr.EagerDerived::EagerDerived(rt, fn() { node.get_or_abort() }),
    )
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
  })
  ignore(leaves)
}
