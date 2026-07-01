# Changelog

All notable changes to `dowdiness/incr` are documented in this file.

## [Unreleased]

## [v0.12.0] - 2026-07-01

### Added

- **Added `Scope::adopt` and `Trackable` impls for facade types.** `scope.adopt(tracked)` registers a `Trackable` cell (e.g. `Derived`, `Input`, `Effect`) with the scope for deterministic disposal — the method-style companion to `add_tracked(scope, tracked)`. Seven facade types gained `Trackable` impls: `Derived`, `Input`, `InputField`, `ReachableDerived`, `EagerDerived`, `Effect`, and `Reactive`. The `Trackable` trait was moved to `incr/cells` and re-exported from `@incr`.
- **Added `Input::derived` for pipeline-uniform derived creation.** `input.derived(f)` creates a `Derived[U]` from an `Input[T]` by applying `f` on each read, replacing the `scope.derived(() => f(input.get()))` pattern with a chained `input.derived(f).map(g)`. Uses equality-based backdating (`U : Eq`).
- **Added `Derived::derived_no_backdate` for standalone no-backdate construction.** `Derived::derived_no_backdate(rt, compute, label?)` creates a `Derived[T]` without equality-based backdating, accepting output types that do not implement `Eq`. The target-facade companion to `Memo::new_no_backdate`.
- **Added `Input::derived2`, `Input::derived3`, and no-backdate variants.**
  Combine 2 or 3 `Input` cells into a `Derived` without passing `Runtime`
  explicitly. `price.derived2(qty, (p, q) => p * q)` replaces
  `Derived(rt, () => price.get() * qty.get())`. Three-input variant
  `derived3` handles 3-way combinations. `_no_backdate` variants accept
  output types that do not implement `Eq`. Includes cross-runtime guards
  matching `Derived::map2`.
- **Added `Runtime::input` method.** `rt.input(2, label="count")` creates an
  `Input` owned by the runtime without needing the `Input` type name in
  scope. The method is the primary creation path for new `Input` cells.
- **Added `Derived::accumulated_result` for Result-style accumulator reads.** `Derived::accumulated_result` is a `Result`-style alias for `Derived::accumulated` on the target facade, mirroring the existing `Memo::accumulated_result` compatibility alias. (#324)
- **Added `BrowserRenderer::flush_all()` for synchronous test flushes.** `renderer.flush_all()` synchronously flushes all mounted roots without waiting for an animation frame, drains after-flush commands, and fires the `after_flush` callback. Resets `frame_scheduled` after the full cycle completes so the next change triggers another flush cycle. (#339)

### Breaking Changes

- **Remove `Memo`, `MemoMap`, `HybridMemo` types.** These legacy compatibility
  types have been fully removed. Use `Derived`, `DerivedMap`, and
  `ReachableDerived` respectively. `Memo::new_memo` and
  `Memo::new_no_backdate` are gone — use
  `Derived::with_backdate` (public, requires `T : BackdateEq`) and
  `Derived::derived_no_backdate` directly.
- **Remove `Signal` type.** The legacy compatibility type `Signal[T]`
  has been removed. Use `Input[T]` instead. This includes:
  - `Signal(rt, v)` → `Input(rt, v)`
  - `Signal::new(rt, v)` → `Input::new(rt, v)`
  - `Signal::set_unconditional(v)` → `Input::force_set(v)`
  - `Signal::is_up_to_date()` → `Input::is_fresh()` or `Input::is_up_to_date()`
  - `create_signal(db, v)` → `create_input(db, v)`
  - `Scope::signal(self, v)` → `Scope::input(self, v)`
  - `SignalId[T]` → `InputId[T]`
  - `TrackedCell::as_signal()` → `TrackedCell::as_input()`
  - The `Input` wrapper struct in `target_facade.mbt` has been deleted;
    `Input[T]` is now the primary type in `input.mbt`.
  - `Readable` trait impl moved from `Signal` to `Input`.
  - `Freshness` trait impl for `Input` is unchanged.
### Migration

- `Memo(rt, compute)` → `Derived(rt, compute)`
- `MemoMap(rt, compute)` → `DerivedMap(rt, compute)`
- `HybridMemo(rt, compute)` → `ReachableDerived(rt, compute)`
- `memo.accumulated(acc)` → `derived.accumulated(acc)`
- `.inner.*` → direct method calls
- `Signal(rt, v)` → `Input(rt, v)`
- `Signal::set_unconditional(v)` → `Input::force_set(v)`
- `Signal::is_up_to_date()` → `Input::is_fresh()`
- `create_signal(db, v)` → `create_input(ctx, v)`
- `scope.signal(v)` → `scope.input(v)`
- `cell.as_signal()` → `cell.as_input()`
- `SignalId[T]` → `InputId[T]`

### Changed

- **Renamed `Derived` map family: safe default now uses short name.** `Derived::map_eq` → `Derived::map` (the safe `Eq`-backdating path), `Derived::map` → `Derived::map_no_backdate` (explicit no-backdate opt-in). Same convention for `map2`/`map2_eq` and `map3`/`map3_eq`. The short, ergonomic name is now the safe default. All callsites migrated.

- **Removed `type MemoId` from `@incr` re-exports.** `MemoId[T]` was a phantom-typed wrapper around `CellId` that matched the old `Memo` naming. With `Memo` already removed from the public facade, the standalone ID alias is inconsistent. The type remains defined in `dowdiness/incr/types` for internal use; use `CellId` directly or reference it via `@incr_types.MemoId` for white-box access.

## [v0.11.0] - 2026-06-26

### Added

- Added `Derived::map` for target-facade value transformations on the same runtime. The mapped result does not require `Eq` because it uses no-backdate recomputation.
- Added `Derived::map_eq` for target-facade transformations whose mapped output implements `Eq`, preserving backdating so equal mapped values do not invalidate downstream dependents.
- Added `Derived::map2` / `Derived::map3` and `Derived::map2_eq` / `Derived::map3_eq` for target-facade multi-input transformations. The non-`Eq` forms use no-backdate recomputation; the `_eq` forms preserve backdating for equal mapped outputs; all four abort on cross-runtime inputs.


### Changed

- **Removed `@incr.Memo` / `@incr.MemoMap` / `@incr.HybridMemo` re-exports.** The internal types `Memo`, `MemoMap`, `HybridMemo` remain in `incr/cells/` (still used as `Derived.inner` etc.) but are no longer re-exported from `@incr`. Use `Derived`, `DerivedMap`, `ReachableDerived` instead. Added forwarding methods `dependencies()`, `verified_at()`, `on_change()`, `clear_on_change()` to `Derived` and `observe()`, `is_disposed()` to `ReachableDerived`.
- **Removed `create_memo` / `create_memo_map` / `create_hybrid_memo` helpers.** Use `create_derived` / `create_derived_map` / `create_reachable_derived` (these accept `RuntimeContext`, mirroring the old `Database` pattern).
- **Removed `Readable` trait impls for `Memo` / `HybridMemo`.** The `Freshness` trait covers `Derived` and `ReachableDerived` via `is_fresh()`.

### Examples
These changes are in `examples/` workspace members, not the published `dowdiness/incr` library.

- Added `SubSpec::WindowKeydown` subscription family to `examples/incr_tea` (#290). `WindowKeydown(key_name, Msg)` reconciles a `window.addEventListener("keydown", ...)` listener — starting, updating in place (message or key name change), and stopping it without leaking browser listeners — alongside the existing `Timer` family. Demonstrated by a new `examples/incr_tea_7guis/keyboard_shortcut` task card.
- Added `Program::stateful` and `Program::stateful_cmd` helpers to `examples/incr_tea` (#287, #302), letting demos keep mutable state behind a `Program` while preserving the explicit command/update flow.
- Extended the typed-spreadsheet examples with multi-root locality instrumentation (#294, #295, #297, #298): per-region `InputField`s, per-root recompute stats, patch/skip counters, validation tests, and measurement docs for cross-root updates.

### Removed

- Removed deprecated event aliases (`MemoEvent`, `MemoEnteringEvent`, `MemoCompletedEvent`, `MemoAbortedEvent`) and deprecated runtime event helpers (`on_memo_event`, `clear_memo_event_listener`).
- Removed deprecated runtime one-shot read helpers (`Runtime::read`, `Runtime::read_hybrid`, `Runtime::read_reactive`) in favor of target-facade reads/watches.
- Removed the deprecated `gc_tracked` no-op and the deprecated `incr/pipeline` package.

### Migration

- Replace `MemoEvent` / `MemoEnteringEvent` / `MemoCompletedEvent` / `MemoAbortedEvent` with `DerivedEvent` / `DerivedEnteringEvent` / `DerivedCompletedEvent` / `DerivedAbortedEvent`.
- Replace `Runtime::on_memo_event` / `Runtime::clear_memo_event_listener` with `Runtime::on_derived_event` / `Runtime::clear_derived_event_listener` or the additive listener APIs.
- Replace `Runtime::read`, `Runtime::read_hybrid`, and `Runtime::read_reactive` with target-facade reads/watches (`Derived`, `ReachableDerived`, `EagerDerived`, `Watch`). Callers that still hold low-level `Memo` / `HybridMemo` / `Reactive` handles should migrate one-shot reads to `observe()`-based reads instead of the removed runtime helpers.
- Replace `gc_tracked(rt, tracked)` with `add_tracked(scope, tracked)` for compatibility `TrackedCell` owners, or `add_input_fields(scope, owner)` for target-style `InputField` owners.
- Remove imports of `dowdiness/incr/pipeline`; the package is gone. Define application-local build traits in downstream code instead of depending on `Sourceable` / `Parseable` / `Checkable` / `Executable`.

## [v0.10.1] - 2026-06-24

### Fixed
- Correct changelog: `batch_result` hook composability is backward-compatible, not breaking (additive APIs added alongside existing singletons)

## [v0.10.0] - 2026-06-24

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

[Unreleased]: https://github.com/dowdiness/incr/compare/v0.12.0...HEAD
[v0.12.0]: https://github.com/dowdiness/incr/compare/v0.11.0...v0.12.0
[v0.11.0]: https://github.com/dowdiness/incr/compare/v0.10.1...v0.11.0
[v0.10.1]: https://github.com/dowdiness/incr/compare/v0.10.0...v0.10.1
[v0.10.0]: https://github.com/dowdiness/incr/releases/tag/v0.10.0
