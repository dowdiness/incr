# Incr Next

`dowdiness/incr_next` is the pre-1.0 typed query kernel. It is independent of
`dowdiness/incr`.

K1.1 supplies the Store/Region/Source/Query/View lifetime and transaction
kernel. K1.2a adds query-local typed memo ownership and each successful memo's
direct forward trace. K1.2b verifies those traces to reuse unrelated
publications and recompute selected or dynamically changed branches. Query keys
use the public `K : Hash + Eq` bound; callers must keep key hashing and equality
stable while a key is retained. Structural kernel failures remain in the outer
`Result`, while domain failures are values inside `V` (for example
`V = Result[Value, DomainError]`).

K1.2c keeps failed structural recomputes on the current error channel,
preserves the last successful target authority, and releases temporary traces
before recovery. Native RC probes and an independent Fresh failure-recovery
scenario provide ownership and work evidence. K1.2 is **ACCEPTED** at
implementation head `12ec2404b676ef7864e353aeb3681c0fef6f20e3` and **MERGED** as
squash commit `db2ac77ac0362a7c5ff8d20887868cbdbb635aa8`. K1.3 invocation-level
cycle detection is **ACCEPTED** at implementation head
`e187b562f87ec4ecd50940a5e8fc2bc5d478380c`, finalized at status-only head
`a8115757662a6412e053aad9b7dc451f39a825c6`, and **MERGED** as squash commit
`5657cfc99734c9ac9e7093dd71819d6a0c48df87`. K1.4 typed cutoff and backdating
is **ACCEPTED AND MERGED** at implementation/validation head
`0036bdd199a685823b6769bf1acdac3f9b6b9014`, status-only head
`c88e724383ca5f3e817f30226a9fa23cf3ad7358`, and squash merge commit
`9d53d51d6ec6e282b8aa247442ee126acfe64a2d`. Hosted acceptance passed 46/46,
public diff review was APPROVE, maintainer acceptance was PASS, and squash-tree
equivalence passed. CodeRabbit skipped content review and is not positive
evidence; independent public review supplies review evidence. The selected
public surface preserves `Region::query` and adds explicit AlwaysChanged,
`Eq`, and type-owned constructors with private policy storage.

K1.5 private proof loss and ownership closure is **ACCEPTED AND MERGED** at
implementation head `064a80ac884f7c5588f123cc62dd784adeb26b48`, review-fix head
`378df40f7b84e1b6a3ebdb7f32299e2d628f1d54`, status-only head
`6de46abf19acb69cc5d5274b89a0ee780e48fb8d`, and squash merge commit
`4e66654d021435179116c0cffd56c0216b1bc664`. Hosted acceptance passed 46/46 at
the status-only head, maintainer acceptance passed, and squash-tree equivalence
passed. Its package-private per-key operation forgets one memo and all reuse
evidence without changing semantic state, then conservatively rematerializes
from a surviving View or downstream recipe. It adds no public eviction API or
retention policy.

K1.6 product-quality conformance has an **UNACCEPTED LOCAL CANDIDATE** at
implementation commit `a36b6d721db78160f8aadde1c5880694c0df2bb6`. Generated
and shrinkable Fresh differential tests, temporary package-private proof-loss
and work fixtures, and the local backend/boundary/ownership/workspace matrix
pass without widening production kernel source or public interfaces. See the
[K1.6 local validation record](docs/k1-6-validation.md). Local evidence fix
`170a996` adds operation-prefix failure localization and cutoff suffix/value
shrinking after public-branch review found both gaps. Exact-tree gates and
independent review must pass again. Implementation PR, hosted CI, maintainer
acceptance, merge, and the later product decision remain pending or
unauthorized.
