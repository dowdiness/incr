# Duplix-Informed Retention Benchmarks (+ Gated Follow-Up Tracks)

**Status:** Track 1 executed — PR [#398](https://github.com/dowdiness/incr/pull/398)
(merged 2026-07-14, squash `b05add3`); results in
[docs/performance/2026-07-14-retention-baseline.md](../performance/2026-07-14-retention-baseline.md).
Tracks 2–3 remain gated decisions and are **not started**; no consumer currently
exhibits the hazard shape (incr_tea reconciles at the vdom layer with
scope-anchored watches). Decision record:
[ADR 2026-07-14 Retention follow-up tracks — keep gated](../decisions/2026-07-14-retention-followup-tracks-gated.md).
The 7a/7b/8a prediction contradictions are tracked as
[#399](https://github.com/dowdiness/incr/issues/399).

**Date:** 2026-07-14

## Goal

Quantify the cost of *forgotten* lifecycle management in `incr` — stale
subscribers, abandoned eager cells, and dynamic-subgraph churn — with a
reproducible benchmark suite, so the dispose/gc contract has measured numbers
instead of assumptions. Two follow-up tracks (detachable per-key scopes, a
keyed Map-diff facade) are specified but **gated on Track 1's results**.

The recommended implementation unit is **Track 1 only, as one PR**. Tracks 2
and 3 are not later phases of that PR and are not commitments to ship: each
requires a separate go/no-go decision after the benchmark snapshot exists.

The framing question for the whole effort: *can `incr` keep memory and update
cost predictable under UI-style workloads (long-lived inputs, high churn of
short-lived dynamic subgraphs) without depending on the user's perfect
`dispose()`/`gc()` discipline?* The analysis behind this plan concluded the
answer is currently "not fully", and that the gap is an **ownership problem,
not an invalidation problem** — `incr`'s verify/backdate/push-gate engine
stays as-is; what's missing is a hard-to-misuse API for dynamic-subgraph
ownership. Neither is Duplix's dirty-strand design the answer: its own probe
shows steady per-update cost growing linearly with retained stale edges.

## Background (self-contained — no session context required)

This plan derives from a 2026-07-14 comparison of `incr` against
[Duplix](https://github.com/Yoorkin/duplix) (Yoorkin's experimental MoonBit
reactive graph), cross-reviewed by an independent model. Duplix splits its
graph into downward-only value edges plus consumable upward "dirty flag" edges,
and ships a `dirty_retention_probe/` that measures what leaks when derived
nodes are dropped without disposal. Its probe found steady-state costs of
~77–96 ns per stale edge **per update** (≈3–3.8 ms/update at 40k stale edges).
`incr` has explicit `dispose`/`Runtime::gc`/`Watch` machinery but no equivalent
measurement of what forgetting to use it costs.

Facts established against `incr` sources during the analysis (line numbers are
from that review — **re-verify each against the current tree before relying on
it**, e.g. via `moon ide peek-def` / `find-references`):

- **F1.** A never-read `Derived` registers no subscribers
  (`incr/cells/derived_impl.mbt`, deps recorded only on recompute). A *primed*
  (read-once) `Derived` that is then dropped stays in its input's
  `subscribers` until dispose/gc, because `diff_and_update_subscribers` only
  runs on recompute (`derived_impl.mbt` ~42–65,
  `internal/kernel/subscriber_diff.mbt` ~32–52).
- **F2.** `enqueue_reachable_push_subscribers` returns before iterating
  subscribers when the source's `push_reachable_count == 0`
  (`internal/kernel/push_propagate.mbt` ~129–145). Pull-only stale subscribers
  on an input therefore cost **nothing per set** — until any live push path
  from the *same* input opens the gate, after which every update scans the
  input's full direct-subscriber list, O(N) (~146–179).
- **F3.** `PushReactiveData` is always a live subscriber
  (`internal/kernel/dispatch.mbt` ~80–98): an abandoned `EagerDerived` is not
  merely scanned but **fully recomputed on every set** — existing benches show
  100 abandoned ≈ 100 live (`incr/tests/bench_test.mbt` ~227–278;
  `docs/performance/2026-04-21-pre-r1-baseline.md`).
- **F4.** Dispose and gc do clean up: memo disposal removes the cell from each
  dependency's subscriber list (`incr/cells/pull_memo_lifecycle.mbt` ~8–18);
  `gc` marks from Watch/Observer/Effect roots and disposes unreached Interior
  cells (`internal/kernel/gc.mbt`).
- **F5.** `Input::force_set` aborts inside an active tracking frame or a
  non-Idle propagation phase (`incr/cells/input.mbt` ~246–285). No benchmark
  or facade in this plan may mutate an `Input` from inside derived compute.
  Note: *cell allocation* inside compute (used by scenario 5) is a separate
  matter — it is not guarded today but is not a publicly supported invariant
  either; treat it as a benchmark-only adversarial shape.
- **F7.** Disposing a pull memo removes it from its upstreams' subscriber
  lists but does **not** rewrite or recompute downstream memos that recorded
  it as a dependency (`incr/cells/pull_memo_lifecycle.mbt` ~8–18): a
  surviving consumer's next verify can reach a disposed dependency and abort.
  This exact problem is documented as Blocker 1 in
  [docs/research/reactive-map-design.md](../research/reactive-map-design.md)
  — **read that doc before Track 3**; it also carries a concrete driver
  (Lambda name resolution) and a prior scope estimate.
- **F6.** `Scope::child` pushes into `parent.children` but `dispose` never
  detaches the child from that array (`incr/cells/scope.mbt` ~68–103), so
  per-key child scopes under a long-lived owner accumulate disposed handles.

## Risk / benefit and recommended stopping points

This is a decision ladder, not a three-track implementation roadmap. Its main
advantage is that stopping after Track 1 still leaves useful artifacts, while
the largest semantic and API risks remain isolated behind two later gates.

### Track 1 — measurement with a cheap exit

Benefits:

- Converts F1–F3 from source-derived predictions into measurements. Scenarios
  4 and 5 are especially valuable because a contradictory result changes the
  case for both follow-up tracks rather than merely adjusting a constant.
- Adds a retention regression guard for future kernel changes. The existing
  suite covers abandoned eager cells only at N = 100 and does not cover the
  same-root gate transition or dynamic-subgraph churn.
- Records the practical dispose/gc tolerance contract in a dated snapshot:
  which mistakes are cheap, which stay latent, and which become O(N).
- Requires no public API or engine change. If the follow-up case is weak, the
  work can stop here without stranded production machinery.

Costs:

- N = 10k across the matrix makes the suite expensive to run exclusively. Do
  not add every row to routine CI without first selecting a smaller smoke set;
  keep the full matrix as an explicitly invoked benchmark if necessary.
- Dated numbers age as the kernel changes. Each performance-affecting kernel
  change must decide whether to recapture a new snapshot; old snapshots remain
  immutable historical records rather than silently updated baselines.
- Fixture construction is part of the research risk. The controls below catch
  known traps, but a prediction mismatch still requires separating a real
  finding from a malformed fixture before changing the plan.

**Stopping point:** one PR containing Track 1's benchmarks, count assertions,
dated snapshot, and documentation index update. Do not bundle Scope changes,
the keyed facade, or speculative engine support into that PR.

### Track 2 — useful only after its own evidence

Benefit: F6 is a real Scope ownership weakness independent of `KeyedInput`, so
a detach fix could improve general Scope quality even if Track 3 never ships.

Cost: Option A adds a new lifecycle invariant to a recently hardened path. It
must preserve #388's child-before-hooks-before-cells disposal order and remain
safe while a parent iterates a cascade whose children detach themselves.
Option B avoids an engine change but has no independent value without a facade
that owns per-key scopes.

**Stopping point:** do not infer that F6 deserves an engine change merely from
source shape. Measure cumulative disposed-child retention first, as specified
in Track 2. If memory, parent-dispose latency, and retained bookkeeping stay
negligible at realistic churn, keep the current Scope contract.

### Track 3 — highest benefit and highest long-term cost

Benefit: a successful facade would make keyed dynamic-subgraph ownership
explicit and provide a hard-to-misuse answer to lifecycle orphaning for a real
class of UI and analysis workloads.

Costs:

- F7 makes retirement a semantic problem, not cache bookkeeping. Every current
  option narrows the API, introduces tombstone/sweep policy, or requires an
  ADR-sized engine change.
- The repository explored this territory in April 2026 and stopped at
  `DerivedMap` after finding the same cross-key-dispose blocker. Re-entry must
  identify what new Track 1 evidence or consumer constraint changes that
  earlier decision; novelty alone is not enough.
- A third keyed lifecycle abstraction adds permanent semver, documentation,
  examples, and migration cost immediately after the 0.14.x facade cleanup.
- Lambda name resolution is a candidate, not yet a value gate. (Correction
  2026-07-14: this plan's "three resolver variants currently coexist" premise
  was stale at writing time — consolidation onto `@scope` shipped 2026-07-02
  as canopy #129 / PR #839.) Before using it as the driver, name the concrete
  contract the consolidated resolver would gain from `KeyedInput` and the
  measured success signal. Note canopy #567 explores converging binder
  identity onto loom's `ProjectionIdentityTracker`, a direction that keeps
  keyed identity outside `incr` entirely.

**Stopping point:** no Track 3 implementation until a consumer, retirement
protocol, ownership boundary, and success metric are approved in a separate
design decision. Track 1 results alone cannot authorize this API.

## Track 1 — Retention benchmark suite (execute now)

### Deliverable

A new benchmark file `incr/tests/retention_bench_test.mbt` (same package and
`@bench` idiom as the existing `incr/tests/bench_test.mbt`) covering the
scenario matrix below, plus a dated results snapshot
`docs/performance/2026-07-XX-retention-baseline.md` following the existing
performance-doc conventions (dated snapshot, never edited afterwards).

### Design rules

- Build each fixture (runtime, inputs, N derived cells, priming reads,
  dropping handles) **outside** the `@bench` body; the timed body is the
  minimal steady-state unit — typically one `Input::set` with a fresh value
  followed by one read of the designated live cell. Match the style of
  existing entries in `bench_test.mbt`.
- "Dropped" means: create the handle in a local block, prime it as the
  scenario requires, then let the binding go out of scope without `dispose`.
  Nothing else may retain it except the graph itself.
- Every scenario runs at (at least) N = 1k and 10k so linear-vs-flat scaling
  is visible. Report ns/update.
- Alongside timing, record the countable state per scenario — counts are more
  stable evidence than wall-clock alone. From the blackbox tests package,
  `rt.dependents(root.id()).length()` gives the root's subscriber count
  (`incr/cells/introspection.mbt`, `Runtime::dependents`). If internal node
  counts are needed, put those assertions in a separate
  `incr/cells/*_wbtest.mbt` companion instead of forcing them into the bench
  package.
- Benchmarks must not run concurrently with other workloads (existing
  bench-discipline rule). Exact command:
  `moon bench --release -p dowdiness/incr/tests -f retention_bench_test.mbt`.

### Scenario matrix

Predictions come from F1–F3; a scenario whose measurement contradicts its
prediction is a finding, not a benchmark bug — investigate before "fixing" it.

| # | Scenario | Shape | Prediction |
|---|----------|-------|------------|
| 1 | `uncomputed_pull_fanout` | Drop N never-read Deriveds on one Input | Flat set cost; SoA retention only (F1) |
| 2 | `primed_pull_fanout_no_push` | Prime + drop N Deriveds; no push cell anywhere on that Input | Flat set cost despite N stale subscribers (F2 gate) |
| 3 | `primed_pull_fanout_distant_push` | Like 2, but a live EagerDerived exists on a *different* Input | Still flat (per-source gate) |
| 4 | `primed_pull_fanout_same_root_live_push` | Like 2, plus ONE live push path from the *same* Input | O(N) scan per set — the Duplix `map_fanout` analog (F2) |
| 5 | `dynamic_subgraph_churn_same_root` | See two-phase fixture below | ns/update scales with accumulated stale count N — the Duplix `bind_live_root_subgraph` analog |
| 6 | `abandoned_eager_fanout` | Drop N EagerDeriveds on one Input | O(N) full recompute per set (F3) |
| 7a | `scan_disposed_control` | Scenario 4 shape; dispose only the N stale pull entries, keep the live push path | Restores flat cost (F4) |
| 7b | `scan_gc_control` | Scenario 4 shape; anchor the live push terminal with a `Watch` (or `Observer`), then `rt.gc()` | Restores flat cost with the gate still open |
| 7c | `eager_disposed_control` | Scenario 6 shape; dispose all N abandoned Eagers | Flat cost ≈ clean input |
| 7d | `eager_gc_control` | Scenario 6 shape; `rt.gc()` reclaims all abandoned Eagers (no roots anchor them) | Flat cost ≈ clean input |
| 8a | `chain_depth` | N chains at depth 1 vs depth 4, with the root's *direct* subscriber count held equal across cases | Steady push scan is depth-neutral; memory/gc work scales with total nodes |
| 8b | `fan_in` | N outputs each reading all 12 roots; measure (i) setting 1 root and (ii) setting all 12 in one batch | Scan count N for (i), 12·N-bounded for (ii) |

**Scenario 5 two-phase fixture (required — a naive version is non-stationary):**
if the timed body itself allocates a fresh inner Derived per iteration, each
`@bench` iteration measures a different graph and the mean is a churn
trajectory, not a value of N. Instead: (setup phase) run the churn loop N
times to accumulate N stale inners, then flip a capture flag so the live
Eager reuses its current inner; (timed body) one fresh `set` + designated
live read, allocating nothing. If cumulative churn cost itself is wanted,
measure the whole N-cycle churn as a separate custom probe, not via `@bench`.

**Scenario 7 controls (known-positive pair):** if 4 does not measure worse
than 7a/7b, or 6 worse than 7c/7d, the probe is not exercising the retention
path — recheck the fixture before drawing conclusions. Caution for 7b: an
`EagerDerived` is an Interior cell; holding its MoonBit handle does **not**
make it a GC root, so running `rt.gc()` on the scenario-4 shape without a
`Watch`/`Observer` anchor would sweep the live push path too, closing the
gate and conflating two effects. After `rt.gc()`, assert
`rt.dependents(root.id())` contains only the live path.

### Optional native tier (only if memory numbers are needed)

Timing and counts above are cross-target and sufficient for the go/no-go
decisions in Tracks 2–3. If a direct RSS comparison against Duplix's probe is
later wanted: `moon bench --release --target native` works regardless of any
`preferred-target` declaration (the CLI flag overrides it),
and RSS/first-dirty measurement needs a separate native-only executable (e.g.
`tools/retention_probe/`) using C FFI via a `native-stub` package — keep it
out of `incr/tests/`. Do not start here; RSS is allocator-noisy and not
needed for the first decision.

### Acceptance criteria

- [x] All matrix scenarios implemented at N ∈ {1k, 10k} and passing
      `moon bench --release` (exit status captured per the wrapped-exit-code
      rule; no piped status). — 28/28, `EXIT=0`, reproduced by an independent
      reviewer re-run (all scenarios within 2×, max ratio 1.32×).
- [x] Controls 7a/7b measurably cheaper than scenario 4, and 7c/7d cheaper
      than scenario 6 — the positive controls fire. — 7a/7b ≈75–84× cheaper
      than 4 at N=10k; 7c/7d >86,000× cheaper than 6.
- [x] Predictions vs measurements table written to the dated performance
      snapshot, including subscriber/node counts, with any contradiction
      called out explicitly. — snapshot table + constructed-node column;
      wbtest companion `incr/cells/retention_bench_fixture_wbtest.mbt` pins
      the load-bearing totals; contradictions (7a/7b residual growth, 8a
      depth effect, superlinear 10k constants) recorded → follow-up
      [#399](https://github.com/dowdiness/incr/issues/399).
- [x] `moon check` / `moon fmt` / `moon info` clean; no `.mbti` drift beyond
      the bench file's own package. — verified twice (implementer +
      reviewer), `moon check --deny-warn` included.
- [x] `docs/README.md` index updated for the new performance snapshot.

## Track 2 — Detachable per-key scope ownership (gated on Track 1)

**Facade trigger:** choose per-key ownership only if scenario 5 (churn) shows
meaningful growth *and* the Track 3 facade is still wanted.

**Independent Option A trigger:** a dedicated white-box Scope probe must first
create and individually dispose at least 10k child scopes under one long-lived
parent, then measure/assert all three of: retained `parent.children` length,
memory trend (RSS only if needed), and the later cost of disposing the parent.
Option A is independently justified only if this accumulation is material in a
realistic non-`KeyedInput` consumer or measurably degrades lifecycle operations.
F6's source-level accumulation alone is not sufficient. If that evidence is
absent and Track 3 is not approved, stop without changing `Scope`.

`Scope::child` never detaches disposed children (F6). Decide between:

- **Option A:** add a detach-on-dispose mechanism to `Scope` (child removes
  itself from `parent.children`; needs care about iteration during disposal
  cascades and about not breaking `on_dispose` ordering shipped in #388).
- **Option B:** per-key independent `Scope::new(rt)` owned by the facade's
  entry map, with the facade's own dispose iterating entries — no engine
  change, ownership lives in the facade.

Whichever is chosen, write the decision and its invariants (who may hold a
disposed scope handle; what `dispose` guarantees about parent arrays) into the
plan/ADR **before** implementation, and add a churn regression test that holds
a long-lived owner scope through ≥10k key enter/leave cycles and asserts
bounded growth of whatever structure the option retains.

## Track 3 — `KeyedInput` facade prototype (assoc analog, gated on Tracks 1–2)

**Trigger:** a concrete consumer names itself (value-gate rule: who consumes
this, what signal judges success, what lifecycle). Do not build speculatively.
Approval also requires all of the following:

- A written choice among the F7 retirement protocols below, including whether
  per-key outputs may escape the facade.
- A delta against the April 2026 conclusion in
  [reactive-map-design.md](../research/reactive-map-design.md): state what new
  evidence or narrower consumer contract makes re-entry safe now.
- An explicit public-API budget covering semver policy, documentation,
  examples, and the relationship to `DerivedMap`; the default answer after the
  0.14.x facade cleanup is no additional facade without demonstrated value.
- For the Lambda resolver candidate: the resolver split is already
  consolidated onto `@scope` (canopy #129 / PR #839, merged 2026-07-02), so
  this gate reduces to naming the concrete contract and success signal that
  moving the consolidated resolver onto `KeyedInput` would improve. Do not
  add `KeyedInput` as a parallel resolver path.

Duplix's `assoc` (per-key stable subgraphs over a changing `Map[K, V]`) cannot
be transliterated: its diff-and-mutate runs inside derived compute, which
`incr` forbids (F5). The viable shape is a **userland facade, functional-core
/ imperative-shell**:

Prerequisite reading:
[docs/research/reactive-map-design.md](../research/reactive-map-design.md) —
an earlier exploration of the same territory whose blockers (cross-key
dispose, `remove_except` bookkeeping, tracking semantics) apply directly here.

- Pure core: `diff(old_map, new_map) -> keep/insert/update/remove commands`.
  Deterministic, no runtime access, unit-testable.
- Shell: `KeyedInput::set(new_map)` runs the diff *outside* the graph, then
  inside one `Runtime::batch` updates the source input and only the changed
  per-key `Input[V]`s (same-value sets are no-ops, so unchanged keys backdate
  normally), and **after** the batch commit returns, retires removed keys'
  scopes. Removal disposal must never run inside batch/propagation.
- **Retirement protocol (required — naive post-batch dispose is unsafe, F7):**
  disposing a removed key's cells while a surviving downstream memo still
  records them as dependencies makes that consumer's next verify abort on a
  disposed dep. Choose one of:
  - v1: per-key outputs never escape the facade; a facade-owned terminal
    aggregate is force-recomputed after the batch (dropping old deps) and
    only then are removed entries disposed;
  - tombstone: removed entries are held in a retired state and swept at a
    safe point once their subscriber count reaches zero;
  - engine-level dispose invalidation for arbitrary external consumers —
    a separate ADR-sized decision, out of scope for the prototype.
- Key exit is a domain event → deterministic dispose; `Runtime::gc` remains
  only the safety net for abandoning the whole facade. Key re-entry creates a
  fresh entry — state its semantics explicitly; caching/LRU is a separate
  option, not a default.
- Keep a membership/order index separate from per-key value cells so a
  value-only change does not invalidate keyset aggregates. Do not make Map
  iteration order an API contract.
- Reuse from `DerivedMap` by **extracting** its keyed-cache/lifecycle helpers
  (`get_or_create_entry` pattern, scope-disposal hook), not by extending it:
  `DerivedMap` is key-query memoization; this facade is
  membership-following subgraph ownership — different exit semantics.

Design review by an independent model before implementation (algorithm-class
change: lifecycle invariants, batch interaction, backdating per key).

## End-state success conditions (across all tracks)

These are the design goals the gated tracks must eventually satisfy; Track 1
provides the instruments that make them checkable:

- After a key exits, the root input's subscriber count returns to baseline —
  **and every surviving consumer still reads successfully** (no
  Disposed/Cycle abort; this is the F7 retirement-protocol check).
- Steady per-update time does not grow with the *cumulative* number of
  created-then-dropped subgraphs (only with live ones).
- A **facade-owned** `EagerDerived` retired by key exit is disposed
  immediately and stops recomputing. (A bare `EagerDerived` handle dropped by
  the user is *not* fixed by these tracks — see Non-goals.)
- Per-key memory is proportional to the number of *live* keys.
- After `facade.dispose()`, owned cells, `Watch`/`Observer` roots, per-key
  scopes, and parent-ownership bookkeeping all return to baseline.
- No intermediate states are observable during a batched map update.
- Same-value per-key updates preserve backdating.
- Removing and re-entering the same key has pinned identity/state semantics
  (fresh entry by default), fixed by a test.
- On a raised failure mid-update the shell exposes no partial state
  (`Runtime::batch` rolls back raises; `abort` is unrecoverable — state the
  failure contract explicitly).

## Execution order

1. Land Track 1 benchmarks and the dated snapshot as one PR. This is the whole
   recommended implementation scope and the only work authorized by this plan.
2. Read the snapshot. Make a separate decision on Track 2 only if its facade
   trigger or independent Option A evidence gate is satisfied.
3. Make a separate Track 3 design decision only when every consumer and
   re-entry gate above is satisfied; engine-level primitives
   (post-compute command queue) only if the userland facade proves
   insufficient — record that as its own ADR-worthy decision.

## Non-goals

- Making a *bare* abandoned `EagerDerived` (a handle the user constructed
  directly and dropped) stop recomputing automatically — that would require
  finalizers/weak ownership/automatic GC, a different mechanism entirely.
  These tracks fix facade-owned lifecycles only; the general question in the
  Goal section stays open to that extent.
- Copying Duplix's consumable-edge propagation into `incr`'s kernel —
  `incr`'s `on_observe`/`on_unobserve` push suspension already covers the
  motivating case differently; any such proposal must be framed as a delta
  against suspension, with Track 1 numbers as the baseline.
- Claiming equivalence between Duplix and `incr` mechanisms in any write-up:
  Duplix's `push_dirty` edge-clearing has no `incr` equivalent
  (`incr` maintains `push_reachable_count` + liveness counters instead), and
  Duplix's "at-most-once recompute" maps only conditionally onto `incr`'s
  verify/backdate semantics.
