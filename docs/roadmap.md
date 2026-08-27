# Roadmap

The canonical current work queues for the current `incr` product and the
separate Incr Query product track.

---

## Current `dowdiness/incr` core backlog

No current-Incr core implementation is commissioned. The prior #399 attribution
is retired from the active backlog, with slot reclamation/compaction a no-go;
see the [dated performance note](performance/2026-07-15-retention-cost-attribution.md)
and [retention follow-up ADR](decisions/2026-07-14-retention-followup-tracks-gated.md).

## Incr Query product track

`dowdiness/incr_query` is an adopted, unpublished pre-1.0 sibling product.
Current `dowdiness/incr` remains current and is not replaced. The [accepted
Incr Query ADR](decisions/2026-08-17-incr-query-pre-1-0-sibling-product.md) and
[K0 Product and Kernel Contract](design/specs/2026-08-13-incr-query-kernel-contract.md)
plus [K0 Lifetime and Transaction Contract](design/specs/2026-08-13-incr-query-lifetime-and-transactions.md)
are normative. Plan 015 is complete; its durable implementation record is the
[GitHub blob at commit 5846993](https://github.com/dowdiness/incr/blob/58469934c5644686992688bc7a9f1685326a081d/plans/015-incr-next-kernel-alpha.md).

K1 and K2 are complete and accepted, with evidence indexed by
[`incr_query/docs/README.md`](../incr_query/docs/README.md). K2 selected a
separate alpha publication commission after one prerequisite: standardize
active candidate packaging on an exact MoonBit 0.10.9-or-newer pin while
preserving historical evidence pins and optional 0.10.4 consumer compatibility.
Active repository automation now uses exact MoonBit 0.10.9+6e6c44045 through
its checksum-verified local installer, satisfying that prerequisite.
Repository-wide validation exposed the `examples/incr_tea` transitive
`moonbitlang/async@0.19.0` as compiler-incompatible; the example module now
resolves `async@0.21.0` directly while retaining its existing Luna, JS, and
Rabbita pins.

Actual publication, registry mutation, version release, Canopy production
integration, Mount, Program/Port/Formula, public debug/explain, public or
automatic eviction/LRU, and parallel evaluation remain gated and excluded.

## Module-owned queues

- **incr_tea**: [`incr_tea/docs/backlog.md`](../incr_tea/docs/backlog.md) — task list for the `dowdiness/incr_tea` module (retargeted TEA issues + agenda).

## What is not here

Completed work, superseded proposals, driver-gated investigations, and
speculative tracks are intentionally absent. They remain recoverable through:

- **ADRs**: [`docs/decisions/`](decisions/) — architectural decisions and rationale
- **Plans**: [`plans/`](../plans/) — concrete implementation records
- **Issues**: GitHub issue tracker — open and closed issues
- **Git history**: all historical work and decisions

This keeps each queue focused on current actionable work instead of becoming a
historical archive.
