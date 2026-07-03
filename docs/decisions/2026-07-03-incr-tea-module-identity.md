# ADR: `incr_tea` Module Identity

**Date:** 2026-07-03
**Status:** Accepted
**Issue:** [#344](https://github.com/dowdiness/incr/issues/344) (Stage 2)

## Context

Stage 1 ([PR #349](https://github.com/dowdiness/incr/pull/349)) moved the TEA
framework out of `examples/incr_tea` into its own workspace module,
`dowdiness/incr_tea@0.1.0` at `incr_tea/`. The mechanical split is done; the
name and the in-workspace trajectory were decided on #344. What the split did
not record is the module's identity: what it is for, what its boundary
commitments are, and where its work is tracked. Before the split, the
framework was 10k+ LOC of example-scoped code with three in-repo consumers,
six open feature issues, and no owner document — large enough to exert design
pressure on the core (the composable-hooks ADR exists because of it) without
any stated contract about how that pressure is allowed to flow.

This ADR is docs-only. It records identity and boundary decisions; it moves
no code.

## Decision

### Scope — what `incr_tea` is

`incr_tea` is an experimental TEA (Model/Msg/`update`/`view`) UI framework
whose **primary purpose is to pressure-test the `dowdiness/incr` public
facade under real UI workloads**: incremental keyed-diff rendering,
subscriptions, commands, stateful components, and root activation policies,
all built on `Input`/`Derived`/`Watch` cells. Framework features are accepted
when they exercise or inform the core; the in-workspace placement exists to
keep that core-feedback loop cheap (per the
[2026-07-03 workspace boundary assessment](../design/specs/2026-07-03-workspace-boundary-assessment.md)).

### Scope — what `incr_tea` is not

- **Not a published library.** It is not on mooncakes; its version number is
  a workspace-internal pin with no consumer-facing meaning.
- **Not a stability contract.** Its API may break without deprecation
  windows. The Stage 3 compatibility-retirement window (#345) is a
  `dowdiness/incr` concern and does not extend to `incr_tea`.
- **Not a Rabbita replacement.** Rabbita remains the primary, live UI
  framework in the wider canopy stack; `incr_tea` competes with it only as a
  measurement subject in the compare benches.

### Import contract

- The framework module imports **only the `dowdiness/incr` root facade** —
  never `dowdiness/incr/cells`, `/types`, or anything deeper — plus
  `moonbitlang/core` packages. This is CI-enforced by
  `scripts/check-workspace-boundaries.sh` (#343); this ADR promotes it from
  an incidental checker rule to a named commitment.
- Adjacent-framework dependencies (`rabbita`, `luna`, `signals`, `mizchi/js`)
  live **only in the `examples/incr_tea` browser harness**, which hosts the
  subpackage mains, web assets, and cross-framework compare benches. The
  framework module itself stays dependency-clean.

### Backlog

The module's work is tracked in
[`incr_tea/docs/backlog.md`](../../incr_tea/docs/backlog.md), seeded with the
six open TEA issues retargeted from their `examples/incr_tea` framing
(#268, #286, #288, #256, #252, #190). The
[Incremental TEA direction](../research/incr-tea-ui-direction.md) research
note remains the strategic rationale; the backlog is the operational list.

### Demo/fixture disentanglement — agenda, not executed here

Stage 1 surfaced two couplings that intentionally moved **with** the
framework rather than staying in the harness:

- `browser_editor_demo.mbt` doubles as the package-private fixture for
  `renderer_wbtest`'s #251 regression test, and `browser_demo.mbt` consumes
  the same `priv` fixtures. Exposing them would have been API redesign,
  out of scope for a byte-equivalent move.
- `dom_bench.mbt` and the `ui_compare_dom_*` group are in-package benches
  that use package-private renderer/`Html` internals by design.

The benches are correctly placed and stay. The demos are not: the plan shape
is to first separate the wbtest fixture from the demo (a test-only fixture
that `renderer_wbtest` owns), then move both browser demos to the
`examples/incr_tea` harness. Trigger to execute: the next change that touches
the renderer fixtures, or any move toward publishing the module — whichever
comes first. Until then, do nothing.

## Consequences

- `incr_tea` gets an owner document trail: this ADR for identity, the module
  backlog for work, the research note for direction.
- The boundary checker's coverage of `incr_tea` (verified with a
  known-positive control in Stage 1) is now backed by a recorded commitment,
  so weakening it is an ADR-level change, not a script tweak.
- `dowdiness/incr` version bumps continue to go through
  `scripts/bump-version.sh`, which updates `incr_tea`'s pin atomically like
  any other member. `incr_tea`'s own version stays untouched by that script
  and carries no publish obligation.
- Anyone proposing to publish `incr_tea`, promise API stability, or extract
  it to its own repository must supersede this ADR first.
