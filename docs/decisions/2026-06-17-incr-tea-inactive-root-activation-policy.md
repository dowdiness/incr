# ADR: Incremental TEA Inactive-Root Activation Policy

**Date:** 2026-06-17
**Status:** Accepted
**Issue:** [#280](https://github.com/dowdiness/incr/issues/280)

## Context

This decision is scoped to `examples/incr_tea`. Inactive roots already have an
explicit lifecycle: `BrowserRenderer::deactivate(root)` keeps DOM, `Program`, and
view `Watch` alive while scheduled frames skip watched-view reads;
`BrowserRenderer::activate(root)` marks the root active and performs one catch-up
flush.

The [cohort measurements](../performance/2026-06-16-incr-tea-shared-vs-independent-inactive-root-cohorts.md)
show shared-`Program` roots are cheaper than independent roots in every measured
16-root case. The [trigger-overhead probe](../performance/2026-06-17-incr-tea-activation-trigger-overhead.md)
then showed that IntersectionObserver-triggered activation includes browser
scheduling latency of roughly 8–16 ms, while direct activation remains
sub-millisecond for one root and roughly 5.4 ms shared / 7.1 ms independent for
16-root activate-all.

## Decision

Use a **manual-first hybrid** policy:

- product/semantic UI actions call `BrowserRenderer::activate(root)` directly
  before the root becomes interactive;
- visibility, near-viewport, idle, or scheduler triggers may request early
  activation only as side-effect-safe, advisory prewarm;
- same-workspace inactive DOM roots should prefer shared-`Program` ownership;
- do not add a core `incr` activation scheduler unless an example-local
  prototype exposes a concrete library gap.

## Rejected alternatives

- **Pure IntersectionObserver activation** as the sole policy: measured observer
  scheduling latency is too high for first-frame editor reveals and focus/keyboard
  paths. It remains useful only as a side-effect-safe prewarm hint.
- **Idle-only activation** as the correctness path: idle time is not guaranteed
  before a reveal and can be starved by busy editor work.
- **Independent root/program per hidden view by default:** measured 16-root
  same-workspace cohorts are consistently slower than shared ownership.
- **Always activate all inactive roots:** one-root activation stays bounded by
  one root; activate-all should be reserved for actions that make all roots
  interactive.

## Consequences

- No core `incr` activation scheduler is added.
- The renderer lifecycle contract remains `deactivate` / `activate`; optional
  prewarm is an example/browser policy on top.
- Because `activate` drains after-flush work and marks a root active, prewarm is
  valid only when early activation is acceptable for that root. A hidden root
  with focus or other DOM-dependent after-flush effects should wait for the
  semantic `show` action unless a later prototype adds a side-effect-free
  catch-up path.
- The next validation step is an example-local controller/helper with semantic
  operations such as `show(root)` and `hide(root)`, plus optional safe prewarm.
  Compare direct semantic activation, prewarm hit, and prewarm miss against the
  recorded shared-`Program` baselines before hardening any API.
