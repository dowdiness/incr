# ADR: Machine Composition Remains Domain-Level Pure Functions

**Date:** 2026-07-14
**Status:** Accepted

## Context

The completed Machine composition experiment exercised parent/child composition,
semantic identity, add/remove/reorder, stale/duplicate completion rejection,
history, commands, and one aggregate `Program::stateful_cmd` through a
semantic-editor driver. Circle Drawer provided a second natural-form
comparison.

The 2026-07-15 follow-up hardened request-sequence storage and instrumentation.
Performance evidence passed all structural gates and all three 256-child p95
runs remain below the 16.7 ms synchronous JS budget.

## Decision

Keep Machine composition as ordinary pure reducers and functions plus small
domain types and semantic IDs, integrated through the aggregate `Program`.

Do **not** add any of the following from this evidence:

- a shared or public `Machine` type;
- a core keyed facade;
- a per-key reactive graph;
- a new `incr` Runtime API.

The domain-specific incarnation/request-sequence stale-result protocol does
not generalize from the second driver.

## Rationale

- Responsibilities that repeat across drivers are already ordinary functions
  and domain data.
- Non-repeating command/stale-result protocol is domain-specific.
- Aggregate structural and performance gates passed without measured per-key
  ownership need.
- Circle Drawer repeats the aggregate reducer, stable semantic identity,
  selected-child state lens, and history restoration — but does not repeat
  validation commands, asynchronous completion routing, incarnation
  allocation, request sequencing, or stale-result classification.

## 2026-07-15 follow-up

The invariant/instrumentation hardening removed duplicated request-sequence
storage but did not change the decision. The single-source sequence and
observer-disabled browser timing remain as regression evidence.

## Consequences

- Stage C per-key experiment remains gated by aggregate measurements missing a
  named locality or lifetime target.
- No Runtime lifecycle abstraction is authorized by this evidence.
- Performance snapshots remain as regression evidence.

## Non-goals

- No shared `Machine` type, core keyed facade, per-key reactive graph, or
  new `incr` Runtime API from this evidence.
- No per-key Scope ownership or detachable child Scopes.
- No generative-UI runtime plan.

## Reopen criteria

The original decision separates a narrow vocabulary extraction from a full
shared `Machine`. Both stages have independent reopen triggers.

**Stage 1 — narrow vocabulary extraction.** The first candidate is an
opaque cross-package request token plus one pure completion-classification
function with outcomes `accepted | retired | superseded | duplicate | unexpected`.
Issuance, retirement, cancellation, restore policy, command mapping, and
lifecycle ownership remain domain decisions. Reopen this extraction when
either of the following holds:

1. A second real consumer independently repeats the same classification
   semantics with domain-independent vocabulary.
2. One production consumer has a compile-time invariant that docs and local
   representation cannot protect, and a pre-registered defect experiment
   shows the candidate converts a silent production-shaped failure into a
   compile error.

**Stage 2 — full shared `Machine`.** Reconsider only when lifecycle and
imperative-shell wiring also repeat naturally across application-shaped
drivers. Repeated pure reducers and domain IDs alone are insufficient.

**Per-key reactive experiment gate (independent).** The aggregate design
misses a named locality or lifetime target that per-key reactive ownership
plausibly fixes, with ownership and retirement semantics specified.

## Verification and evidence

- [2026-07-14 Machine composition aggregate evidence](../performance/2026-07-14-machine-composition-evidence.md)
- [2026-07-15 Machine composition follow-up](../performance/2026-07-15-machine-composition-follow-up.md)

## Retired source documents

The following research notes were distilled into this ADR and deleted. They
are recoverable in Git history:

- `docs/research/2026-07-14-machine-composition-implementation-report.md`
- `docs/research/2026-07-14-machine-composition-abstraction-decision.md`

The performance snapshots remain as evidence.
