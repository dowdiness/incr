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
is **COMMISSIONED** (implementation not yet accepted). Its exact public
AlwaysChanged, `Eq`, and type-owned constructor surface remains subject to the
commissioned generated-interface compile probe. K1.5–K1.6 remain blocked and
uncommissioned.
