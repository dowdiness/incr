# Ideal API Rename Migration Plan

**Date:** 2026-05-21
**Status:** Draft implementation plan
**Scope:** Docs-only plan. Do not implement public API changes in this
planning step.

## Context

PR #62 (`f408d20`) accepted
[ADR 2026-05-21: Ideal Public API Naming](../decisions/2026-05-21-public-api-ideal-naming.md).
The ADR records the target vocabulary:

| Current | Target |
|---|---|
| `Signal[T]` | `Input[T]` |
| `Memo[T]` | `Derived[T]` |
| `HybridMemo[T]` | `ReachableDerived[T]` |
| `Reactive[T]` | `EagerDerived[T]` |
| `MemoMap[K, V]` | `DerivedMap[K, V]` |
| `TrackedCell[T]` | `InputField[T]` |
| `Observer[T]` | `Watch[T]` |
| `FunctionalRelation[K, V]` | `MapRelation[K, V]` |
| `Readable` | `Freshness` |
| `Trackable` | `InputFieldOwner` |
| `Database` | `RuntimeContext` |

Keep `Runtime`, `Scope`, `Effect`, `Accumulator`, `Relation`, and `Rule`.

The ADR deliberately did not choose a migration sequence. This plan supplies
one, based on the current public signatures:

- `Signal`, `Memo`, `HybridMemo`, `MemoMap`, `TrackedCell`, `Runtime`, and
  `FunctionalRelation` already have custom constructors plus `::new`.
- Derived reads currently use aborting `get()` and, for `Memo`/`MemoMap`,
  permissive `get_result()` for `Result`-returning cycle handling.
- `MemoMap::get(key)` is currently a permissive aborting read, while the target
  `DerivedMap::get(key)` is a strict `Result`-returning read.
- `Database`, `Readable`, and `Trackable` are `pub(open)` traits, so downstream
  users may implement them directly.
- PR #61 proved `#alias(old_name, deprecated="...")` for same-signature method
  aliases by renaming package-private permissive reads to `read_permissive`.

## Migration principles

1. Keep current names as the compatibility surface until target names compile
   and are documented.
2. Use `#alias(..., deprecated="...")` only for callable names with unchanged
   signature and behavior.
3. Do not hide semantic changes behind aliases. If the old and target names
   need the same spelling with different return types or preconditions, use a
   wrapper/facade phase or a breaking phase.
4. Treat type and trait renames separately from method renames. `#alias` is a
   callable migration tool; do not assume it can deprecate public type or trait
   names.
5. Do not switch tutorials and checked examples to target-only spelling until
   the target spelling is available in code and the examples can be checked.
6. Do not add target-vocabulary read methods to `Memo`, `HybridMemo`, or
   `MemoMap` merely as a bridge. Those compatibility handles are eventual
   cleanup/removal targets; migration should move callers to `Derived`,
   `ReachableDerived`, and `DerivedMap` instead.

## Aliasable callable renames

`#alias(..., deprecated="...")` is only a direct migration tool for callable
renames on the same effective receiver. PR #61 proved this for same-receiver
method aliases. It did not prove cross-receiver aliases such as
`Memo::get_result -> Derived::read`.

Treat each row below as a direct `#alias` candidate only if the target name is
implemented on the same receiver as the old name, or if the type-name migration
is a true alias that preserves method resolution. If the target type is a
wrapper/facade, implement target forwarding methods on the wrapper and keep or
deprecate the old receiver separately.

### Same-receiver aliasability analysis

These candidates keep the same behavior if the target name is implemented on the
same receiver, and can use `#alias` after a compile spike confirms the receiver
is unchanged. This is an aliasability analysis, not a blanket implementation
instruction. The 2026-05-26 revision rejects same-receiver read bridges on
`Memo`, `HybridMemo`, and `MemoMap`; migrate those callers to the target facades
instead.

| Current callable | Target callable | Direct alias condition |
|---|---|---|
| `Type::new(...)` on cell constructors | `Type::Type(...)` custom constructor | Same type receiver. Keep `::new` as a deprecated alias after the target constructor is canonical. |
| `Signal::set_unconditional(value)` | `Signal::force_set(value)` | Same receiver only. `Input::force_set(value)` is a facade forwarding method. |
| `TrackedCell::set_unconditional(value)` | `TrackedCell::force_set(value)` | Same receiver only. `InputField::force_set(value)` is a facade forwarding method. |
| `is_up_to_date()` concrete methods | `is_fresh()` concrete methods | Same receiver. Trait migration is separate. |
| `observe()` | `watch()` | Same receiver for `Memo`, `HybridMemo`, and `Reactive` only. Target facades define their own `watch()` methods. |
| `Observer::get()` | `Observer::read()` | Same receiver only. `Watch::read()` is a target facade method with target semantics. |
| `Memo::get_result()` | `Memo::read()` | Same receiver only. Do not alias it to target `get()`. |
| `Memo::get()` | `Memo::get_or_abort()` | Same receiver only. This alias is invalid once `get` is also the target `Result` method on that receiver. |
| `Memo::get_or(fallback)` | `Memo::read_or(fallback)` | Same receiver only. |
| `Memo::get_or_else(fallback)` | `Memo::read_or_else(fallback)` | Same receiver only. |
| `MemoMap::get_result(key)` | `MemoMap::read(key)` | Same receiver only. |
| `MemoMap::get(key)` | `MemoMap::read_or_abort(key)` | Same receiver only. Do not alias it to target `get(key)`. |
| `MemoMap::get_tracked(key)` | `MemoMap::get_or_abort(key)` | Same receiver only. |
| `MemoMap::get_or(key, fallback)` | `MemoMap::read_or(key, fallback)` | Same receiver only. |
| `MemoMap::get_or_else(key, fallback)` | `MemoMap::read_or_else(key, fallback)` | Same receiver only. |
| `MemoMap::contains(key)` | `MemoMap::has_cached(key)` | Same receiver only. |
| `MemoMap::length()` | `MemoMap::cache_len()` | Same receiver only. |
| `MemoMap::sweep()` | `MemoMap::sweep_cache()` | Same receiver only. |
| `MemoMap::clear()` | `MemoMap::clear_cache()` | Same receiver only. |

### Wrapper/facade forwarding targets

If `Derived`, `DerivedMap`, `ReachableDerived`, `EagerDerived`, or `Watch` are
implemented as wrappers instead of true type aliases, the target methods are
not `#alias` migrations from the old receiver. They are new forwarding methods:

| Wrapper target | Current behavior to forward to |
|---|---|
| `Derived::read()` | `Memo::get_result()` |
| `Derived::get_or_abort()` | `Memo::get()` |
| `Derived::read_or(fallback)` | `Memo::get_or(fallback)` |
| `Derived::read_or_else(fallback)` | `Memo::get_or_else(fallback)` |
| `DerivedMap::read(key)` | `MemoMap::get_result(key)` |
| `DerivedMap::read_or_abort(key)` | `MemoMap::get(key)` |
| `DerivedMap::get_or_abort(key)` | `MemoMap::get_tracked(key)` |
| `DerivedMap::read_or(key, fallback)` | `MemoMap::get_or(key, fallback)` |
| `DerivedMap::read_or_else(key, fallback)` | `MemoMap::get_or_else(key, fallback)` |
| `DerivedMap::has_cached(key)` | `MemoMap::contains(key)` |
| `DerivedMap::cache_len()` | `MemoMap::length()` |
| `DerivedMap::sweep_cache()` | `MemoMap::sweep()` |
| `DerivedMap::clear_cache()` | `MemoMap::clear()` |

`FunctionalRelation -> MapRelation` is a type rename. Its methods can keep
their current names. Constructor aliases are enough after the type-name strategy
is chosen.

## Changes that need wrappers or compatibility traits

### Public type names

Type renames are not `#alias` work. Phase 0 proved that type aliases preserve
method resolution but do not provide target constructor syntax, so the target
surface should use facade types when it needs examples such as `Input(...)` or
when target methods must differ from current compatibility methods.

Use wrapper/facade types for the target public handles:

- `Signal[T] -> Input[T]`
- `TrackedCell[T] -> InputField[T]`
- `Observer[T] -> Watch[T]`
- `FunctionalRelation[K, V] -> MapRelation[K, V]`
- `Memo[T] -> Derived[T]`
- `HybridMemo[T] -> ReachableDerived[T]`
- `Reactive[T] -> EagerDerived[T]`
- `MemoMap[K, V] -> DerivedMap[K, V]`

The wrapper phase lets new code call `Derived::get() -> Result[...]` while old
code keeps `Memo::get() -> T`. A type alias cannot provide both meanings for
the same method name on the same receiver.

### `Database -> RuntimeContext`

`Database` is a public open trait. A direct rename would break downstream
`impl Database for MyDb` code, so stage it as compatibility traits:

1. Add `pub(open) trait RuntimeContext { runtime(Self) -> Runtime }`.
2. Keep `Database` unchanged and mark it as compatibility/deprecated in docs.
3. Add target helper surfaces against `RuntimeContext` only where they are
   still useful during migration. Do not multiply `create_*` helpers unless a
   downstream migration needs them; the ADR's final API prefers constructors,
   `Scope`, and receiver-based conveniences over free `create_*` functions.
4. Document the temporary dual-impl pattern for downstream contexts. The
   checked API-reference companion pins this shape in
   [`../api_reference_examples.mbt.md`](../api_reference_examples.mbt.md#runtimecontext-and-the-create_-helpers).
5. In a later breaking phase, flip generic helper bounds from `Database` to
   `RuntimeContext` or remove the helper if the constructor/scope path has
   replaced it.

Before adding blanket compatibility impls such as `impl[T : RuntimeContext]
Database for T`, run a focused compile spike. Blanket impls may collide with
explicit downstream impls, and avoiding coherence surprises is more important
than saving one migration line.

### `Readable -> Freshness`

`Readable` is also a public open trait. Stage it as a new trait plus explicit
built-in impls:

1. Add `pub(open) trait Freshness { is_fresh(Self) -> Bool }`.
2. Add concrete `is_fresh()` methods for `Input`, `Derived`,
   `ReachableDerived`, and `InputField`, delegating to current
   `is_up_to_date()` behavior.
3. Keep `Readable` and its existing impls during compatibility.
4. Prefer explicit built-in impls for both traits. Do not rely on blanket
   trait bridging until a compile spike proves it is non-overlapping.
5. Move docs and examples for new generic code to `Freshness`; leave a
   migration note for users with custom `Readable` impls.

### `Trackable -> InputFieldOwner`

`Trackable` declares ownership of `TrackedCell` fields. Stage the target as a
new trait:

1. Add `pub(open) trait InputFieldOwner { cell_ids(Self) -> Array[CellId] }`.
2. Add a target helper such as `add_input_fields(scope, owner)` using
   `InputFieldOwner`.
3. Keep `Trackable` and `add_tracked(scope, tracked)` as deprecated
   compatibility names.
4. Keep `gc_tracked` deprecated as it is today; do not create a target synonym
   for a no-op.
5. Document the same temporary dual-impl pattern as `RuntimeContext` for
   downstream types that need to compile against both surfaces.

## `DerivedMap` read-vocabulary staging

`MemoMap` is the sharpest migration risk because the target default read changes
meaning:

- Current `MemoMap::get(key) -> V` is permissive and aborting.
- Target `DerivedMap::get(key) -> Result[V, CycleError]` is strict and
  non-aborting.
- Current code does not expose the exact target primitive. It has strict
  aborting read via `MemoMap::get_tracked(key)` and permissive `Result` read
  via `MemoMap::get_result(key)`, but not strict `Result` read.

Do not attempt to make `MemoMap::get` serve both contracts. Use one of these
two sequences:

1. Preferred: introduce `DerivedMap` as a thin target facade over `MemoMap`.
   `DerivedMap::get(key)` must first implement the missing strict
   `Result`-returning primitive: check that a tracking frame is active, then
   read the per-key memo through a `Result` path so cycles are returned rather
   than aborted. After that primitive exists, `MemoMap::get(key)` can remain
   compatibility API.
2. Rejected fallback: keep `MemoMap` as the only runtime type and add every
   non-conflicting target method directly to it. This was plausible before the
   facade shipped, but it is now unnecessary churn. `DerivedMap` exists and keeps
   docs honest: target-name examples can show target semantics without expanding
   the compatibility handle.

The facade path keeps docs honest: target-name examples can show target
semantics without breaking existing `MemoMap` users.

The facade/read contract is specified in
[`docs/design/specs/2026-05-21-ideal-api-facade-read-semantics.md`](../design/specs/2026-05-21-ideal-api-facade-read-semantics.md).

## `Runtime::read*` staging

Current outside-the-graph one-shot reads are receiver methods on `Runtime`:

- `Runtime::read(memo : Memo[T]) -> T`
- `Runtime::read_hybrid(memo : HybridMemo[T]) -> T`
- `Runtime::read_reactive(reactive : Reactive[T]) -> T`

They create a temporary observer, read the target, dispose the observer, and
abort on cycle or invalid reads. They are therefore aborting convenience reads,
not the target `Result`-returning read surface.

Stage them as compatibility API:

1. Keep all three current methods during the additive target-name phase.
2. Do not add replacement target runtime read names during the additive phase.
   The ideal target surface puts reads on handles:
   `derived.read()`, `derived.read_or_abort()`, and `derived.watch()`.
3. Do not rename `Runtime::read(memo) -> T` to target `read(...)`, because target
   `read(...)` means `Result`-returning permissive read.
4. Do not assume MoonBit can overload `Runtime::read` by argument type while the
   old `Runtime::read(memo) -> T` exists. The Phase 0 compile spike must verify
   whether same-name receiver methods can differ only by parameter type. If not,
   reserve runtime-receiver `read(...) -> Result[...]` for a breaking phase after
   old `Runtime::read` has been removed or renamed.
5. Deprecate `Runtime::read*` as legacy compatibility in the same PR that adds
   the target handle outside-read methods. Remove it in a breaking release.
6. Delay any decision about new `Runtime` read helpers until after the old
   helpers are gone and a concrete downstream driver proves `Runtime` adds
   semantics beyond direct handle reads.
7. Do not add `Runtime::read_all`. Do not add `Runtime::snapshot` unless it
   enforces a real runtime invariant such as write exclusion, grouped event
   draining, or temporary roots for the duration of a read group.

## `Scope` helper staging

`Scope` is a kept type, but its current helper names expose old cell
vocabulary:

- `Scope::signal(...) -> Signal[T]`
- `Scope::memo(...) -> Memo[T]`
- `Scope::hybrid_memo(...) -> HybridMemo[T]`
- `Scope::reactive(...) -> Reactive[T]`
- `Scope::add_observer(obs : Observer[T]) -> Observer[T]`

Stage target helpers additively:

| Current helper | Target helper |
|---|---|
| `Scope::signal(...)` | `Scope::input(...)` |
| `Scope::memo(...)` | `Scope::derived(...)` |
| `Scope::hybrid_memo(...)` | `Scope::reachable_derived(...)` |
| `Scope::reactive(...)` | `Scope::eager_derived(...)` |
| `Scope::add_observer(obs)` | `Scope::add_watch(watch)` |

If target cell names are true aliases, these helpers can return the target
aliases while delegating to the current implementations. If target cell names
are wrappers, the helpers should construct the wrapper/facade type directly and
register the underlying cell id or watch disposal hook with the scope.

Keep current helper names through the compatibility window. Deprecate them only
after target helpers exist and the docs have switched to the target vocabulary.

## Implementation sequence

### Phase 0: language-mechanics spike

Before a public implementation PR, verify:

- Whether MoonBit supports deprecated type aliases for public type renames.
- Whether methods on a type alias resolve exactly like methods on the target
  type.
- Whether blanket trait compatibility impls are legal without overlapping
  downstream explicit impls.
- Whether `#alias` works on public custom constructors and public methods in
  the same way PR #61 used it for package-private methods.
- Whether same-receiver methods can overload by argument type. This matters for
  any future `Runtime::read(target) -> Result[...]` API while current
  `Runtime::read(memo) -> T` remains in compatibility.

This spike should be discarded or kept as a tiny preparatory PR; it should not
mix with the migration itself.

Phase 0 spike result (2026-05-21): compile probes live under
`examples/spikes/ideal_api_rename_phase0/` and verify the mechanics above.

- Public `#alias` works for custom constructors and public methods across a
  package boundary.
- `#deprecated` works on public `pub type Alias[T] = Target[T]`, and methods
  resolve through the alias to the target type.
- Short constructor syntax through a type alias does not resolve:
  `RenamedCell(3)` fails with `Value RenamedCell not found in package`.
  Alias-only type renames therefore cannot provide target constructor syntax
  such as `Input(...)`.
- Arbitrary blanket compatibility impls are rejected:
  `pub impl[T : CurrentFreshness] CompatReadable for T` fails with
  `Invalid type for "self": must be a type constructor`. Compatibility traits
  need per-type impls and downstream dual-impl guidance instead.
- Same-receiver overloads by argument type are rejected: a second
  `ReadRuntime::read(...)` fails with `The method read for type ReadRuntime has
  been defined`. Do not stage a future `Runtime::read(...) -> Result[...]`
  overload while the current `Runtime::read(memo) -> T` remains.
- Because alias method resolution exposes the target type's current methods,
  `DerivedMap` should be a wrapper/facade if `DerivedMap::get(key)` needs strict
  `Result` semantics during compatibility.

### Phase 1: additive target surface

Add target names without changing existing contracts:

- Add `Input`, `InputField`, `Watch`, `MapRelation`, `Derived`,
  `ReachableDerived`, `EagerDerived`, and `DerivedMap` as facades.
- Add non-conflicting target methods and deprecated callable aliases.
- Add `RuntimeContext`, `Freshness`, and `InputFieldOwner` while keeping
  `Database`, `Readable`, and `Trackable`.
- Add target `Scope` helpers while keeping `Scope::signal`, `Scope::memo`,
  `Scope::hybrid_memo`, `Scope::reactive`, and `Scope::add_observer`.
- Keep all current docs examples on compatibility names unless the exact target
  spelling is now checked and compiling.

### Phase 2: docs and downstream migration window

After Phase 1 compiles:

- Update API reference and concepts docs to list target names first and current
  names as deprecated compatibility.
- Switch examples that only need safe facade forwarding: `Input`, `InputField`,
  `Watch`, `force_set`, `is_fresh`, and cache method names.
- Keep examples involving `Derived::get()` and `DerivedMap::get()` on current
  names unless the wrapper facade already implements target `Result` semantics.
- Add migration notes showing old-to-new read vocabulary.
- Prefer checked examples (` ```mbt check`) or literate `.mbt.md` examples for
  any new target-only snippet.

### Phase 3: compatibility-to-facade migration

After the target facades have shipped:

- publish a migration guide from `Memo`, `HybridMemo`, and `MemoMap` to
  `Derived`, `ReachableDerived`, and `DerivedMap`;
- provide a conservative codemod for type, constructor, and unambiguous method
  rewrites;
- report context-sensitive reads (`get_result`, top-level vs tracked-context
  reads) for manual migration;
- do not add same-receiver target-vocabulary methods to compatibility handles.

### Phase 4: final docs switch and compatibility cleanup

After Phase 3:

- Switch `README.md`, `docs/getting-started.mbt.md`, `docs/concepts.mbt.md`,
  `docs/cookbook.mbt.md`, and API examples to target names by default.
- Keep one migration table in the API reference for the deprecated names.
- Stop presenting `create_*` helpers as the preferred construction path.
- Remove deprecated aliases or compatibility handles only after at least one
  documented migration window and a changelog entry.

## Documentation switch rule

Docs should move in three waves:

1. **Before Phase 1:** current names remain canonical in examples; target names
   appear only in ADRs and this plan.
2. **After Phase 1:** target names may be used in examples only when the exact
   snippet compiles on the target surface. Current names remain documented as
   compatibility.
3. **After Phase 3:** target names become canonical everywhere. Current names
   move to migration notes and deprecation tables.

Do not switch prose examples ahead of code. The repository already has many
unchecked ` ```moonbit` blocks, so target-only examples should be either
checked blocks or backed by integration tests where the behavior matters.
