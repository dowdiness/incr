# Incr Next testkit

This module owns the independent operation model, Fresh oracle, incremental
adapter, graph scenarios, and differential checks. `fresh` deliberately has no
dependency on `dowdiness/incr_next`.

Fresh is a from-scratch semantic oracle: every read evaluates the modeled graph
again and returns the value, missing-source result, or normalized error for that
operation. Its `Counter` observation is separate work evidence, not part of the
semantic comparison. Differential matching filters out `Counter` observations
and compares the remaining ordered observations. The incremental adapter's
counter is checked independently as kernel work evidence.

That separation is intentional. For example, the current baselines are Fresh
versus incremental work of keyed identity `3` versus `2`, chain `4` versus `2`,
diamond `10` versus `4`, unrelated publication `2` versus `1`, and selected or
dynamic publication `2` versus `2`. These differences must not weaken the
value/error comparison or make Fresh simulate memo reuse.

`Script` snapshots its operation array at construction. Query keys must keep
stable `Hash`/`Eq` behavior while a View or memo can retain them; mutating a key
is a caller-contract violation. Source payloads and Query results are also
caller-owned. A returned mutable Query result aliases the memo: the second
same-epoch read is a cache hit and observes that mutation. Callers should use
immutable values or make explicit copies at these boundaries.
