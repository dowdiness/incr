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

K1.1 is accepted and merged at implementation head
`0ad8f5ae60082dfc6410aac781baa61f52c67d79`: module/package seams,
independent Fresh boundary, opaque capabilities, no-memo evaluation,
transaction-only publication, the module-global alpha phase gate, and the
Region lifetime skeleton.

K1.2 is **ACCEPTED** at implementation head
`12ec2404b676ef7864e353aeb3681c0fef6f20e3` and **MERGED** as squash commit
`db2ac77ac0362a7c5ff8d20887868cbdbb635aa8`. K1.2a/b/c cover typed
per-Query memo ownership, last-successful forward verification and dynamic
traces, target-local failure atomicity and recovery, plus their ownership,
boundary, backend, and work-count gates. Local validation, hosted CI,
CodeRabbit, independent reviews, and maintainer acceptance pass.

K1.3 invocation-level cycle detection is **COMMISSIONED** (implementation not
yet accepted). The commission covers typed active tracking per QueryCore, a
key-free session active stack, active checks before memo lookup, copied
key-free normalized Cycle witnesses, and independent Fresh and incremental
cycle semantics.

An old-trace Cycle requests recomputation; only a current-recompute Cycle
becomes the root ReadError. The scope also requires cleanup on every structured
exit and memo recovery after cycle introduction/removal. It does not include
cutoff/backdating, eviction or automatic retention, iterative evaluation or
stack-overflow protection, recovery values, error caching, parallelism,
Mount/Program, Canopy, ADR, or publication. K1.4–K1.6 remain blocked and
uncommissioned.

The sibling module owns the accepted K1.1 and K1.2 records and K1.3 commission in
[`incr_next/docs/roadmap.md`](../incr_next/docs/roadmap.md); this root roadmap
retains the product pointer.

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
