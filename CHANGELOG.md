# Changelog

All notable changes to `dowdiness/incr` are documented in this file.

## [Unreleased]

### Added

- Added `Derived::map` for target-facade value transformations on the same runtime. The mapped result does not require `Eq` because it uses no-backdate recomputation.
- Added `Derived::map_eq` for target-facade transformations whose mapped output implements `Eq`, preserving backdating so equal mapped values do not invalidate downstream dependents.
- Added `Derived::map2` / `Derived::map3` and `Derived::map2_eq` / `Derived::map3_eq` for target-facade multi-input transformations. The non-`Eq` forms use no-backdate recomputation; the `_eq` forms preserve backdating for equal mapped outputs; all four abort on cross-runtime inputs.

### Examples

These changes are in `examples/` workspace members, not the published `dowdiness/incr` library.

- Added `SubSpec::WindowKeydown` subscription family to `examples/incr_tea` (#290). `WindowKeydown(key_name, Msg)` reconciles a `window.addEventListener("keydown", ...)` listener — starting, updating in place (message or key name change), and stopping it without leaking browser listeners — alongside the existing `Timer` family. Demonstrated by a new `examples/incr_tea_7guis/keyboard_shortcut` task card.
- Added `Program::stateful` and `Program::stateful_cmd` helpers to `examples/incr_tea` (#287, #302), letting demos keep mutable state behind a `Program` while preserving the explicit command/update flow.
- Extended the typed-spreadsheet examples with multi-root locality instrumentation (#294, #295, #297, #298): per-region `InputField`s, per-root recompute stats, patch/skip counters, validation tests, and measurement docs for cross-root updates.

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
