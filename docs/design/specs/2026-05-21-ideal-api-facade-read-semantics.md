# Ideal API Facades and Read Semantics

**Status:** Proposed

**Date:** 2026-05-21

**Parent decision:** [ADR 2026-05-21: Ideal Public API Naming](../../decisions/2026-05-21-public-api-ideal-naming.md)

**Parent plan:** [Ideal API Rename Migration Plan](../../plans/2026-05-21-ideal-api-rename-migration.md)

## Goal

Define the target facade shape and read semantics before implementing the
public API rename. The design must let target examples use names such as
`DerivedMap::get(key) -> Result[V, CycleError]` without changing the current
compatibility behavior of `MemoMap::get(key) -> V`.

## Phase 0 Constraints

The Phase 0 compile spike establishes these language constraints:

- Public `#alias` works for callable names and methods.
- Public type aliases preserve method resolution.
- Short constructor syntax does not resolve through a type alias.
- Blanket compatibility impls such as `impl[T : NewTrait] OldTrait for T` are
  rejected.
- Same-receiver overloads by argument type are rejected.

Therefore the target surface cannot rely on plain type aliases if it needs
target constructor syntax or target methods whose names collide with current
compatibility methods.

## Decisions

### Target handles are facades

Add target-name handle types in `cells/` as thin facades over the current
handles:

| Target facade | Current handle |
|---|---|
| `Input[T]` | `Signal[T]` |
| `Derived[T]` | `Memo[T]` |
| `ReachableDerived[T]` | `HybridMemo[T]` |
| `EagerDerived[T]` | `Reactive[T]` |
| `DerivedMap[K, V]` | `MemoMap[K, V]` |
| `InputField[T]` | `TrackedCell[T]` |
| `Watch[T]` | new watch handle, not a plain `Observer[T]` alias |
| `MapRelation[K, V]` | `FunctionalRelation[K, V]` |

Facades live in `cells/` rather than the root package so they can use
package-private read helpers and runtime state without exposing internals. The
root package re-exports them with `pub using @internal`.

Each facade owns one private current handle:

```moonbit
pub(all) struct Derived[T] {
  priv inner : Memo[T]
}
```

Each facade defines its own custom constructor:

```moonbit
pub fn[T : Eq] Derived::Derived(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
) -> Derived[T]
```

This is necessary because `pub type Derived[T] = Memo[T]` would allow method
resolution but not `Derived(...)` constructor syntax.

### Compatibility handles remain canonical for old code

Do not mutate the current method contracts:

- `Memo::get() -> T` remains strict and aborting.
- `Memo::get_result() -> Result[T, CycleError]` remains permissive.
- `MemoMap::get(key) -> V` remains permissive and aborting.
- `MemoMap::get_tracked(key) -> V` remains strict and aborting.
- `Runtime::read*` methods remain aborting one-shot compatibility helpers.

Target facades call new package-private primitives where the target behavior
does not already exist.

### `Result` covers cycles, not misuse

Target `Result[T, CycleError]` reads only make cycle detection recoverable.
They do not make every invalid operation recoverable.

These conditions still abort:

- strict read outside an active tracked context
- reading a disposed cell
- cross-runtime dependency reads
- reads during phases where the current implementation already forbids them
- user compute closures raising `Failure`

Rationale: `CycleError` is the only current recoverable read error. Invalid
context, disposed handles, and cross-runtime reads are API misuse or corrupted
lifecycle state, not ordinary data-dependent failures.

## Read Semantics

### Inputs

`Input[T]` wraps `Signal[T]`.

```moonbit
input.get()              -> T
input.peek()             -> T
input.set(value)         -> Unit
input.force_set(value)   -> Unit
```

`Input::get()` records a dependency when a tracking frame is active. Cycles are
impossible for inputs, so it returns `T` directly.

### Derived

`Derived[T]` wraps `Memo[T]`.

```moonbit
derived.get()            -> Result[T, CycleError]
derived.get_or_abort()   -> T
derived.read()           -> Result[T, CycleError]
derived.read_or_abort()  -> T
derived.watch()          -> Watch[T]
```

Semantics:

- `get()` is strict. It first checks for an active tracked context, then uses a
  `Result`-returning pull verification path so cycles become `Err`.
- `get_or_abort()` is strict and aborts on invalid context or cycle.
- `read()` is permissive. It works outside the graph and records a dependency if
  already tracking.
- `read_or_abort()` is the aborting convenience for `read()`.
- `watch()` creates a long-lived `Watch` root.

Implementation needs a package-private primitive on `Memo[T]`:

```moonbit
fn[T] Memo::get_strict_result(self : Memo[T]) -> Result[T, CycleError]
fn[T] Memo::read_result(self : Memo[T]) -> Result[T, CycleError]
```

`read_result` can delegate to the current `get_result_inner` path. The strict
variant adds the tracking-context guard before delegating.

### Reachable Derived

`ReachableDerived[T]` wraps `HybridMemo[T]` and mirrors `Derived[T]`:

```moonbit
reachable.get()            -> Result[T, CycleError]
reachable.get_or_abort()   -> T
reachable.read()           -> Result[T, CycleError]
reachable.read_or_abort()  -> T
reachable.watch()          -> Watch[T]
```

Implementation needs a new `HybridMemo` result primitive. Today
`HybridMemo::read_permissive()` aborts on cycles, so it cannot back
`ReachableDerived::read()`.

```moonbit
fn[T : Eq] HybridMemo::read_result(self : HybridMemo[T]) -> Result[T, CycleError]
fn[T : Eq] HybridMemo::get_strict_result(
  self : HybridMemo[T],
) -> Result[T, CycleError]
```

The body should mirror `HybridMemo::read_permissive()` but return
`Err(CycleError)` instead of aborting when `force_recompute` or `pull_verify`
detects a cycle.

### Eager Derived

`EagerDerived[T]` wraps `Reactive[T]`.

```moonbit
eager.get()             -> T
eager.read()            -> T
eager.watch()           -> Watch[T]
```

`Reactive[T]` stores an already-computed push value. A read of the cached value
does not run pull verification and has no `CycleError` path. Do not force an
always-`Ok` `Result` onto `EagerDerived`; reserve `Result` for reads with a real
recoverable failure mode.

`get()` remains strict and aborts outside a tracked context. `read()` is
permissive and records a dependency if already tracking.

### Derived Map

`DerivedMap[K, V]` wraps `MemoMap[K, V]`.

```moonbit
map.get(key)                 -> Result[V, CycleError]
map.get_or_abort(key)        -> V
map.read(key)                -> Result[V, CycleError]
map.read_or_abort(key)       -> V
map.read_or(key, fallback)   -> V
map.read_or_else(key, f)     -> V
map.has_cached(key)          -> Bool
map.cache_len()              -> Int
map.sweep_cache()            -> Int
map.clear_cache()            -> Unit
```

Semantics:

- `get(key)` is strict and returns cycle errors.
- `get_or_abort(key)` is strict and aborts on invalid context or cycle.
- `read(key)` is permissive and returns cycle errors.
- `read_or_abort(key)` is permissive and aborts on cycle.
- `read_or` and `read_or_else` recover from cycles only.

Implementation needs package-private primitives on `MemoMap`:

```moonbit
fn[K : Hash + Eq, V : Eq] MemoMap::get_strict_result(
  self : MemoMap[K, V],
  key : K,
) -> Result[V, CycleError]

fn[K : Hash + Eq, V : Eq] MemoMap::read_result(
  self : MemoMap[K, V],
  key : K,
) -> Result[V, CycleError]
```

`read_result` is the current `MemoMap::get_result` behavior. The strict variant
checks that `self.rt.core.tracking.stack.length() > 0` before creating or
reading the per-key memo.

Keep `MemoMap::get_result(key)` as compatibility spelling. Target docs should
prefer `DerivedMap::read(key)`.

### Watch

`Watch[T]` is a target-name long-lived read handle. It should not be a plain
alias of `Observer[T]` if target watch reads return recoverable cycle errors.

```moonbit
pub struct Watch[T] {
  priv runtime : Runtime
  priv target_id : CellId
  priv getter : () -> Result[T, CycleError]
  priv mut disposed : Bool
}

watch.read()           -> Result[T, CycleError]
watch.read_or_abort()  -> T
watch.dispose()        -> Unit
watch.is_disposed()    -> Bool
```

`Watch` can share the same `gc_root_counts` and `CellLifecycle` mechanics as
`Observer`, but it needs a `Result`-returning getter. `Observer[T]` stays as the
compatibility handle with `Observer::get() -> T`.

`EagerDerived::watch()` can return a `Watch[T]` whose getter always returns
`Ok(value)` after the ordinary disposed/cross-runtime guards.

## Runtime Receiver Reads

Do not add `Runtime::read(...)` target overloads in the additive phase. Phase 0
proved MoonBit rejects same-receiver overloads by parameter type, and the
current compatibility method already owns `Runtime::read(memo : Memo[T]) -> T`.

Preferred target examples should use direct handle methods:

```moonbit
derived.read()
derived.read_or_abort()
derived.watch()
```

If a runtime-receiver form gets a real downstream driver later, use names that
cannot collide with each other:

```moonbit
rt.read_derived(derived)                 -> Result[T, CycleError]
rt.read_derived_or_abort(derived)        -> T
rt.read_reachable(reachable)             -> Result[T, CycleError]
rt.read_reachable_or_abort(reachable)    -> T
rt.read_eager(eager)                     -> T
```

Do not use `Runtime::read_or_abort(...)` as a generic receiver name unless only
one such method will ever exist.

## Implementation Order

1. Add package-private result primitives for `Memo`, `HybridMemo`, and
   `MemoMap`; cover strict-context and cycle behavior with focused tests.
2. Add target facade structs in `cells/` with constructors and direct read
   methods.
3. Add `Watch[T]` with `Result`-returning `read()` while keeping `Observer[T]`.
4. Add `Scope` and `RuntimeContext` helpers that return target facades.
5. Switch docs examples from compatibility handles to target handles only after
   the exact examples compile.

## Test Cases

Add focused tests before broad docs rewrites:

- `Derived::get()` inside a memo returns `Ok`.
- `Derived::get()` outside a tracked context aborts.
- `Derived::read()` outside a tracked context returns `Ok`.
- `Derived::read()` inside a tracked context records a dependency.
- `ReachableDerived::read()` returns `Err(CycleError)` for a cycle rather than
  aborting.
- `DerivedMap::get(key)` inside a memo returns `Ok`.
- `DerivedMap::get(key)` outside a tracked context aborts.
- `DerivedMap::read(key)` outside a tracked context returns `Ok`.
- `DerivedMap::read_or(key, fallback)` only uses the fallback on cycles.
- `Watch::read()` keeps the target alive across `Runtime::gc()`.
- Existing `MemoMap::get`, `MemoMap::get_tracked`, `MemoMap::get_result`, and
  `Runtime::read*` behavior remains unchanged.

## Non-Goals

- Do not remove compatibility names in this phase.
- Do not change `MemoMap::get` semantics.
- Do not introduce a broad read trait with associated result types. MoonBit
  traits do not have associated types, and the read shapes differ by handle.
- Do not add runtime-receiver overloads for target reads.
