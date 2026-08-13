# Incr Next testkit

This module owns the independent K1.1 operation model, Fresh oracle, incremental adapter, and differential scenarios. `fresh` deliberately has no dependency on `dowdiness/incr_next`.

K1.1 keeps mutable-key, mutable-source-payload, and mutable-result counterexamples as expected divergences: the kernel follows the snapshot-value caller contract and does not defensively copy.
