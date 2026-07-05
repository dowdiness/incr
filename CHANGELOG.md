# Changelog

All notable changes to `dowdiness/incr` are documented in this file.

## [v0.14.0] - 2026-07-05

Breaking release: public API boundary cleanup (Phases 0–2 of
`docs/plans/2026-07-05-public-api-boundary-cleanup.md`; PRs #353/#354/#355/#357).
Every removed or changed name lists its replacement below.

### Removed (breaking)

- **`Accumulator::new(rt~, ...)` removed.** Replaced by positional constructor
  `Accumulator(rt, label?)`. The `Accumulator::Accumulator(Runtime, label?)`
  constructor is now the canonical form — same semantics.


- **Ghost handle types.** `InputId[T]`, `MemoId[T]`, `RelationId[T]`, and
  `FunctionalRelationId[K, V]` are deleted from `@incr/types`, and the
  `InputId` / `RelationId` root re-exports are dropped. They were leftovers
  of the handle types removed in v0.12/v0.13 — no API produced or consumed
  them, so there is no migration. `RuleId` (returned by `Runtime::new_rule`)
  is unchanged; `ReactiveId[T]` stays in `@incr/types` because the
  `EagerDerived[T]` implementation still uses it internally.

### Changed (breaking)

- **Invariant-bearing types closed.** `Revision`, `InternId`, and
  `InternTable[T]` are now `pub` instead of `pub(all)`: consumers can no
  longer construct them via struct literals. Construct through the existing
  API instead — `Revision::initial()` / `.next()`,
  `InternTable::new()` / `.intern(value)`. `InternTable`'s fields are
  additionally `priv`: its mutable internals (`values`, `to_id`) are no
  longer readable from outside, closing the interior-mutation hole where
  `table.values.push(...)` could bypass `intern` (verified by a
  known-positive probe). `Revision.value` / `InternId.index` stay readable
  (`Int` fields — reads copy). `CycleError::new` remains public because the
  kernel package must construct it and MoonBit has no sibling-only
  visibility; it is documented as library-internal.

- **`Input::get_result` / `InputField::get_result` return `Result[T, ReadError]`**
  instead of `Result[T, CycleError]`. This aligns the read channel with the
  Honest Read-Error Ownership spec (`ReadError = Cycle(CycleError) | Disposed(CellId)`).
  A disposed input now returns `Err(ReadError::Disposed(id))` instead of aborting.
  The `Cycle` variant is structurally unreachable for inputs (they have no
  dependencies) — documented in the shared `ReadError` type in `@incr/types`.
  **Migration.** Match on `ReadError::Disposed(id)` instead of relying on the
  absent abort. Prior code matching `Err(CycleError)` and `fail("unreachable")`
  is unaffected — `ReadError::Cycle(e)` wraps the same `CycleError`.

- **`DerivedMap` constructors add `V : Eq` bound.** `DerivedMap::DerivedMap`,
  `Scope::derived_map`, and `create_derived_map` now require `V : Eq` on the
  value type, closing the constructible-but-unreadable gap (the read methods
  already needed this bound). `DerivedMap::fallible` adds `E : Eq` alongside
  `V : Eq` for the same reason — `Result[V, E] : Eq` is required by the
  read channel.

### Changed

- **`CycleError::path()` returns a fresh copy.** Previously it returned the
  stored path array; mutating it could desynchronize the path from the
  labels snapshot that `format_path` indexes by position (out-of-bounds
  abort). `ReadError::path()` inherits the fix by delegation.

### Added

- **`Scope::watch(derived)`.** Folds watch creation, scope registration, and
  one priming read into a single call. The priming read records the target's
  upstream `gc_dependencies`, so a `Runtime::gc()` that runs before the first
  consumer read can no longer sweep the upstream graph (the bare
  `scope.add_watch(derived.watch())` form GC-roots only the uncomputed
  terminal — see the contrast test in `incr/tests/scope_test.mbt`).

- **`Expr[T]` formula layer (Track E).** A lazy expression DSL over target
  facade handles. Expression chains allocate no incremental cells until
  materialized via `Expr::derived` or `Scope::derived_expr` (one cell per
  materialization). Supports:

  - **Source lifts:** `Input::expr`, `InputField::expr`, `Derived::expr`,
    `ReachableDerived::expr`, `EagerDerived::expr`.
  - **Constants:** `Expr::constant(rt, value, label?)`.
  - **Combinators:** `map`, `map2`.
  - **Operators:** `Add`, `Sub`, `Mul`, `Div`, `Mod`, `Neg` (via MoonBit
    operator traits on `Expr[T]`).
  - **Materialization:** `Expr::derived(label?) -> Derived[T]`,
    `Scope::derived_expr(expr, label?) -> Derived[T]`.

  Cross-runtime composition aborts at construction time. The `Expr` type is
  re-exported from `@incr`. See `incr/cells/expr.mbt` and
  `docs/design/specs/2026-05-25-expr-formula-api.md`.

### Deprecated

- **`Input::new` / `Runtime::new` / `Relation::new`.** The `Type::Type`
  constructor forms (`Input(rt, v)`, `Runtime()`, `Relation(rt)`) are
  canonical. The aliases remain functional in this release; removal is planned
  for a future breaking release after the `Expr[T]` track (see
  `docs/plans/2026-07-05-public-api-boundary-cleanup.md`).

- **`Effect::new(rt, f)`.** Replaced by `Effect(rt, f)` (`Effect::Effect`).
  The old name remains functional. `Effect::Effect(Runtime, f)` is now the
  canonical constructor form.

### Note

- **`Scope::new` is deliberately kept.** Unlike the other constructor aliases,
  `Scope::new` is the pervasive documented form and the rename value does not
  cover the churn. The `Scope` constructor remains `Scope::new(rt)`.
- **`_no_backdate` variants are kept until `Expr[T]` lands.** The mapN family
  (`map_no_backdate`, `derived2_no_backdate`, etc.) is interim algebra sugar
  pending Track E; revisit when `Expr[T]` materialization ships.

## [v0.13.0] - 2026-07-03

Breaking release: the compatibility API surface is removed directly, with no
deprecation stage (issue #345; minor-as-breaking per the current semver policy
while the library has no external users). Migrate by renaming — every removed
name has a target-facade replacement with the same shape.

### Removed (breaking)

- **`Readable` trait.** Use the read method directly on your facade handle. The
  trait just re-exported method signatures; it added no capability.
- **`Trackable` trait.** Same rationale as `Readable`.
- **`Database` type.** There is no replacement — its `Runtime::derived`
  convenience wrapper already existed as
  `Derived(rt, fn() { ... })` / `Scope::derived(fn() { ... })`. The type
  existed only for the old `Signal`/`Memo` era; remove its root re-export.
- **`FunctionalRelation` / `MapFunctionalRelation`.** Replaced by
  `MapRelation` (the datalog-engine-backed map facade). `Runtime::new_rule`
  and `Relation::insert` / `remove` / `iter` / `contains` are unchanged.
- **`TrackedCell` / `TrackedCellObserver` aliases.** Replaced by `InputField`
  and `Observer`. Identical functionality, new names.
- **`ReactiveHandle` / `PushReactiveHandle` aliases.** Replaced by
  `EagerDerived` and `Effect`. Identical functionality, new names.
- **`HybridMemoHandle` alias.** Replaced by `ReachableDerived`. Same API shape,
  new name.
- **`Signal` / `Memo`** aliases for `Input` and `Derived`. Final removal after
  v0.12.0 deprecation; identical single-type replacement.

### Added

- **`Input::read_honest` / `InputField::read_honest` / `Derived::read_honest`**
  (+ `ReachableDerived` / `Accumulator` / `Relation` / `MapRelation`). Full
  honest-read channel exposing `ReadError`. The existing `read` method
  delegates to `read_honest` in each case.
- **Accumulator serialization hooks.** `Accumulator::commit_hook(scope, f)`,
  `Accumulator::restore_hook(scope, f)`. See `docs/design/specs/2026-05-28-accumulator-commit-restore-hooks.md`.

### Changed (breaking)

- **`Effect::Effect` and `Scope::effect` now take `fn() -> Unit`** instead of
  `fn() -> T`. The old signature was a compatibility artifact from the
  `Reactive` → `EagerDerived` migration: every effect returning `T` immediately
  discards it. Return `Unit` from your callback. The `create_effect` helper in
  `traits.mbt` is updated to match.
- **`Runtime::batch`:** If the commit phase encounters a cycle, batch now
  completes the cycle-aborted cell's dependents' recomputation. Previously the
  cycle's path stack trace was returned and remaining dirty cells were left
  unrepaired. Post-batch `current_revision` now always advances.

### Changed

- **`UserGuide` layout and wording improvements.**

### Documentation

- Migrate reference docs to checked literate examples (`*.mbt.md` under docs/).
  Removed `docs/internals.md`, `docs/api-reference.md`, and `docs/scope.md`;
  replaced by `docs/design/internals.md` and `docs/api-reference.mbt.md` /
  `docs/scope.mbt.md`.

## [v0.12.0] - 2026-06-22

Compatibility-breaking release: the `Signal`/`Memo`-family aliases are
deprecated and produce compiler warnings. See `docs/migration-v0.11-v0.12.md`.
The aliases are functional but warned; they will be removed in v0.13.

### Changed (breaking)

- **`Input::new` → `Input(rt, v)`** (named constructor). The old `new` is
  deprecated with a warning.
- **`Derived::new` → `Derived(rt, compute)`.** The old `new` is deprecated
  with a warning.
- **`ReachableDerived::new` → `ReachableDerived(rt, compute)`.** The old `new`
  is deprecated.
- **`DerivedMap::new` → `DerivedMap(rt, compute)`.** The old `new` is
  deprecated.
- **`EagerDerived::new` → `EagerDerived(rt, compute)`.** The old `new` is
  deprecated.
- **`Effect::new` → `Effect(rt, f)`.** The old `new` is deprecated.
- **`Scope::EagerDerived` → `Scope::eager_derived`.** Deprecated.

### Deprecated

- **`Signal` / `Memo` / `HybridMemoHandle` / `TrackedCell` / `TrackedCellObserver`
  / `ReactiveHandle` / `PushReactiveHandle`** type aliases. All deprecated in
  favor of target names listed in v0.13.0's Removed section.

### Removed (breaking)

- **`FunctionalRelation` & `MapFunctionalRelation`** from the `@incr/types`
  package (moved to cells/internal). Two re-exports dropped; downstream code
  that only imported `@incr` is unaffected by the swap.
- **`Runtime::new_memo_with_durability`** removed. Use `Derived` with a
  positional durability parameter: `Derived(rt, compute, durability=High)`.

### Added

- **`Runtime::gc()` and `Runtime::gc_sweep()`.** Mark-compact garbage
  collection for unreachable cells. Uses `@gc_trait.GcRoot` interface for root
  discovery.
- **`Derived::on_change`** and `Derived::clear_on_change`. Register a callback
  that fires when this derived cell's output changes.
- **`ReachableDerived::observe`.** Returns an `Observer[T]` (same shape as the
  existing `Derived::observe`).
- **`Runtime::collect_gc_roots`.** Returns live roots for integration with
  `@gc_trait`.

## [v0.11.0] - 2026-06-13

### Added

- **`AcceptedDerived[V, E]`** — success-gated derived authoring (Layer 4).
- **`ReachableDerived` alias** — pre-naming for `HybridMemoHandle`.
- **`Runtime::derived_event_listener`** — low-level access to cell verification
  events for debugging/monitoring layers.

### Changed (breaking)

- **`Effect` recompute semantics.** Effect now recomputes on every committed
  revision where any transitive dependency has changed since the effect's last
  verified revision. Previously effects only recomputed when a direct source
  changed, making them unusable for push-pull boundary patterns
  (e.g. `Derived` → `Effect` where the Derived backdates). This aligns Effect
  with the documented "reactive" semantics.
- **`Observer` now guards reads against stale sentinel.** `Observer::get`
  resets the stale sentinel before reading, matching top-level test reads.

### Fixed

- **Concurrent scope disposal safety.** `Scope::child` now pushes before
  returning (not after), fixing a racy read during concurrent `dispose()`.

## [v0.10.1] - 2026-06-13

### Fixed

- **CI CI:** Disable publish-provenance for mooncakes to fix release workflow.

## [v0.10.0] - 2026-06-24

### Added
- Experimental `incr_tea` module: keyed VDOM diff, pure event-payload descriptors, renderer lifecycle, and Eq-safe HTML ergonomics
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

[Unreleased]: https://github.com/dowdiness/incr/compare/v0.14.0...HEAD
[v0.14.0]: https://github.com/dowdiness/incr/compare/v0.13.0...v0.14.0
[v0.13.0]: https://github.com/dowdiness/incr/compare/v0.12.0...v0.13.0
[v0.12.0]: https://github.com/dowdiness/incr/compare/v0.11.0...v0.12.0
[v0.11.0]: https://github.com/dowdiness/incr/compare/v0.10.1...v0.11.0
[v0.10.1]: https://github.com/dowdiness/incr/compare/v0.10.0...v0.10.1
[v0.10.0]: https://github.com/dowdiness/incr/releases/tag/v0.10.0
