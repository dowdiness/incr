///|
/// Gate microbenchmark for #189 (Incremental TEA vs Rabbita dirty-cell baseline).
///
/// Reproduces the claimed incremental win in isolation BEFORE building the full
/// comparison matrix, per the moonbit-perf-investigation discipline. The claim:
/// incr's verify+backdating model SKIPS the view recompute when the mutated
/// field is not a dependency of the view, whereas a dirty-cell model re-runs
/// view(model) on every change.
///
/// This file is target-agnostic on purpose: it mirrors `CounterApp`'s shape
/// (three `InputField`s, a `Derived` view reading only two of them) using the
/// public `@incr` API plus an observable recompute counter, so it runs on both
/// `--target wasm-gc` (default `moon bench`) and `--target js`. The plain
/// `test` below pins the recompute *count* so the wall-time numbers are
/// interpreted against a mechanically-proven skip.

///|
/// A counter-shaped reactive harness: `count`/`title` are read by the view,
/// `unrelated` is not. `recomputes` counts every view-closure invocation.
priv struct GateHarness {
  runtime : @incr.Runtime
  count : @incr.InputField[Int]
  unrelated : @incr.InputField[Int]
  view_watch : @incr.Watch[CounterView]
  recomputes : Ref[Int]
}

///|
fn GateHarness::GateHarness() -> GateHarness {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="gate.count")
  let title = scope.input_field("Counter", label="gate.title")
  let unrelated = scope.input_field(0, label="gate.unrelated")
  let recomputes = Ref(0)
  let view : () -> CounterView raise Failure = () => {
    recomputes.val = recomputes.val + 1
    { title: title.get(), count: count.get() }
  }
  let view_root = scope.derived(view, label="gate.view")
  let view_watch = scope.add_watch(view_root.watch())
  ignore(view_watch.read_or_abort()) // prime
  { runtime, count, unrelated, view_watch, recomputes }
}

///|
/// Mutates `unrelated` (NOT a view dependency) then reads the view. incr should
/// skip the recompute: `recomputes` stays flat.
fn GateHarness::touch_unread(self : GateHarness, v : Int) -> CounterView {
  self.runtime.batch(() => self.unrelated.set(v))
  self.view_watch.read_or_abort()
}

///|
/// Mutates `count` (a view dependency) then reads the view. incr recomputes.
fn GateHarness::touch_read(self : GateHarness, v : Int) -> CounterView {
  self.runtime.batch(() => self.count.set(v))
  self.view_watch.read_or_abort()
}

///|
/// Mechanical proof of the skip: the wall-time benches above are only meaningful
/// if the unread-field mutation actually avoids the recompute. This pins it.
test "gate: unread-field mutation skips view recompute" {
  let h = GateHarness::GateHarness()
  // After priming, exactly one recompute has happened.
  inspect(h.recomputes.val, content="1")
  // 100 unread-field mutations + reads: recompute count must stay at 1.
  for i in 1..<=100 {
    ignore(h.touch_unread(i))
  }
  inspect(h.recomputes.val, content="1")
  // A single read-relevant mutation forces exactly one recompute.
  ignore(h.touch_read(7))
  inspect(h.recomputes.val, content="2")
  // 100 read-relevant mutations force 100 recomputes (101 total here on).
  for i in 1..<=100 {
    ignore(h.touch_read(i))
  }
  inspect(h.recomputes.val, content="102")
}

///|
/// GATE A — unread-field mutation. Expected: recompute is SKIPPED, so this
/// path's cost is the propagation/verify machinery only (no view re-eval).
test "gate: unread-field mutation (skip recompute)" (b : @bench.T) {
  let h = GateHarness::GateHarness()
  let mut v = 0
  b.bench(() => {
    v = v + 1
    b.keep(h.touch_unread(v))
  })
}

///|
/// GATE B — read-relevant mutation. Expected: recompute RUNS each iteration.
/// The delta vs Gate A at this trivial view size is the whole question: if the
/// view recompute is cheap relative to dispatch/verify, the skip win is small —
/// which is itself the honest finding that motivates the realistic-tree bench.
test "gate: read-relevant mutation (force recompute)" (b : @bench.T) {
  let h = GateHarness::GateHarness()
  let mut v = 0
  b.bench(() => {
    v = v + 1
    b.keep(h.touch_read(v))
  })
}
