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
boundary, backend, and work-count gates. Local validation, hosted CI, independent reviews, and maintainer acceptance pass;
CodeRabbit skipped content review and is not positive evidence.

K1.3 invocation-level cycle detection is **ACCEPTED** at implementation head
`e187b562f87ec4ecd50940a5e8fc2bc5d478380c`, finalized at status-only head
`a8115757662a6412e053aad9b7dc451f39a825c6`, and **MERGED** as squash commit
`5657cfc99734c9ac9e7093dd71819d6a0c48df87`. It adds typed invocation identity,
active-before-cache ordering, copied key-free Cycle witnesses, old/current
Cycle separation, atomic recovery, and structured cleanup.

K1.4 typed cutoff and backdating is **ACCEPTED AND MERGED** at
implementation/validation head
`0036bdd199a685823b6769bf1acdac3f9b6b9014`, status-only head
`c88e724383ca5f3e817f30226a9fa23cf3ad7358`, and squash merge commit
`9d53d51d6ec6e282b8aa247442ee126acfe64a2d`. Hosted acceptance passed 46/46,
public diff review was APPROVE, maintainer acceptance was PASS, and squash-tree
equivalence passed. CodeRabbit skipped content review and is not positive
evidence; independent public review supplies review evidence. The selected
surface provides fixed-per-Query typed AlwaysChanged, `Eq`, and type-owned
choices without a public predicate or policy representation. Successful
recomputation always installs the newest value and trace; only a
propagation-equivalent result retains old `changed_at` so downstream
verification may skip work.

K1.5 private proof loss and ownership closure is **ACCEPTED AND MERGED** at
implementation head `064a80ac884f7c5588f123cc62dd784adeb26b48`, review-fix head
`378df40f7b84e1b6a3ebdb7f32299e2d628f1d54`, status-only head
`6de46abf19acb69cc5d5274b89a0ee780e48fb8d`, and squash merge commit
`4e66654d021435179116c0cffd56c0216b1bc664`. The status-only head passed 46/46
hosted checks, including `Incr Next Required`, with no pending or failed checks;
maintainer acceptance and squash-tree equivalence passed. Its package-private
per-key operation discards all memo reuse evidence without changing semantic
state, then rematerializes from a surviving View or downstream `QueryCore` plus
typed-key recipe with a new `MemoId`, current stamps, zero cutoff calls, and
conservative downstream recomputation.

K1 is complete: K1.1–K1.6 are accepted/merged. K1.6 evidence is recorded at
implementation `b7d2c32ebdc65472db2ed0fd36f36a678c86822f`, status record
`6f51d63e4e406554e74cbbbb3e6c3f481d559547`, and final PR/CI head
`15892973a556dc8a1c960bd3544f8e3c3922596a`. Hosted acceptance passed 46/46,
including Incr Next Required; independent reviews APPROVE; squash merge is
`58469934c5644686992688bc7a9f1685326a081d`, with squash-tree equality PASS.
Current `incr`, production kernel/manifests, and generated interfaces have zero
delta. K2 usability/distribution is next but not yet commissioned.

Publication, Canopy production integration, Mount, Program/Port/Formula, public
debug/explain, public or automatic eviction/LRU, and parallel evaluation remain
gated and excluded.

The sibling module owns the accepted K1 records in
[`incr_next/docs/roadmap.md`](../incr_next/docs/roadmap.md).

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
