# Incr Next

`dowdiness/incr_next` is the pre-1.0 typed query kernel commissioned for K1.1. It is independent of `dowdiness/incr`.

K1.1 provides opaque `View` recipes, tracked `QueryContext` reads, canonical `Source` views, no-memo `Query[K, V]`, Store-owned revisions, transaction-only publication, same-Store cross-Region reads, and explicit Region lifetime. Each Query callback receives a child invocation context; `QueryContext::revision()` returns `Result[Revision, ReadError]` and reports `ExpiredQueryContext` after that callback exits.

This is alpha software. Typed memo/forward verification, cycles, cutoff, eviction, Mount/Program, Canopy integration, ADR, and publication are not part of K1.1.
