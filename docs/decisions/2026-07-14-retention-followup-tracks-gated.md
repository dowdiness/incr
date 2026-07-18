# ADR: Retention Follow-Up Tracks — Keep Gated; Investigate Retained-Volume Cost First

**Date:** 2026-07-14
**Status:** Accepted — Tracks 2–3 stay gated; reopen only with a named consumer
**Evidence:** [2026-07-14 retention baseline](../performance/2026-07-14-retention-baseline.md); prior exploration [reactive-map-design.md](../research/reactive-map-design.md) (2026-04-19)
**Follow-up:** [#399](https://github.com/dowdiness/incr/issues/399) — **completed (no-go).** See [2026-07-15 retention cost attribution](../performance/2026-07-15-retention-cost-attribution.md): native reproduction confirmed, slot-reclamation/compaction no-go.

## Context

Track 1 of the retention plan measured the cost of *forgotten* lifecycle
management (PR #398). The numbers confirmed the plan's predictions: pull-only
stale subscribers are nearly free while their input has no reachable push
consumer (~72–96 ns/update at 10k stale); one same-root live push path
switches the cost class to an O(N) scan (~757 µs/update at 10k); an abandoned
`EagerDerived` recomputes fully on every set (~6.6 ms/update at 10k); and
`dispose`/`Runtime::gc` restore each shape. The plan gated two follow-up
tracks on these results: Track 2 (detachable per-key `Scope` ownership) and
Track 3 (a `KeyedInput` Map-diff facade for keyed dynamic-subgraph ownership).

The measurement alone cannot answer the gate question, because the gates are
about *consumers*, not costs. The consumer check performed for this decision
found:

- **incr_tea does not exhibit the hazard shape.** Its architecture is one
  model `InputField` + one view `Derived`, keyed reconciliation happens at the
  vdom/DOM layer (`incr_tea/keyed_diff.mbt`), and long-lived readers are
  scope-anchored (`scope.add_watch(...)` in `incr_tea/program.mbt`). It never
  creates per-key reactive subgraphs, so it cannot orphan them.
- **The Lambda resolver candidate's premise was stale.** Resolver
  consolidation onto `@scope` shipped 2026-07-02 (canopy #129 / PR #839),
  before the plan was written. Canopy #567 explores converging binder
  identity onto loom's `ProjectionIdentityTracker` — a direction that keeps
  keyed identity *outside* `incr`.
- **Track 1 did not move the Track 3 blocker.** F7 (disposing a removed key's
  cells while a surviving downstream memo still records them as dependencies
  aborts that consumer's next verify) is a semantic problem; the April 2026
  exploration stopped on it, and cost measurements say nothing about it.

Track 1 also produced an unplanned finding: even after full cleanup, steady
per-update cost grows with *cumulative created* volume (controls 7a/7b:
~1.5 µs at N=1k → 9–10 µs at N=10k with the subscriber count fixed at 1;
scenario 8a tracks total retained nodes, not depth). This is a kernel-side
question — slot/SoA volume vs wasm-gc heap effects — that neither follow-up
track addresses, and it affects disciplined users too.

## Decision

1. **Do not start Track 2 or Track 3 now.** No first-party consumer exhibits
   the hazard shape the facade would fix, and the F7 retirement blocker is
   unchanged. The plan's gate sections remain the authoritative checklists.
2. **The next retention work is [#399](https://github.com/dowdiness/incr/issues/399):**
   attribute the residual retained-volume cost (native-target re-run +
   post-dispose slot-count assertions) before proposing any slot-reclamation
   engine change. It is public-API-free and benefits all users.
3. **F6 (`Scope::child` never detaches disposed children) stays unfixed for
   now.** Without a churn consumer the accumulation does not occur in
   practice; Track 2's evidence gate (a dedicated ≥10k-child Scope probe)
   still applies if this is revisited.

## Reopen criteria

Reopen the Track 2/3 decision only when a concrete consumer names itself with
all of:

1. a workload that creates **per-key dynamic reactive subgraphs under a live
   push path** (the scenario 4/5 shape) — candidates: a canopy projectional
   feature needing per-node incremental analyses, or a lambda `@scope`
   resolver need that loom-side identity tracking (#567) cannot satisfy;
2. a measured success signal for that consumer;
3. a written choice among the F7 retirement protocols (facade-owned terminal
   aggregate, tombstone sweep, or an engine-level ADR), stated as a delta
   against [reactive-map-design.md](../research/reactive-map-design.md).

If #399 attributes the residual cost to SoA slot volume, its fix is a
separate engine decision and does not by itself reopen the facade tracks.

## Rationale

- Track 1 measured the height of the cliff; it cannot measure whether anyone
  walks near it. Building ownership API without a consumer risks a permanent
  semver/documentation burden immediately after the 0.14.x facade cleanup —
  the same reasoning that kept the static-derived fast path private
  ([2026-06-01](2026-06-01-static-derived-public-surface.md)).
- The residual-volume finding redirects effort to a problem that affects
  every long-lived runtime, disciplined or not.

## Consequences

- Track 1 shipped in PR [#398](https://github.com/dowdiness/incr/pull/398); the plan was retired after execution.
- [concepts.mbt.md](../concepts.mbt.md) documents the measured lifecycle cost
  model so users can avoid the cliff today with scope-owned cleanup.
- The retention bench suite (`incr/tests/retention_bench_test.mbt`) is the
  regression instrument for any future kernel change touching these paths;
  new numbers go in new dated snapshots.

## Completed follow-up

The local #399 attribution is complete:

- Native reproduced the residual at the same magnitude and N-dependent shape
  as wasm-gc.
- White-box controls found no cumulative-slot scan or named scaling operation.
- Pull slots are reusable after cleanup.
- Slot reclamation/compaction is a no-go.

The [2026-07-15 retention cost attribution](../performance/2026-07-15-retention-cost-attribution.md)
retains the benchmarks as regression probes. Reopen slot reclamation only when
all three conditions in that note hold:

1. A production-shaped workload reproduces a material user-visible cost.
2. A profiler identifies a named operation whose work scales with retained
   storage.
3. An isolated reclamation or allocation-reuse prototype reduces that operation
   without changing `CellId`, dependency, disposal, or GC semantics.
