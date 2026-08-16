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

K1.3 invocation-level cycle detection is **ACCEPTED** at implementation head
`e187b562f87ec4ecd50940a5e8fc2bc5d478380c`, finalized at status-only head
`a8115757662a6412e053aad9b7dc451f39a825c6`, and **MERGED** as squash commit
`5657cfc99734c9ac9e7093dd71819d6a0c48df87`. It adds typed invocation identity,
active-before-cache ordering, copied key-free Cycle witnesses, old/current
Cycle separation, atomic recovery, and structured cleanup.

K1.4 typed cutoff and backdating is **IMPLEMENTATION COMPLETE** and
**MAINTAINER ACCEPTED** at implementation/validation head
`0036bdd199a685823b6769bf1acdac3f9b6b9014` (component heads
`fad637a57e668924156a50c7af8b4f2e8c58fa59`,
`9318408740b6865c14735da0be922a872e2c21bb`,
`16e6a1fc1a4cb48ac1ba11463096595398115472`,
`f84d9589d4b979b711036263255f6a3f2e684525`); hosted acceptance PASS
46/46, public diff review APPROVE, maintainer acceptance PASS;
**MERGE PENDING** — final merge authorized only after status-only current-head
required checks are green. CodeRabbit skipped content review and is not
positive evidence; independent public review supplies review evidence.
The selected surface provides fixed-per-Query typed
AlwaysChanged, `Eq`, and type-owned choices without a public predicate or policy
representation. Successful recomputation always installs the newest value and
trace; only a propagation-equivalent result retains old `changed_at` so
downstream verification may skip work. K1.5–K1.6 remain blocked and
uncommissioned, as do eviction, Mount/Program, Canopy, ADR, and publication.

The sibling module owns the accepted K1.1–K1.3 records and K1.4 validation in
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
