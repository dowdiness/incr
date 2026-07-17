# `incr_tea` Backlog

Operational task list for the `dowdiness/incr_tea` workspace module. Identity,
scope, and boundary commitments live in the
[module identity ADR](../../docs/decisions/2026-07-03-incr-tea-module-identity.md);
strategic direction lives in the
[Incremental TEA direction](../../docs/research/incr-tea-ui-direction.md)
research note. One line per item; details live in the linked issues.

## Open issues

Rough working order first (per the direction note's near-term roadmap), then
research items:

- [#288](https://github.com/dowdiness/incr/issues/288) — namespace-aware SVG
  support
- [#268](https://github.com/dowdiness/incr/issues/268) — reusable UI
  framework for the typed spreadsheet demo (first slice #269, event
  descriptors #272, and side-by-side proof #273 already shipped; remaining
  scope tracked on the issue)
- [#256](https://github.com/dowdiness/incr/issues/256) — explore
  WebComponent/custom-element mount boundaries
- [#190](https://github.com/dowdiness/incr/issues/190) — design opt-in
  constructive and deep-constructive UI task caches

- [#252](https://github.com/dowdiness/incr/issues/252) — research Qwik-style
  serializable and lazy UI boundaries

## Completed slices

- [#286](https://github.com/dowdiness/incr/issues/286) — Eq-safe controlled
  form support: closure-free `on_change`, controlled input/select values,
  boolean property repair, post-order select reconciliation, and browser smoke
  coverage. Future ergonomic constructors remain gated in the research note.

## Agenda (no issue yet)

- Machine composition evidence driver: test pure parent/child transitions,
  incarnation-safe late results, and aggregate `Program::stateful_cmd`
  integration before proposing a `Machine` type or per-key reactive graph.
- Demo/fixture disentanglement: separate the `renderer_wbtest` #251 fixture
  from `browser_editor_demo.mbt`, then move both browser demos to the
  `examples/incr_tea` harness. Trigger and plan shape recorded in the
  [identity ADR](../../docs/decisions/2026-07-03-incr-tea-module-identity.md).
