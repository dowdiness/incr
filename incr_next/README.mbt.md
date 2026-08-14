# Incr Next

`dowdiness/incr_next` is the pre-1.0 typed query kernel. It is independent of
`dowdiness/incr`.

K1.1 supplies the Store/Region/Source/Query/View lifetime and transaction
kernel. K1.2a adds query-local typed memo ownership and each successful memo's
direct forward trace. Query keys use the public `K : Hash + Eq` bound; callers
must keep key hashing and equality stable while a key is retained. Structural
kernel failures remain in the outer `Result`, while domain failures are values
inside `V` (for example `V = Result[Value, DomainError]`).

Forward trace verification and green-path reuse are still pending K1.2b. K1.3
and later work remains deferred.
