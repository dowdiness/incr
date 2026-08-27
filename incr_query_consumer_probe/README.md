# Incr Query Consumer Probe

**Reader:** Reviewers of Plan 016 K2.1 public-consumer evidence.

**Decision:** Keep one standalone executable that exercises the committed public
`dowdiness/incr_query` interface without current Incr, testkit, private helpers,
or product API changes.

**Keep until:** Superseded by an accepted public-consumer fixture.

**Disposition:** Retained at K2 closure as the public-consumer regression
fixture for future packaging and alpha-publication work.

**Status:** K2.1 accepted and squash-merged as `93eb59b6`; K2.2 accepted and
squash-merged as `9360816f`; K2.3 accepted and squash-merged as `3007f5ff`; K2
is complete.

This module is evidence for
[Plan 016 §3 at final disposition](https://github.com/dowdiness/incr/blob/e30cf501db5a88d7a3764e8703c1f01b2077e046/plans/016-incr-next-usability-and-distribution.md#3-k21-consumer-probe),
not the executable product documentation accepted for K2.2. The accepted probe
was reused by K2.3 and remains the public-consumer regression fixture for
packager migration and any later alpha-publication commission.

Its only non-core dependency is the versioned public
`dowdiness/incr_query` module. The executable and its test run the same fixed
dynamic-query, atomic-transaction, and Region-close scenario. Validation uses
`moon check`, `moon test`, and `moon run` for default, native, JS, and wasm-gc
targets; accepted commands and raw outputs belong in the K2.1 review evidence.
