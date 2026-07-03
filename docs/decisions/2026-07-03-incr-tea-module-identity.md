# ADR: `incr_tea` Module Identity

**Date:** 2026-07-03
**Issue:** [#344](https://github.com/dowdiness/incr/issues/344) (Stage 2)

## Status

Accepted

## Decision

`dowdiness/incr_tea` (the workspace module at `incr_tea/`, created by the
Stage 1 split in [PR #349](https://github.com/dowdiness/incr/pull/349)) is an
**experimental TEA UI framework whose primary purpose is to pressure-test the
`dowdiness/incr` public facade under real UI workloads**. It stays
in-workspace, imports only the `dowdiness/incr` root facade, and tracks its
work in [`incr_tea/docs/backlog.md`](../../incr_tea/docs/backlog.md).

It is **not** a published library, **not** an API-stability contract, and
**not** a Rabbita replacement. Anyone proposing to publish it, promise
stability, or extract it to its own repository must supersede this ADR first.

## Context

Stage 1 (PR #349) mechanically moved the TEA framework out of
`examples/incr_tea` into its own workspace module; the name
(`dowdiness/incr_tea`) and the in-workspace trajectory were decided on #344.

What the split did not record is the module's identity. Before the split, the
framework was 10k+ LOC of example-scoped code with three in-repo consumers,
six open feature issues, and no owner document. It was large enough to exert
design pressure on the core (the
[composable-hooks ADR](2026-06-09-composable-runtime-hooks.md) exists because
of it) without any stated contract about how that pressure is allowed to
flow. The
[2026-07-03 workspace boundary assessment](../design/specs/2026-07-03-workspace-boundary-assessment.md)
scoped Stage 2 to exactly this: an ADR naming the module's scope, its import
contract, and its backlog.

## Non-goals

- **No code moves.** This ADR is docs-only; the mechanical split already
  happened in Stage 1.
- **No execution of demo/fixture disentanglement.** Recorded as follow-up
  with a plan shape and trigger (see Follow-up); deliberately not done here.
- **Not the compatibility-retirement decision.** The Stage 3 breaking window
  ([#345](https://github.com/dowdiness/incr/issues/345)) is a separate,
  user-gated `dowdiness/incr` decision; this ADR only records that it does
  not extend to `incr_tea`.

## Considered Options

**Trajectory** (raised in the workspace boundary assessment and #344):

- **Option: In-workspace module — chosen.**
  What it means: `incr_tea/` stays a member of this repository's `moon.work`.
  Pros: the core-feedback loop (framework work surfacing `incr` API gaps)
  stays cheap — one workspace, one CI, atomic pin bumps.
  Cons: repository carries a 10k+ LOC non-library member.
  Why chosen: the feedback loop is the module's primary purpose; the
  assessment explicitly recommended in-workspace for this reason.
- **Option: Eventual own repository.**
  What it means: extract `dowdiness/incr_tea` to its own repo/module.
  Pros: cleaner separation; independent versioning.
  Cons: cross-repo friction on every core API experiment.
  Why not chosen: kills the cheap feedback loop; reopening this requires
  superseding this ADR.

**Scope framing** (raised during the Stage 2 decision):

- **Option: Core-feedback framework — chosen.**
  What it means: features are accepted when they exercise or inform the
  `dowdiness/incr` core; no publish or stability ambitions.
  Pros: matches the trajectory rationale; keeps #345-style obligations off
  the module; Rabbita remains the primary live UI framework in the wider
  canopy stack, with `incr_tea` competing only as a measurement subject in
  the compare benches.
  Cons: caps the module's ambition; contributors wanting a "real" framework
  must supersede this ADR.
  Why chosen: consistent with the in-workspace decision and with Rabbita's
  standing role.
- **Option: Framework in its own right.**
  What it means: end-user value drives features; aim at eventual publish.
  Why not chosen: raises the API-stability bar (and would pull #345-style
  breaking windows onto the module) without a driver — the module has no
  external consumers.
- **Option: Dual identity, framework-first.**
  What it means: framework ambitions co-equal with core pressure-testing,
  while staying unpublished.
  Why not chosen: blurs acceptance criteria for features; the single-purpose
  framing is falsifiable, this one is not.

## Consequences

- `incr_tea` gets an owner-document trail: this ADR for identity,
  [`incr_tea/docs/backlog.md`](../../incr_tea/docs/backlog.md) for work, and
  the [Incremental TEA direction](../research/incr-tea-ui-direction.md)
  research note for strategic rationale.
- The import contract becomes a named commitment: the framework module
  imports **only the `dowdiness/incr` root facade** — never
  `dowdiness/incr/cells`, `/types`, or anything deeper — plus
  `moonbitlang/core` packages. Adjacent-framework dependencies (`rabbita`,
  `luna`, `signals`, `mizchi/js`) live only in the `examples/incr_tea`
  browser harness. Weakening either is now an ADR-level change, not a script
  tweak.
- `incr_tea`'s version number is a workspace-internal pin with no
  consumer-facing meaning. `dowdiness/incr` version bumps continue to go
  through `scripts/bump-version.sh`, which updates `incr_tea`'s pin
  atomically like any other member; the script does not touch `incr_tea`'s
  own version.
- `incr_tea`'s API may break without deprecation windows.

## Compatibility and API Impact

No known impact. This ADR is docs-only: no MoonBit code, no public API, no
`.mbti`, no re-exports, and no module import graph changes. Verified in the
current tree: `incr_tea/moon.pkg` imports `dowdiness/incr` plus
`moonbitlang/core` packages only, and `incr_tea/moon.mod` pins
`dowdiness/incr` alone — the contract above describes the existing state
rather than changing it.

## Implementation Notes

Shipped alongside this ADR (all docs/metadata, same PR):

- `incr_tea/docs/backlog.md` seeded with the six retargeted TEA issues
  (#268, #286, #288, #256, #252, #190).
- `docs/README.md` index rows for this ADR and the backlog.
- The six issues retitled from their `examples/incr_tea` framing to the
  module (`incr_tea:` prefix).

## Validation

- **Import contract:** CI-enforced by `scripts/check-workspace-boundaries.sh`
  (#343) in the "Check architecture boundaries" job. Its member loop covers
  every `moon.work` member except `incr` itself, so `incr_tea/` is checked
  under both invariant A (facade-only imports) and invariant B (pin ==
  library version); the checker's parsing is regression-guarded by
  `scripts/check-workspace-boundaries-selftest.sh`. Coverage of the new
  member was verified with a known-positive control in Stage 1.
- **Identity drift:** any PR that publishes `incr_tea`, adds a deprecation
  window to it, or moves adjacent-framework deps into the module contradicts
  this ADR and should be caught in review by this document.

## Follow-up

Deferred work; none of it is decided beyond what is written here.

- **Demo/fixture disentanglement.** Stage 1 surfaced two couplings that
  intentionally moved *with* the framework rather than staying in the
  harness: `browser_editor_demo.mbt` doubles as the package-private fixture
  for `renderer_wbtest`'s #251 regression test (and `browser_demo.mbt`
  consumes the same `priv` fixtures), while `dom_bench.mbt` and the
  `ui_compare_dom_*` group are in-package benches that use package-private
  renderer/`Html` internals by design. The benches are correctly placed and
  stay. The demos are not: the plan shape is to first separate the wbtest
  fixture from the demo (a test-only fixture that `renderer_wbtest` owns),
  then move both browser demos to the `examples/incr_tea` harness.
  **Trigger:** the next change that touches the renderer fixtures, or any
  move toward publishing the module — whichever comes first. Until then, do
  nothing.
- **Stage 3 breaking window (#345).** Date/version is a separate user
  decision on the `dowdiness/incr` track.
- **Backlog execution.** The retargeted issues live in
  [`incr_tea/docs/backlog.md`](../../incr_tea/docs/backlog.md); working order
  is recorded there, not here.
