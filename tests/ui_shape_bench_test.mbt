///|
/// One-shot UI-workload investigation (2026-05-18).
///
/// Purpose: validate / refute the claim that incr's push engine — tuned for
/// parser-shaped workloads — can drive a UI-library tree of ~1000 nodes
/// at 60 Hz (16.67 ms / frame budget).
///
/// Three shapes per size N ∈ {100, 1000}:
///  - flat:   1 Signal → N Reactives (every leaf depends on root state)
///  - tree:   balanced binary tree of Reactives, N total nodes, depth ~log2(N)
///  - layered: Signal → 1 Memo (derived state) → N Reactives (DOM-writing
///             effects). Closest analogue to a component tree where leaves
///             react to a memoized projection of root state.
///
/// Each bench measures one "root signal mutation" — the worst-case UI event
/// (router change, theme switch, store-wide update). Subscription patterns
/// matter more than total cell count: see `flat 1000, sparse subscription`
/// for the typical hover/scroll case where 1000 cells exist but only a few
/// depend on the mutated signal.
///
test "ui: flat 100 reactives (root mutation)" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 0)
  let reactives : Array[@incr.Reactive[Int]] = []
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    reactives.push(@incr.Reactive::new(rt, fn() { sig.get() + idx }))
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
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 0)
  let reactives : Array[@incr.Reactive[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let idx = i
    reactives.push(@incr.Reactive::new(rt, fn() { sig.get() + idx }))
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
/// computed once from the root signal). Mirrors a component tree where
/// children consume a Context-style selector.
test "ui: layered 1000 reactives via 1 memo (root mutation)" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 0)
  let derived = @incr.Memo::new(rt, fn() { sig.get() * 2 })
  let reactives : Array[@incr.Reactive[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let idx = i
    reactives.push(@incr.Reactive::new(rt, fn() { rt.read(derived) + idx }))
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
/// but only 10 actually depend on the mutated signal. This is the typical
/// per-frame case — hover state, scroll position, single-component local
/// state. Total cell population should be amortized; only the live
/// subscription set should cost.
test "ui: flat 1000 reactives, only 10 subscribed (sparse mutation)" (
  b : @bench.T,
) {
  let rt = @incr.Runtime::new()
  let hot_sig = @incr.Signal::new(rt, 0)
  let cold_sig = @incr.Signal::new(rt, 0)
  let reactives : Array[@incr.Reactive[Int]] = []
  // 10 reactives subscribed to the hot signal
  for i = 0; i < 10; i = i + 1 {
    let idx = i
    reactives.push(@incr.Reactive::new(rt, fn() { hot_sig.get() + idx }))
  }
  // 990 reactives subscribed to an unrelated cold signal (other UI state)
  for i = 0; i < 990; i = i + 1 {
    let idx = i
    reactives.push(@incr.Reactive::new(rt, fn() { cold_sig.get() + idx }))
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    hot_sig.set(v)
  })
  ignore(reactives)
}

///|
/// Tree shape: balanced binary tree of 1023 Reactives (depth 10).
/// Each non-root node depends on its parent via a chained Reactive — a
/// closer analogue to a component tree where each component reads its
/// own slice of props derived from a parent's projection.
///
/// Note: this requires a Memo bridge because Reactive cannot be `.get()`-ed.
/// We build the tree of Memos (which can be both subscribed to and read)
/// and put a leaf Reactive at the bottom of each path to capture "DOM
/// updates."
test "ui: tree 1023 memos + 512 leaf reactives (root mutation)" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 0)
  // Build balanced binary tree of Memos, 1023 nodes total (depth 10)
  let nodes : Array[@incr.Memo[Int]] = []
  nodes.push(@incr.Memo::new(rt, fn() { sig.get() })) // root @ idx 0
  for i = 0; i < 511; i = i + 1 {
    let parent = nodes[i]
    let li = 2 * i + 1
    let ri = 2 * i + 2
    nodes.push(@incr.Memo::new(rt, fn() { rt.read(parent) + li }))
    nodes.push(@incr.Memo::new(rt, fn() { rt.read(parent) + ri }))
  }
  // Attach a leaf Reactive to each of the 512 deepest nodes (indices 511..1022)
  let leaves : Array[@incr.Reactive[Int]] = []
  for i = 511; i < 1023; i = i + 1 {
    let node = nodes[i]
    leaves.push(@incr.Reactive::new(rt, fn() { rt.read(node) }))
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
  })
  ignore(leaves)
}
