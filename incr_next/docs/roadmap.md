# Incr Next roadmap

K1.1 is **ACCEPTED** at implementation head
`0ad8f5ae60082dfc6410aac781baa61f52c67d79`. Its local matrix, hosted CI,
boundary probes, native ownership evidence, generated-interface review,
independent reviews, and maintainer acceptance pass.

The accepted scope is Store, Region, Source, Query, opaque View, QueryContext,
Transaction, Revision, structural errors, and the independent testkit. Plan 015
remains **IN PROGRESS**.

K1.2 is **ACCEPTED** at implementation head
`12ec2404b676ef7864e353aeb3681c0fef6f20e3`. K1.2a implements:

- Query-local typed memo ownership after a generated-interface compile probe
  selects the public `K : Hash + Eq` bound;
- Source, Query invocation, and Revision-clock trace ownership/metadata on
  successful memos;
- same-epoch hits, with stale epochs still recomputing unconditionally;
- close-time release and work-count evidence.

K1.2b implements forward trace verification and green reuse, including
unrelated publications, selected recomputation, dynamic trace replacement,
Revision-clock verification, and same-Store cross-Region branch-away. K1.2c
now implements target-local structural failure atomicity: initial failures do
not install memos, failed recomputes return the current error without stale
fallback, successful upstream work remains installed, and recovery preserves
memo identity while replacing value/trace and stamps.

The [K1.2 validation record](k1-2-validation.md) captures the passing local
and hosted gates, CodeRabbit, independent reviews, and maintainer acceptance.
K1.2 is **MERGED** as squash commit
`db2ac77ac0362a7c5ff8d20887868cbdbb635aa8`.

K1.3 invocation-level cycle detection is **IMPLEMENTATION COMPLETE** and
**MAINTAINER ACCEPTED** at implementation head
`e187b562f87ec4ecd50940a5e8fc2bc5d478380c` (commission base
`621180cf460661aa95eb89da58553681688fa502`); hosted CI 46/46 PASS including
Incr Next Required, PR #476 public diff review APPROVE, CodeRabbit was
skipped/manual-review-required (NOT positive evidence), maintainer acceptance
PASS; merge is pending the status-only finalization head passing all required
gates. The commission covers typed active tracking per QueryCore, a key-free
session active stack, active checks before memo lookup, copied key-free
normalized Cycle witnesses, and independent Fresh and incremental cycle
semantics.

An old-trace Cycle requests recomputation; only a current-recompute Cycle
becomes the root ReadError. The scope also requires cleanup on every structured
exit and memo recovery after cycle introduction/removal. It does not include
cutoff/backdating, eviction or automatic retention, iterative evaluation or
stack-overflow protection, recovery values, error caching, parallelism,
Mount/Program, Canopy, ADR, or publication. Plan 015 defines the commissioned
failure matrix and gates.

K1.2 accepts only acyclic invocation graphs and must preserve the K1.1 public
capability surface, Fresh import independence, backend matrix, and zero current
`incr/` diff.

Blocked and uncommissioned until separate maintainer decisions:
cutoff/backdating, proof loss/eviction, Mount/Program, Canopy integration, ADR,
and publication.
