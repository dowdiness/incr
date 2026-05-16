# Push-Engine Cost Decomposition — Strategic Investigation

**Date:** 2026-05-16
**Backend:** wasm-gc (`moon bench --release`)
**Bench file:** `tests/bench_test.mbt`
**Companion doc:** [`2026-05-16-push-engine-linklist-microbench.md`](2026-05-16-push-engine-linklist-microbench.md)
(the Link-list port investigation that surfaced these broader findings)
**Status:** Strategic ranking complete. Chosen direction: **per-recompute
allocation elimination (tracking-buffer reuse)**. Disposed-cell anomaly
captured as a separate follow-up investigation.

> **Result note (added 2026-05-16, same session):** The chosen direction
> shipped as lazy-allocation only — pool reuse of the full `ActiveQuery`
> was rejected by a microbench probe (~2% / within σ on wasm-gc). The
> "~80–150 ns/reactive" estimate in §1 below was inflated; the actual
> ceiling for this optimization is ~50 ns/r. See
> [`2026-05-16-tracking-buffer-lazy-alloc.md`](2026-05-16-tracking-buffer-lazy-alloc.md)
> for the implementation result and corrected estimates.

## Why this document exists

The Link-list port microbench (companion doc) measured the realistic Vue-3.6-style
speedup at 1.2–1.5× on incr's push engine — at the threshold of warranting the
port, not clearly above. The follow-up question "what's the most relevant change
for push-engine performance?" prompted a broader cost decomposition that
revealed higher-leverage targets than Link-list.

## Diagnostic benches (added 2026-05-16)

Two diagnostic benches were added to `tests/bench_test.mbt` to isolate where
unexpected push-engine cost comes from:

| Bench | Cost | What it tells us |
|---|---:|---|
| `signal: set new value` (no cells) | 5.25 ns | True cold baseline. |
| `100 disposed reactives on **separate** signal` | 45 ns | Cell-index size alone is not the cost. |
| `100 disposed reactives on **same** signal` | **27.75 µs** | Per-disposed-cell work on the signal they were subscribed to. |
| `100 abandoned reactives` (handles dropped, never disposed) | 60 ns | Measured cost suggests these aren't traversed during push. Lifecycle path not yet traced — `rt.gc()` is never called in the bench, so the runtime's SoA still holds them. Likely candidate: wasm-gc compile-time elimination of the unobserved closures (the handle is `ignore()`'d). Either way, these are not a real fanout measurement. |
| `100 live reactives` (held by array, no observer) | 1.73 µs (high σ) | High variance plus low absolute cost suggests wasm-gc is also eliminating these. Hold a live observer to get a trustworthy fanout measurement. |
| `500-reactive fanout` (held by array, observed via reactivity) | 138 µs / 276 ns/reactive | Trustworthy steady-state push fanout. |
| `1000-reactive fanout` | 289 µs / 289 ns/reactive | Linear from 500; trustworthy. |

### Key finding: disposed-on-same-signal anomaly

`100 disposed reactives on **same** signal` costs **240 ns per disposed cell**
per signal set. `push.node_count == 0` after the last dispose, so `push_propagate_from`
is skipped entirely. The cost must come from a path that still iterates work
proportional to disposed-cell count on `sig.subscribers` — either dispose's
`remove_subscriber` call leaves entries behind, or `set_changed_at` / some
other arm walks the subscriber set.

**For any real app with cell churn (editor sessions creating/disposing memos
as the user navigates), this is a perf cliff far larger than any per-reactive
push-path optimization.** Tracked as a separate investigation.

## Per-reactive cost decomposition (N=1000 fanout, ~289 ns/reactive)

Inferred breakdown of one push-BFS step + downstream work:

| Component | ~ns/reactive | Code site | Addressable how |
|---|---:|---|---|
| `pop_tracking` allocates `ActiveQuery` + 4 inner collections per recompute | **~80–150** | `cells/internal/kernel/state.mbt:96` `ActiveQuery::new` | **Buffer reuse** — pre-allocate on tracking-frame stack, clear between cells |
| HashSet iter on `sig.subscribers` (outer BFS step) | ~50–100 | `cells/internal/kernel/push_propagate.mbt:145` | Link-list port (deprioritized — see companion doc) |
| Priority-queue heap push + pop (log N) | ~30–50 | `push_propagate.mbt:124, 150, 178` | Scheduler rewrite (level-bucketed dirty list) |
| Type-erased `compute : () -> Bool` indirect call | ~30–50 | `push_reactive.mbt:28` | Per-kind devirtualization (large refactor) |
| `diff_and_update_subscribers` early-exit | ~30 | `subscriber_diff.mbt` | Folded into Link-list port if pursued |
| match arms on `cell_index`, validate, `recompute_level` | ~30 | various | Not really. |

### Why allocation in `pop_tracking` is the top target

`ActiveQuery::new` (`cells/internal/kernel/state.mbt:96`) allocates **five
objects** per push:

1. `ActiveQuery` struct
2. `dependencies : Array[CellId]` (empty)
3. `seen : @hashset.HashSet[CellId]` (empty)
4. `accumulator_reads : @hashmap.HashMap[(AccumulatorId, CellId), Revision]` (empty)
5. `touched_accumulator_slots : @hashset.HashSet[AccumulatorId]` (empty)

This runs on **every** memo recompute AND every push reactive/effect recompute.
At 1000-fanout steady-state, that's 5000 allocations per set; at the bench's
~340 iter/sec sweep, ~1.7M allocations/sec. Sustained GC pressure on a hot
path.

Push reactives and push effects **never** use the two accumulator-related
collections — those are memo-only — yet they pay the allocation cost on every
recompute. Even for memos, the allocations are wasteful: most ActiveQuery
instances finish with very few entries, and the collections themselves are
discarded almost immediately (transferred to `MemoData.dependencies` /
discarded after `diff_and_update_subscribers`).

## Strategic ranking (biggest lever first)

### 1. Per-recompute allocation elimination (tracking-buffer reuse) — CHOSEN DIRECTION

**Estimated saving:** ~80–150 ns/reactive at N=1000 fanout (~30–50% of
per-reactive cost). Affects both push engine and pull engine. Smallest
implementation cost.

**Sketch:**
- Pre-allocate a pool of `ActiveQuery` instances on the tracking-frame stack
  (or a free-list adjacent to it).
- `push_tracking` pops one off; if pool empty, allocates one (so worst case
  is current behavior).
- `pop_tracking` clears the collections (`Array::clear`, `HashSet::clear`,
  `HashMap::clear`) and returns the instance to the pool.
- For ActiveQuery's accumulator-related fields: lazy-allocate them only when
  `record_accumulator_read` is called (push reactives/effects never touch
  them, so they stay `None` and avoid the allocation entirely).

**Open design questions:**
- Does MoonBit's `Array::clear` / `HashSet::clear` / `HashMap::clear` actually
  return the underlying buffer to a reusable state, or does it allocate a new
  buffer? Needs verification before estimating savings.
- The current `pop_tracking` returns the `dependencies` array AND `seen`
  hashset by value. Downstream consumers (`diff_and_update_subscribers`,
  `MemoData.dependencies`) take ownership of these. The reuse strategy needs
  to either (a) clone before returning, or (b) restructure so consumers
  consume from a borrowed view, or (c) have the caller swap-in a fresh empty
  buffer when receiving.

**Microbench plan before implementation:**
- Add allocation-counter instrumentation (or use moonbit's GC stats if
  available) to verify the 5-allocations-per-recompute claim.
- Prototype a single change: lazy-allocate `accumulator_reads` and
  `touched_accumulator_slots` in `ActiveQuery::new`. Re-run the N=1000
  fanout bench. Push reactives never touch these — so any measurable
  improvement is pure win.
- If lazy-allocation alone shows a meaningful improvement (>10%), proceed
  to the full pool design. If not, the allocation cost is smaller than
  estimated and the strategy needs rethinking.

### 2. Disposed-cell anomaly investigation

**Estimated saving:** Unknown but potentially large for cell-churn workloads.
~240 ns per disposed cell per signal set with the disposed cell still in the
subscriber list. For an editor that disposes 1000s of memos over a session
and keeps setting signals, this compounds.

**First step:** whitebox-test that disposing 100 reactives on a signal leaves
`sig.subscribers.size() == 0` (or NOT). The two outcomes lead to very
different fixes:
- If subscribers is empty: cost is in some other path that iterates work
  proportional to disposed-cell count. Trace it.
- If subscribers still has entries: dispose's `remove_subscriber` isn't
  removing them. Bug in the lifecycle.

### 3. Scheduler rewrite: priority-queue → level-bucketed dirty list

**Estimated saving:** ~30–50 ns/reactive + removes one allocation source per
push entry. This is the *other half* of what alien-signals does in Vue 3.6
(and arguably the bigger half). Replace `@priority_queue.PriorityQueue[PushEntry]`
with an `Array[Array[CellRef]]` indexed by topological level.

**Implementation cost:** Moderate — touches `push_propagate.mbt` and the
level-shift handling in `propagate_level_change`.

**Deferred until 1 and 2 land** — the absolute number is smaller and the
refactor benefits compound less with 1.

### 4. Link-list port (deprioritized)

See companion doc. 1.2–1.5× on the BFS iter path specifically. Real but
narrower than 1 and 2. Revisit if a future workload shifts the cost balance
(e.g., very-low-cost compute closures making subscriber-set iter dominant).

### 5. Compute closure devirtualization

Replace boxed `() -> Bool` with per-kind function index. Saves indirect-call
cost. Biggest structural change for the smallest payoff. Not currently planned.

## Chosen direction

**Pursue #1 (per-recompute allocation elimination / tracking-buffer reuse) first.**
Reasons:
- Smallest implementation cost, broadest reach (affects pull engine too).
- The lazy-allocation sub-step (skip accumulator-fields for push reactives)
  is a small isolated change that validates the broader hypothesis with
  almost no risk.
- Allocations on the hot path are persistent GC pressure, not a one-time cost
  — they compound with every change that adds more push reactives.

**File #2 (disposed-cell anomaly) as a separate parallel investigation** —
it's potentially much larger but is a bug-shape problem (find and fix), not a
design problem.

**Defer #3 (scheduler rewrite) and #4 (Link-list port) until #1 lands** and
the per-reactive cost ceiling is clearly visible.

## What was NOT measured but might matter

- **JS-target benchmarks.** Canopy ships to the web. Per CLAUDE.md (and
  moonbit-perf-investigation skill), wasm-gc numbers don't always predict JS
  numbers. The per-allocation cost on V8 is different from wasm-gc; the
  HashSet iter cost is different. If #1 lands, validate on the JS backend
  before declaring victory.
- **Real-application workloads.** The benches measure synthetic fanout. A
  real Canopy editor session has memo-heavy workloads with branchy
  dependencies, not pure push fanout. The relative rank of these
  optimizations may shift on real workloads. The lambda editor benchmark
  suite in `loom/examples/lambda/src/benchmarks/` is the natural sanity-check
  once a prototype lands.
