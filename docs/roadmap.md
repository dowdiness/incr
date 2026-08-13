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

K0 product-contract documentation is commissioned separately from current
`dowdiness/incr`. The selected contract and implementation handoff are:

- [K0 Product and Kernel Contract](design/specs/2026-08-13-incr-next-kernel-contract.md)
- [K0 Lifetime and Transaction Contract](design/specs/2026-08-13-incr-next-lifetime-and-transactions.md)
- [Plan 015 — Incr Next K1 Kernel Alpha](../plans/015-incr-next-kernel-alpha.md)

K1.1 is commissioned: module/package seams, independent Fresh boundary,
opaque capabilities, no-memo evaluation, transaction-only publication, the
module-global alpha phase gate, and the Region lifetime skeleton. K1.2–K1.6
remain uncommissioned; typed memo/trace, cycles, cutoff, proof loss, and later
conformance work require separate maintainer decisions.

The sibling module now owns the active K1.1 queue in
[`incr_next/docs/roadmap.md`](../incr_next/docs/roadmap.md); this root roadmap retains the product pointer.

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
