# Incr Next testkit

This module owns the independent operation model, Fresh oracle, incremental
adapter, graph scenarios, and differential checks. `fresh` deliberately has no
dependency on `dowdiness/incr_next`.

`Script` snapshots its operation array at construction. Query keys must keep
stable `Hash`/`Eq` behavior while a View or memo can retain them; mutating a key
is a caller-contract violation. Source payloads and Query results are also
caller-owned. A returned mutable Query result aliases the memo: the second
same-epoch read is a cache hit and observes that mutation. Callers should use
immutable values or make explicit copies at these boundaries.
