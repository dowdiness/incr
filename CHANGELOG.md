# Changelog

All notable changes to `dowdiness/incr` are documented in this file.

## [Unreleased]

### Added

- Added composable runtime hook registration so multiple observers can share one `Runtime` (#210). `Runtime::add_on_change_listener` / `Runtime::remove_on_change_listener` and `Runtime::add_derived_event_listener` / `Runtime::remove_derived_event_listener` return and accept public `ListenerId` handles. Additive listeners coexist with each other and with the existing singleton APIs, which remain source-compatible through reserved registry slots.
- Defined listener ordering and mutation rules for the new APIs. On-change listeners fire in registration order and snapshot before dispatch, so callbacks can add or remove listeners without affecting the current pass. Derived-event listeners run for each event in registration order and keep the existing idle mutation guard.
- Added `Derived::map` for target-facade value transformations on the same runtime. The mapped result does not require `Eq` because it uses no-backdate recomputation.
- Added `Derived::map_eq` for target-facade transformations whose mapped output implements `Eq`, preserving backdating so equal mapped values do not invalidate downstream dependents.
- Added `Derived::map2` / `Derived::map3` and `Derived::map2_eq` / `Derived::map3_eq` for target-facade multi-input transformations. The non-`Eq` forms use no-backdate recomputation; the `_eq` forms preserve backdating for equal mapped outputs; all four abort on cross-runtime inputs.

### Examples

These changes are in `examples/` workspace members, not the published `dowdiness/incr` library.

- Extended the `examples/incr_tea` browser renderer lifecycle (#209). `BrowserRenderer::detach` removes a root's DOM subtree but keeps its `Program` scope and watch alive, so the root can be re-mounted with state preserved. `BrowserRenderer::destroy` disposes the program when the component instance is gone. `BrowserRenderer::dispose` removes the renderer's two stored `ListenerId`s, destroys every mounted root, treats queued `requestAnimationFrame` callbacks as no-ops, and rejects new mounts.
- Added keyed child reconciliation and pure event-payload descriptors to `examples/incr_tea` (#211). `keyed_node` / `KeyedElem` preserves per-key DOM identity across insert, remove, and reorder operations, while DOM payload extraction stays at the browser boundary so cacheable `Html` values remain closure-free.
- Added tracked subscription reconciliation to `examples/incr_tea` (#244). Programs can declare a `Derived[Subscriptions]` map keyed by `SubKey`; the runtime diffs it into side-effect handles, updates same-key timers in place, stops removed timers, and the browser demo includes a timer subscription card.
- Added Incremental TEA benchmarks comparing watched `incr` view recomputation and keyed diff planning against dirty-cell and naive positional baselines (#243).
- Added `SubSpec::WindowKeydown` subscription family to `examples/incr_tea` (#290). `WindowKeydown(key_name, Msg)` reconciles a `window.addEventListener("keydown", ...)` listener — starting, updating in place (message or key name change), and stopping it without leaking browser listeners — alongside the existing `Timer` family. Demonstrated by a new `examples/incr_tea_7guis/keyboard_shortcut` task card.

## v0.10.1 (2026-06-24)

### Fixed
- Correct changelog: `batch_result` hook composability is backward-compatible, not breaking (additive APIs added alongside existing singletons)

## v0.10.0 (2026-06-24)

### Added
- Experimental `incr_tea` module: keyed VDOM diff, pure event-payload descriptors, renderer lifecycle, and Eq-safe HTML ergonomics
- `incr_tea` activation policy with inactive browser roots and subscription diff flow
- `incr_tea` spreadsheet proof-of-concept with event descriptor expansion
- `incr_tea` keyed DOM benchmark
- `incr_tea` 7GUIs stress test
- `incr_tea` semantic editor demo

### Changed
- Runtime on-change and derived-event hooks are now composable via `add_on_change_listener` / `add_derived_event_listener` (backward-compatible — existing `set_on_change` / `on_derived_event` remain available)
### Performance
- Optimize `incr_tea` keyed diff planner
- Compare adjacent UI view builds
- Add activation trigger probe

### Removed
- Remove deprecated `try` question syntax

### Documentation
- Document `incr_tea` architectural direction after Rabbita, Qwik, and Luna comparison
