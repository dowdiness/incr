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

K1.2c is implemented: failed structural recomputes keep the current error
on the structural channel, preserve the last successful target authority, and
release temporary traces before recovery. Native RC probes and an independent
Fresh failure-recovery scenario provide ownership and work evidence. K1.2
implementation is still **NOT ACCEPTED**. K1.3 and later work remains blocked.
