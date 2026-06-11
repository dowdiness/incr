# Incremental TEA vs dirty-cell baseline — 2026-06-10

Closes the measurement half of [#189]: benchmark the Incremental TEA renderer
prototype (`examples/incr_tea`) against a dirty-cell ("re-run view + diff")
baseline, to locate where incr's verify + backdating recompute model wins and
where it does not. **This is a measurement, not an optimization** — no renderer
code was changed; the keyed diff + event payloads landed in #211 (PR #240) and
are the subject under test as-is.

## Environment

| | |
|---|---|
| Date | 2026-06-10 |
| CPU | AMD Ryzen 7 6800H (WSL2) |
| Toolchain | moon 0.1.20260608 |
| Reactive engine | `dowdiness/incr@0.9.0` (registry pin) |
| JS runtime | Node v24.14.1 |
| Benches | `examples/incr_tea/gate_bench_test.mbt`, `examples/incr_tea/bench_wbtest.mbt` |
| Command | `moon bench --release -p examples/incr_tea -f <file> --target {js,wasm-gc}` |

Numbers are `mean ± σ` over `10 × N` runs, confirmed stable across two
back-to-back runs. JS is the primary target (Canopy ships to the web); wasm-gc is
reported for the gate as a cross-backend sanity check.

## What is and is not measured

The renderer splits into a **pure** layer (cacheable `Html` view values, the
`plan_keyed_diff` planner, `Eq`-based skip decisions) and a **DOM** layer (the
`#cfg(target="js")` applier `diff_keyed_children`, attribute patching, real
event listeners). The DOM layer needs a live `document` and **cannot run under
`moon bench` in Node** — so it is deliberately *not* benchmarked here. What is
measured are the two pure layers that carry the incremental story:

- **Part 1 — view recompute vs skip.** incr publishes the view as a `Derived`
  over field-level `Input`s; when a mutated field is not a view dependency,
  verify finds the deps unchanged and **skips the whole view rebuild**
  (backdating). A dirty-cell renderer has no dependency graph, so it re-runs
  `view(model)` and diffs on **every** change.
- **Part 2 — the keyed planner.** `plan_keyed_diff` matches old→new children by
  key so insert/remove/reorder reuse DOM nodes instead of rebuilding by
  position. Measured against a naive positional rebuild (no key reuse).

The "Rabbita / dirty-cell" baseline is **modeled**, not Rabbita itself: a small
in-package struct that rebuilds the same `Html` tree and `Eq`-diffs it on every
change. **Fairness caveat (runs against incr):** the incr benches pay the real
`runtime.batch` + propagation + `Watch` read overhead; the dirty-cell baseline is
pure compute with no framework bookkeeping. So the unread-mutation win below is a
conservative *lower* bound, and the read-mutation comparison is, if anything,
slightly unfavorable to incr.

## Gate (discipline check): does the skip reproduce in isolation?

Per `moonbit-perf-investigation`, before building the matrix, one microbenchmark
reproduces the claimed win in isolation — the counter-shaped graph (three
`Input` fields, a `Derived` view reading two of them), with an observable
recompute counter. The companion assertion pins the mechanism: across 100
unread-field mutations the recompute count stays at 1; 100 read-relevant
mutations force 100 recomputes.

| Target | unread mutation (skip) | read mutation (recompute) | skip saves |
|---|---|---|---|
| JS | **490 ns** ± 2 | 863 ns ± 6 | 373 ns (1.76×) |
| wasm-gc | **310 ns** ± 10 | 564 ns ± 4 | 254 ns (1.82×) |

Even for a **trivial** 2-field view, the skip is observably cheaper on both
backends — the gate passes. The skip cost (~0.5 µs JS) is pure
batch+propagation+verify overhead with no view evaluation; the recompute path
adds the view closure + `Eq` commit. The win grows with view size, which is what
Part 1 measures.

## Part 1 — view recompute vs skip (JS, per change)

List-shaped component: `items` (read by the view) + `unrelated` (not read). The
view builds a keyed `<ul>` of N `<li>` rows (labelled span + a notes `<input>`),
mirroring the demo's list view. Four columns per N:

- **incr skip** — mutate `unrelated`, read view. incr skips the N-node rebuild.
- **incr rebuild** — mutate `items`, read view. incr rebuilds (a dep changed).
- **dirty unread** — rebuild + full-walk diff that finds nothing (the unread
  scenario under a dirty-cell renderer).
- **dirty read** — rebuild + early-exit diff (output changed).

| N | incr skip | incr rebuild | dirty unread | dirty read |
|---|---|---|---|---|
| 16  | **0.48 µs** | 3.8 µs  | 4.55 µs | 2.8 µs |
| 64  | **0.51 µs** | 13.1 µs | 18.5 µs | 11.4 µs |
| 256 | **0.50 µs** | 48.4 µs | 79.7 µs | 47.5 µs |

### Two clean head-to-heads

**Unread mutation — incr skip vs dirty unread (the locality win):**

| N | incr skip | dirty unread | incr is |
|---|---|---|---|
| 16  | 0.48 µs | 4.55 µs | **9.5× faster** |
| 64  | 0.51 µs | 18.5 µs | **36× faster** |
| 256 | 0.50 µs | 79.7 µs | **159× faster** |

incr's skip is **flat O(1)** (~0.5 µs regardless of N) because verify never
re-enters the view closure; the dirty-cell baseline is **O(N)** (rebuild + diff)
because it cannot know the change was irrelevant. The win is the full view-build
cost and **grows linearly with view size**.

**Read mutation — incr rebuild vs dirty read (same scenario, output changes):**

| N | incr rebuild | dirty read | incr is |
|---|---|---|---|
| 16  | 3.8 µs  | 2.8 µs  | 1.36× slower |
| 64  | 13.1 µs | 11.4 µs | 1.15× slower |
| 256 | 48.4 µs | 47.5 µs | ≈ par (1.02×) |

When the change **does** affect the view, incr must rebuild like the dirty-cell
renderer **and** pays the graph overhead (batch + propagation + `Watch`), so it
is slightly slower at small N. The fixed ~1 µs overhead amortizes as the rebuild
grows, converging to par at N=256. incr's machinery is only worth it when it lets
you *skip*.

Note this is the **hardest** case for incr: `dirty read` toggles two prebuilt
arrays so the output differs at the *first* node, making its `Eq` diff exit as
early as possible — the dirty-cell renderer's best-case diff. Any realistic edit
whose first divergence is deeper makes the dirty-cell diff walk further and lose
ground, so "incr at par" here is a floor, not a ceiling, on incr's read-path
standing.

### Takeaway

incr's net win is governed by the **locality ratio** — how often a state change
leaves a given component's view unchanged. The field-level `Input` design of
`incr_tea` makes most mutations local (each component depends on a few fields),
so most components skip and incr wins by 1–2 orders of magnitude; on the minority
of changes that do hit a view, incr is at par. A dirty-cell renderer pays the
full O(N) rebuild + diff on *every* change regardless.

## Part 2 — keyed planner vs naive positional (JS)

`plan_keyed_diff(old_keys, new_keys)` runtime, by operation and list size. The
naive positional plan is an all-create / all-detach plan (O(N) construction, zero
key reuse) — the floor the planner is measured against.

Each step below is a 4× increase in N, so a quadratic O(n·m) planner should grow
~16× per step and a linear one ~4×. Both growth intervals are shown so the
scaling claim does not rest on a single pair of points.

| operation | N=16 | N=64 | N=256 | 16→64 | 64→256 |
|---|---|---|---|---|---|
| reverse (full reorder) | 0.65 µs | 10.1 µs | 128 µs | 15.5× | 12.7× |
| prepend one            | 0.47 µs | 4.35 µs | 54.4 µs | 9.3×  | 12.5× |
| unchanged              | —       | —       | 54.4 µs | —     | —      |
| naive positional       | —       | —       | 2.40 µs | —     | — (O(N)) |

**Reuse counts (asserted in `bench_wbtest.mbt` at N=64 and N=256)** — the benefit
the matching CPU buys, since the DOM ops it avoids are not measurable in Node.
The pattern is structural (N-independent); shown at N=256 to align with the
runtime rows above:

| operation (N=256) | nodes reused | nodes created | nodes detached |
|---|---|---|---|
| reverse  | 256 | 0 | 0 |
| prepend  | 256 | 1 | 0 |
| naive positional | 0 | 256 | 256 |

### Findings

1. **The planner is super-linear, consistent with its documented O(n·m).** Across
   the two 4× steps the cost grows 9–16× (vs 4× for a linear planner), with
   reverse — the worst case (~128 µs at N=256, full back-to-front scans) — closest
   to the 16× quadratic ideal. The smaller prepend ratio at 16→64 reflects
   fixed-cost overhead that a 16-element list cannot amortize. Even `unchanged`,
   the most reuse-favorable input, is *not* O(N): first-available-wins re-scans
   the consumed prefix on every match (matching new[k] at old[k] still probes k
   consumed slots), so it lands at the same ~54 µs quadratic floor as `prepend`.
2. **Naive positional construction is O(N) (2.4 µs)** but yields **zero reuse** —
   all N nodes are recreated in the DOM.
3. **The trade-off.** At N=256 the planner spends 54–128 µs of matching to avoid
   up to 256 DOM `createElement` + `insertBefore` calls (and their listeners). A
   single DOM create+insert is ~1–10 µs (DOM-bound, *not* measured here), i.e.
   256 creates ≈ 0.25–2.5 ms. So the planner's matching stays well below the DOM
   work it saves whenever reuse is substantial — **keying still wins net at these
   sizes** — but the O(n²) matching erodes the margin and would dominate beyond a
   few hundred items.

## Gaps and follow-ups

- **DOM applier now has a browser follow-up.** `diff_keyed_children`, attribute
  patching, and real listeners need a browser. This snapshot captures the
  planner's *benefit* only as reuse **counts**; the companion Playwright
  wall-time run is [2026-06-12 Incremental TEA keyed DOM applier](2026-06-12-incr-tea-keyed-dom-applier-playwright.md).
- **Planner O(n²) is empirically justified for the LIS/two-ended follow-up** the
  planner comment already anticipates ("a two-ended / LIS pass is a follow-up if
  a benchmark justifies it"). These numbers justify it for large keyed lists.
  That is a **separate optimization issue**, not part of #189.
- **wasm-gc Part 1/2 not measured.** `Html` and `plan_keyed_diff` are
  `#cfg(target="js")`, so the list/planner benches only exist on JS — the
  deployment target. The gate (target-agnostic) confirms the skip mechanism holds
  on wasm-gc too.

## Conclusion

incr's verify + backdating model wins decisively on the workload it is built for:
**state changes that don't affect a given view are skipped in O(1)** (9.5–159×
faster than a dirty-cell rebuild, the gap growing with view size), while changes
that *do* affect the view cost about the same as a dirty-cell rebuild plus a
fixed graph overhead. The keyed planner buys real DOM reuse but carries an O(n²)
matching cost that is cheap at small lists and a candidate for a follow-up
optimization at large ones.
