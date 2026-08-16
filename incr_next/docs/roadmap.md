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

K1.3 invocation-level cycle detection is **ACCEPTED** at implementation head
`e187b562f87ec4ecd50940a5e8fc2bc5d478380c`, finalized at status-only head
`a8115757662a6412e053aad9b7dc451f39a825c6`, and **MERGED** as squash commit
`5657cfc99734c9ac9e7093dd71819d6a0c48df87`. Hosted CI, independent public diff
review, maintainer acceptance, and squash-tree equivalence pass. CodeRabbit
skipped content review and is not positive evidence.

K1.4 typed cutoff and backdating is **IMPLEMENTATION COMPLETE** and **MAINTAINER
ACCEPTED** at implementation/validation head
`0036bdd199a685823b6769bf1acdac3f9b6b9014` (component heads
`fad637a57e668924156a50c7af8b4f2e8c58fa59`,
`9318408740b6865c14735da0be922a872e2c21bb`,
`16e6a1fc1a4cb48ac1ba11463096595398115472`,
`f84d9589d4b979b711036263255f6a3f2e684525`); hosted acceptance PASS
46/46, public diff review APPROVE, maintainer acceptance PASS; **MERGE
PENDING** — final merge authorized only after status-only current-head required
checks are green. CodeRabbit skipped content review and is not positive
evidence; independent public review supplies review evidence. The
generated-interface probe selected explicit
AlwaysChanged, `Eq`, and type-owned constructors while preserving the existing
`Region::query` baseline. Successful recomputation installs the newest value
and dynamic trace; propagation-equivalent results retain old `changed_at`,
preserving Cycle/failure atomicity while allowing downstream work to skip.

K1.4 exposes no arbitrary predicate or `TrustedCutoff`; direct reads always see
the newest value, while only admissible downstream verification may reuse old
observations. The 24-cell, workspace, ownership, interface, negative, and
boundary gates pass. K1.5–K1.6 remain blocked and uncommissioned. Proof
loss/eviction, automatic retention, Mount/Program, Canopy integration, ADR, and
publication remain unauthorized and require separate maintainer decisions.
