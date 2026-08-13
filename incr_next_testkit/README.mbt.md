# Incr Next testkit

This module owns the independent operation model, Fresh oracle, incremental
adapter, graph scenarios, and differential checks. `fresh` deliberately has no
dependency on `dowdiness/incr_next`.

`Script` snapshots its operation array at construction. The K1.1 snapshot-value
contract does not defensively copy values captured as mutable Query keys, Source
payloads, or Query results. Executable counterexamples document the exact
outcomes: mutating a key changes a later read, mutating a Source payload changes
its later view, and mutating a returned Query result changes the next uncached
result. Callers must provide immutable values or make explicit copies.
