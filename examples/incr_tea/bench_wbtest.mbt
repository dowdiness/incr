///|
/// Benchmark matrix for #189 — Incremental TEA vs a modeled dirty-cell baseline.
///
/// Whitebox + `#cfg(target="js")` because the subject under test (`Html`,
/// `plan_keyed_diff`, the keyed-list view builders) is js-gated and `priv`. The
/// DOM applier + listeners need a real `document` and CANNOT run under
/// `moon bench` in Node — those layers are deliberately NOT benchmarked here;
/// see the dated perf doc for that gap. What IS measured are the two PURE layers
/// that carry the incremental story:
///
///   Part 1 — view recompute vs skip. incr's verify+backdating SKIPS the whole
///   view rebuild when the mutated field is not a view dependency; a dirty-cell
///   renderer re-runs view(model) + diffs on EVERY change. Benched as a function
///   of list size N so the win can be read as a scaling curve.
///
///   Part 2 — the keyed planner `plan_keyed_diff` vs a naive positional rebuild
///   (no key reuse). Measures the planner's matching overhead and the reuse it
///   buys (avoided DOM node creations — the DOM-bound benefit itself is not
///   measurable in Node and is noted in the perf doc).
///
/// Fairness note: the incr benches pay the real `runtime.batch` + propagation +
/// `Watch` read overhead; the dirty-cell baseline is pure compute (rebuild +
/// `Eq`) with NO framework bookkeeping. The asymmetry runs AGAINST incr, so the
/// unread-skip win measured below is a conservative lower bound.

// ─── Shared view builders (used by both incr and the dirty-cell baseline) ────

///|
/// Builds N (id, label) item pairs. `id` is the keyed-child key.
#cfg(target="js")
fn bench_make_items(n : Int, tag : String) -> Array[(String, String)] {
  [
    for i in 0..<n => ("item-\{i}", "\{tag} \{i}")
  ]
}

///|
/// Pure keyed-list view: one `<li>` per item, mirroring the demo's list view
/// (a labelled span + an uncontrolled notes input per row). This is the
/// per-change rebuild cost a dirty-cell renderer pays unconditionally and the
/// cost incr pays only when a view dependency actually changed.
#cfg(target="js")
fn bench_list_html(items : Array[(String, String)]) -> Html[RendererMsg] {
  let children = items.map(pair => {
    let (id, label) = pair
    (
      id,
      li(attrs=[class_attr("list-item")], [
        span(attrs=[class_attr("list-label")], [text("\{label} (\{id})")]),
        input(attrs=[class_attr("list-note"), attr("placeholder", "notes")]),
      ]),
    )
  })
  keyed_node("ul", attrs=[class_attr("bench-list")], children)
}

// ─── Part 1a: incr reactive list harness ─────────────────────────────────────

///|
/// A list-shaped reactive component: `items` is read by the view, `unrelated`
/// is not. Mirrors `CounterApp`'s field-level structure at list scale.
#cfg(target="js")
priv struct IncrListHarness {
  runtime : @incr.Runtime
  items : @incr.InputField[Array[(String, String)]]
  unrelated : @incr.InputField[Int]
  view_watch : @incr.Watch[Html[RendererMsg]]
}

///|
#cfg(target="js")
fn IncrListHarness::new(n : Int) -> IncrListHarness {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let items = scope.input_field(
    bench_make_items(n, "Item"),
    label="bench.items",
  )
  let unrelated = scope.input_field(0, label="bench.unrelated")
  let view : () -> Html[RendererMsg] raise Failure = () => {
    bench_list_html(items.get())
  }
  let view_root = scope.derived(view, label="bench.view")
  let view_watch = scope.add_watch(view_root.watch())
  ignore(view_watch.read_or_abort()) // prime
  { runtime, items, unrelated, view_watch }
}

///|
/// Mutates the unread `unrelated` field, then reads the view. incr SKIPS the
/// N-node rebuild (verify finds the view's deps unchanged).
#cfg(target="js")
fn IncrListHarness::touch_unread(
  self : IncrListHarness,
  v : Int,
) -> Html[RendererMsg] {
  self.runtime.batch(() => self.unrelated.set(v))
  self.view_watch.read_or_abort()
}

///|
/// Sets the read `items` field to a (distinct) value, then reads the view.
/// incr REBUILDS the N-node tree because a view dependency changed.
#cfg(target="js")
fn IncrListHarness::touch_read(
  self : IncrListHarness,
  next : Array[(String, String)],
) -> Html[RendererMsg] {
  self.runtime.batch(() => self.items.set(next))
  self.view_watch.read_or_abort()
}

// ─── Part 1b: modeled dirty-cell baseline (re-run view + diff every change) ───

///|
/// A dirty-cell renderer's pure per-change work: on ANY model mutation it
/// re-runs `view(model)` and diffs the new tree against the previous one. It has
/// no dependency graph, so it cannot tell whether the mutated field is in the
/// view — it rebuilds + diffs unconditionally. The `Eq` compare stands in for
/// the VDOM diff that decides whether DOM patches are needed.
///
/// Two frame methods cover the two scenarios head-to-head with incr:
///   `rerender_unchanged` — UNREAD mutation: output is identical, so the diff
///     walks the whole tree and finds nothing (full-walk `Eq`). This is exactly
///     the work incr's verify SKIPS — compare against `touch_unread`.
///   `rerender_changed` — READ mutation: output differs, so the diff exits at
///     the first changed node (early-exit `Eq`). Compare against `touch_read`.
/// (`prev` is reassigned each frame so the rebuild is never hoisted.)
#cfg(target="js")
priv struct DirtyCell {
  arrs : Array[Array[(String, String)]]
  mut parity : Int
  mut prev : Html[RendererMsg]
}

///|
#cfg(target="js")
fn DirtyCell::new(n : Int) -> DirtyCell {
  let a = bench_make_items(n, "Item")
  let b = bench_make_items(n, "Alt")
  { arrs: [a, b], parity: 0, prev: bench_list_html(a) }
}

///|
/// Unread-mutation frame: rebuild from the same model, diff (full walk, finds
/// nothing), keep. Returns whether the diff found a change (always false).
#cfg(target="js")
fn DirtyCell::rerender_unchanged(self : DirtyCell) -> Bool {
  let next = bench_list_html(self.arrs[0])
  let changed = self.prev != next
  self.prev = next
  changed
}

///|
/// Read-mutation frame: toggle the model so the output changes, rebuild, diff
/// (early exit at the first changed node), keep. Returns true.
#cfg(target="js")
fn DirtyCell::rerender_changed(self : DirtyCell) -> Bool {
  self.parity = (self.parity + 1) % 2
  let next = bench_list_html(self.arrs[self.parity])
  let changed = self.prev != next
  self.prev = next
  changed
}

// ─── Part 1 benches: N = 16 / 64 / 256 ───────────────────────────────────────
//
// Read each triple together:
//   incr unread skip  — O(1), independent of N (the win)
//   incr read rebuild — O(N), incr pays the rebuild only on a relevant change
//   dirty-cell rerender — O(N) on EVERY change, read or unread (the baseline)

///|
#cfg(target="js")
test "list N=16: incr unread-field mutation (skip rebuild)" (b : @bench.T) {
  let h = IncrListHarness::new(16)
  let mut v = 0
  b.bench(() => {
    v = v + 1
    b.keep(h.touch_unread(v))
  })
}

///|
#cfg(target="js")
test "list N=16: incr read-relevant mutation (rebuild)" (b : @bench.T) {
  let h = IncrListHarness::new(16)
  let a = bench_make_items(16, "Item")
  let b2 = bench_make_items(16, "Alt")
  let arrs = [a, b2]
  let mut v = 0
  b.bench(() => {
    v = v + 1
    b.keep(h.touch_read(arrs[v % 2]))
  })
}

///|
#cfg(target="js")
test "list N=16: dirty-cell unread mutation (rebuild + full-walk diff)" (
  b : @bench.T,
) {
  let dc = DirtyCell::new(16)
  b.bench(() => b.keep(dc.rerender_unchanged()))
}

///|
#cfg(target="js")
test "list N=16: dirty-cell read mutation (rebuild + early-exit diff)" (
  b : @bench.T,
) {
  let dc = DirtyCell::new(16)
  b.bench(() => b.keep(dc.rerender_changed()))
}

///|
#cfg(target="js")
test "list N=64: incr unread-field mutation (skip rebuild)" (b : @bench.T) {
  let h = IncrListHarness::new(64)
  let mut v = 0
  b.bench(() => {
    v = v + 1
    b.keep(h.touch_unread(v))
  })
}

///|
#cfg(target="js")
test "list N=64: incr read-relevant mutation (rebuild)" (b : @bench.T) {
  let h = IncrListHarness::new(64)
  let arrs = [bench_make_items(64, "Item"), bench_make_items(64, "Alt")]
  let mut v = 0
  b.bench(() => {
    v = v + 1
    b.keep(h.touch_read(arrs[v % 2]))
  })
}

///|
#cfg(target="js")
test "list N=64: dirty-cell unread mutation (rebuild + full-walk diff)" (
  b : @bench.T,
) {
  let dc = DirtyCell::new(64)
  b.bench(() => b.keep(dc.rerender_unchanged()))
}

///|
#cfg(target="js")
test "list N=64: dirty-cell read mutation (rebuild + early-exit diff)" (
  b : @bench.T,
) {
  let dc = DirtyCell::new(64)
  b.bench(() => b.keep(dc.rerender_changed()))
}

///|
#cfg(target="js")
test "list N=256: incr unread-field mutation (skip rebuild)" (b : @bench.T) {
  let h = IncrListHarness::new(256)
  let mut v = 0
  b.bench(() => {
    v = v + 1
    b.keep(h.touch_unread(v))
  })
}

///|
#cfg(target="js")
test "list N=256: incr read-relevant mutation (rebuild)" (b : @bench.T) {
  let h = IncrListHarness::new(256)
  let arrs = [bench_make_items(256, "Item"), bench_make_items(256, "Alt")]
  let mut v = 0
  b.bench(() => {
    v = v + 1
    b.keep(h.touch_read(arrs[v % 2]))
  })
}

///|
#cfg(target="js")
test "list N=256: dirty-cell unread mutation (rebuild + full-walk diff)" (
  b : @bench.T,
) {
  let dc = DirtyCell::new(256)
  b.bench(() => b.keep(dc.rerender_unchanged()))
}

///|
#cfg(target="js")
test "list N=256: dirty-cell read mutation (rebuild + early-exit diff)" (
  b : @bench.T,
) {
  let dc = DirtyCell::new(256)
  b.bench(() => b.keep(dc.rerender_changed()))
}

// ─── Part 2: keyed planner vs naive positional rebuild ───────────────────────

///|
/// Naive positional reconciliation: no keys, so no node is reused. Every new
/// slot is a fresh create (`None`) and every old slot is detached. This is the
/// floor the keyed planner is measured against — its construction is O(new_len)
/// with zero matching work, but it buys zero DOM reuse.
#cfg(target="js")
fn naive_positional_plan(old_len : Int, new_len : Int) -> KeyedPlan {
  let steps : Array[Int?] = Array::make(new_len, None)
  let removals = [ for i in 0..<old_len => i ]
  { steps, removals }
}

///|
#cfg(target="js")
fn bench_keys(n : Int) -> Array[String] {
  [
    for i in 0..<n => "item-\{i}"
  ]
}

///|
/// Reverse = full reorder: every new key matches an old key, so the planner
/// reuses all N nodes (0 DOM creations). This was the old consumed-prefix
/// scanner's worst case; after #241, N=256 measured 127.49 → 17.10 µs.
#cfg(target="js")
test "planner N=16: reverse (full reorder, all reuse)" (b : @bench.T) {
  let old_keys = bench_keys(16)
  let new_keys = old_keys.rev()
  b.bench(() => b.keep(plan_keyed_diff(old_keys, new_keys)))
}

///|
#cfg(target="js")
test "planner N=64: reverse (full reorder, all reuse)" (b : @bench.T) {
  let old_keys = bench_keys(64)
  let new_keys = old_keys.rev()
  b.bench(() => b.keep(plan_keyed_diff(old_keys, new_keys)))
}

///|
#cfg(target="js")
test "planner N=256: reverse (full reorder, all reuse)" (b : @bench.T) {
  let old_keys = bench_keys(256)
  let new_keys = old_keys.rev()
  b.bench(() => b.keep(plan_keyed_diff(old_keys, new_keys)))
}

///|
/// Prepend one new key: N reuses + 1 create. The new head misses; every
/// survivor at N=64/256 hits the duplicate-free key-map path. Map setup is near
/// break-even at N=64, but N=256 measured 51.29 → 17.63 µs.
#cfg(target="js")
test "planner N=16: prepend one (N reuse, 1 create)" (b : @bench.T) {
  let old_keys = bench_keys(16)
  let new_keys = ["item-new", ..old_keys]
  b.bench(() => b.keep(plan_keyed_diff(old_keys, new_keys)))
}

///|
#cfg(target="js")
test "planner N=64: prepend one (N reuse, 1 create)" (b : @bench.T) {
  let old_keys = bench_keys(64)
  let new_keys = ["item-new", ..old_keys]
  b.bench(() => b.keep(plan_keyed_diff(old_keys, new_keys)))
}

///|
#cfg(target="js")
test "planner N=256: prepend one (N reuse, 1 create)" (b : @bench.T) {
  let old_keys = bench_keys(256)
  let new_keys = ["item-new", ..old_keys]
  b.bench(() => b.keep(plan_keyed_diff(old_keys, new_keys)))
}

///|
/// Unchanged list: the most reuse-favorable input. The key-map fast path avoids
/// the old consumed-prefix re-scan; N=256 measured 52.31 → 19.69 µs.
#cfg(target="js")
test "planner N=256: unchanged (all reuse, key-map fast path)" (b : @bench.T) {
  let old_keys = bench_keys(256)
  let new_keys = bench_keys(256)
  b.bench(() => b.keep(plan_keyed_diff(old_keys, new_keys)))
}

///|
/// Naive positional floor at the largest N: array fill, no matching.
#cfg(target="js")
test "naive positional N=256: rebuild plan (no reuse)" (b : @bench.T) {
  b.bench(() => b.keep(naive_positional_plan(256, 256)))
}

// ─── Part 2 reuse-count assertions (the benefit the runtime cost buys) ───────

///|
/// Quantifies the DOM work the planner saves vs naive positional. The planner's
/// matching CPU (Part 2 benches) is the price; these counts are what it buys.
#cfg(target="js")
test "planner reuse counts: reverse and prepend reuse vs naive all-create" {
  let keys = bench_keys(64)
  // Reverse: planner reuses all 64 nodes, creates 0.
  let rev_plan = plan_keyed_diff(keys, keys.rev())
  let rev_reused = rev_plan.steps.filter(s => s is Some(_)).length()
  let rev_created = rev_plan.steps.filter(s => s is None).length()
  inspect(rev_reused, content="64")
  inspect(rev_created, content="0")
  inspect(rev_plan.removals.length(), content="0")
  // Prepend one: planner reuses all 64, creates 1.
  let pre_plan = plan_keyed_diff(keys, ["item-new", ..keys])
  let pre_reused = pre_plan.steps.filter(s => s is Some(_)).length()
  let pre_created = pre_plan.steps.filter(s => s is None).length()
  inspect(pre_reused, content="64")
  inspect(pre_created, content="1")
  // Naive positional for the same reverse: reuses 0, creates all 64, detaches 64.
  let naive = naive_positional_plan(64, 64)
  let naive_reused = naive.steps.filter(s => s is Some(_)).length()
  inspect(naive_reused, content="0")
  inspect(naive.steps.length(), content="64")
  inspect(naive.removals.length(), content="64")
}

///|
/// The reuse pattern is structural (N-independent), but the perf doc's
/// cost/benefit tradeoff cites these counts against the N=256 runtime rows, so
/// they are pinned at N=256 too rather than extrapolated from N=64.
#cfg(target="js")
test "planner reuse counts at N=256: reverse and prepend reuse vs naive" {
  let keys = bench_keys(256)
  // Reverse: 256 reused, 0 created, 0 detached.
  let rev_plan = plan_keyed_diff(keys, keys.rev())
  inspect(rev_plan.steps.filter(s => s is Some(_)).length(), content="256")
  inspect(rev_plan.steps.filter(s => s is None).length(), content="0")
  inspect(rev_plan.removals.length(), content="0")
  // Prepend one (old_len=256, new_len=257): 256 reused, 1 created.
  let pre_plan = plan_keyed_diff(keys, ["item-new", ..keys])
  inspect(pre_plan.steps.length(), content="257")
  inspect(pre_plan.steps.filter(s => s is Some(_)).length(), content="256")
  inspect(pre_plan.steps.filter(s => s is None).length(), content="1")
  // Naive positional: 0 reused, 256 created, 256 detached.
  let naive = naive_positional_plan(256, 256)
  inspect(naive.steps.filter(s => s is Some(_)).length(), content="0")
  inspect(naive.steps.length(), content="256")
  inspect(naive.removals.length(), content="256")
}
