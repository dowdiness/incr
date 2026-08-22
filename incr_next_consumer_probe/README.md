# Incr Next Consumer Probe

**Reader:** Reviewers of Plan 016 K2.1 public-consumer evidence.

**Decision:** Keep one standalone executable that exercises the committed public
`dowdiness/incr_next` interface without current Incr, testkit, private helpers,
or product API changes.

**Keep until:** The K2 disposition is accepted.

**Disposition:** At K2 closure, retain this module as a public-consumer
regression fixture or delete it with the disposition rationale.

This module is evidence for
[Plan 016 §3](../plans/016-incr-next-usability-and-distribution.md#3-k21-consumer-probe),
not the executable product documentation commissioned for K2.2. K2.2 remains
blocked until K2.1 is accepted.

Its only non-core dependency is the versioned public
`dowdiness/incr_next` module. The executable and its test run the same fixed
dynamic-query, atomic-transaction, and Region-close scenario. Validation uses
`moon check`, `moon test`, and `moon run` for default, native, JS, and wasm-gc
targets; accepted commands and raw outputs belong in the K2.1 review evidence.
