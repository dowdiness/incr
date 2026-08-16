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

K1.4 typed cutoff and backdating is **ACCEPTED AND MERGED** at
implementation/validation head
`0036bdd199a685823b6769bf1acdac3f9b6b9014`, status-only head
`c88e724383ca5f3e817f30226a9fa23cf3ad7358`, and squash merge commit
`9d53d51d6ec6e282b8aa247442ee126acfe64a2d`. Hosted acceptance passed 46/46,
public diff review was APPROVE, maintainer acceptance was PASS, and squash-tree
equivalence passed. CodeRabbit skipped content review and is not positive
evidence; independent public review supplies review evidence. The
generated-interface probe selected explicit AlwaysChanged, `Eq`, and type-owned
constructors while preserving the existing `Region::query` baseline.
Successful recomputation installs the newest value and dynamic trace;
propagation-equivalent results retain old `changed_at`, preserving
Cycle/failure atomicity while allowing downstream work to skip.

K1.4 exposes no arbitrary predicate or `TrustedCutoff`; direct reads always see
the newest value, while only admissible downstream verification may reuse old
observations. The 24-cell, workspace, ownership, interface, negative, and
boundary gates pass.

K1.5 private proof loss and ownership closure is **ACCEPTED AND MERGED** at
implementation head `064a80ac884f7c5588f123cc62dd784adeb26b48`, review-fix head
`378df40f7b84e1b6a3ebdb7f32299e2d628f1d54`, status-only head
`6de46abf19acb69cc5d5274b89a0ee780e48fb8d`, and squash merge commit
`4e66654d021435179116c0cffd56c0216b1bc664`. The status-only head passed 46/46
hosted checks, including `Incr Next Required`, with no pending or failed checks;
maintainer acceptance and squash-tree equivalence passed.

The package-private operation for one key forgets the memo value, trace, stamps,
`MemoId`, and cutoff-comparison evidence without changing `Revision`,
`ChangeEpoch`, Query/View definitions, policy, Region generation, or Source
state. A later read rematerializes from a surviving View or downstream
`QueryCore` plus typed recipe as initial success: new `MemoId`, current
`verified_at` and `changed_at`, zero cutoff calls, and conservative downstream
recomputation. Per-entry and dynamic-trace isolation, failure/Cycle non-install
and recovery, phase/lifetime rejection, Region-close ownership completion, and
native RC/finalizer evidence pass local, hosted, public-diff, and maintainer
gates.

K1.6 product-quality conformance has an **UNACCEPTED LOCAL CANDIDATE** at
implementation commit `a36b6d721db78160f8aadde1c5880694c0df2bb6`. K1.6a–c
locally add generated and shrinkable Fresh differential evidence, temporary
package-private proof-loss/work fixtures, and the complete backend, boundary,
ownership, and workspace matrix without changing production kernel source or
public interfaces. The [K1.6 local validation record](k1-6-validation.md)
captures that evidence.

Public-branch review later found that reports localized observations rather
than operations and that cutoff failures did not shrink.
Local evidence fix `170a996` addresses both without changing production kernel
source or interfaces. Exact-tree gates passed, then review required real prefix
replay coverage rather than synthetic length-only assertions. Follow-up
`d013186` exercises Fresh and Incremental replay for setup-dependent scenarios.
Exact-tree gates and independent review must pass once more. Implementation PR,
hosted CI, maintainer acceptance, merge, and the separate product decision
remain pending or unauthorized.

The commissioned scope permits no public eviction, retention, counter, debug,
or explain surface. Mount, Program/Port/Formula, Canopy integration, ADR,
publication, and representation optimization remain blocked. Plan 015 remains
**IN PROGRESS**.
