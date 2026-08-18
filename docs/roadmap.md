# Roadmap

The canonical current work queues for the current `incr` product and the
separate Incr Next product track.

---

## Current `dowdiness/incr` core backlog

No current-Incr core implementation is commissioned. The prior #399 attribution
is retired from the active backlog, with slot reclamation/compaction a no-go;
see the [dated performance note](performance/2026-07-15-retention-cost-attribution.md)
and [retention follow-up ADR](decisions/2026-07-14-retention-followup-tracks-gated.md).

## Incr Next product track

`dowdiness/incr_next` is an adopted, unpublished pre-1.0 sibling product.
Current `dowdiness/incr` remains current and is not replaced. The [accepted
Incr Next ADR](decisions/2026-08-17-incr-next-pre-1-0-sibling-product.md) and
[K0 Product and Kernel Contract](design/specs/2026-08-13-incr-next-kernel-contract.md)
plus [K0 Lifetime and Transaction Contract](design/specs/2026-08-13-incr-next-lifetime-and-transactions.md)
are normative. Plan 015 is complete; its durable implementation record is the
[GitHub blob at commit 5846993](https://github.com/dowdiness/incr/blob/58469934c5644686992688bc7a9f1685326a081d/plans/015-incr-next-kernel-alpha.md).

K1 is complete: K1.1–K1.6 are accepted and merged, with accepted evidence
indexed by [`incr_next/docs/README.md`](../incr_next/docs/README.md). Plan 016
commissions K2 usability/distribution evidence; implementation is not
accepted.

Publication, Canopy production integration, Mount, Program/Port/Formula, public
debug/explain, public or automatic eviction/LRU, and parallel evaluation remain
gated and excluded.

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
