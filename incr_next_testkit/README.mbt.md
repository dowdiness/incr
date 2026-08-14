# Incr Next testkit

This module owns the independent operation model, Fresh oracle, incremental
adapter, graph scenarios, and differential checks. `fresh` deliberately has no
dependency on `dowdiness/incr_next`.

Fresh is a from-scratch semantic oracle: every read evaluates the modeled graph
again and returns the value, missing-source result, or normalized error for that
operation. Its `Counter` observation supplies separate work evidence.
Differential matching filters out `Counter` observations and compares the
remaining ordered observations. The incremental adapter's counter is checked
independently as kernel work evidence.

That separation is intentional. The current Fresh/incremental work baselines
are keyed identity `3/2`, chain `4/2`, diamond `10/4`, unrelated publication
`2/1`, selected publication `2/2`, and dynamic publication `3/2`. Value/error
comparison remains strict, and Fresh always evaluates from scratch.

`Script` has two phases: `initial_sources` creates the complete immutable Source
membership, and `operations` contains Reads, transactional publications to
existing Sources, or invocations of prepared error Views. Both arrays are
snapshotted at construction. Fresh and the incremental adapter build their
maps, Query graphs, Views, and error fixtures before replay. A missing read
remains `Missing`; an undefined `Set` or an operation incompatible with its
graph scenario is rejected during Script construction.

The DynamicBranch scenario starts with `0=0, 1=0`, then reads, sets `1=9`,
reads, sets `0=7`, and reads. Its Fresh/incremental work baseline is `3/2`.

Query keys must keep stable `Hash`/`Eq` behavior while a View or memo can retain
them; mutating a key is a caller-contract violation. Source payloads and Query
results are also
caller-owned. A returned mutable Query result aliases the memo: the second
same-epoch read is a cache hit and observes that mutation. Callers should use
immutable values or make explicit copies at these boundaries.
