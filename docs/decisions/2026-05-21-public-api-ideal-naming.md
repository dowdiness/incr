# ADR: Ideal Public API Naming

**Date:** 2026-05-21
**Status:** Accepted (2026-05-21)
**Related cleanup:** [PR #61](https://github.com/dowdiness/incr/pull/61)

## Context

PR #41 surfaced a naming problem around `MemoMap::get` and
`MemoMap::get_tracked`: the names suggested that only the "tracked" path
records dependencies. That was wrong. Both paths record the same per-key
dependency when a tracking frame is active; the real distinction is
whether the call is allowed outside a tracked compute context.

PR #61 fixed the package-private part of that problem by renaming
`get_untracked` helpers to `read_permissive`, with deprecated aliases.

The broader lesson is that several public names still describe internal
mechanisms (`Memo`, `HybridMemo`, `Reactive`, `TrackedCell`) or inherited
vocabulary (`Database`) rather than the most obvious user-facing trait of
each type. This ADR records the ideal public vocabulary if breaking
changes are ignored. It is a target design, not an implementation plan.

## Decision

Use graph-role names for public cell types:

| Current name | Target name | Meaning |
|---|---|---|
| `Signal[T]` | `Input[T]` | User-provided value that enters the graph. |
| `Memo[T]` | `Derived[T]` | Lazy value derived from graph dependencies. |
| `HybridMemo[T]` | `ReachableDerived[T]` | Lazy derived value that participates in reachability propagation through eager/rooted dependents. |
| `Reactive[T]` | `EagerDerived[T]` | Derived value recomputed eagerly during push propagation. |
| `MemoMap[K, V]` | `DerivedMap[K, V]` | Map-shaped derived computation; each key lazily owns one derived value. |
| `TrackedCell[T]` | `InputField[T]` | Input cell intended to live as a field of a larger tracked value. |
| `Observer[T]` | `Watch[T]` | Long-lived outside-the-graph read handle that roots a derived value. |
| `FunctionalRelation[K, V]` | `MapRelation[K, V]` | Relation-shaped Datalog input keyed like a map. |
| `Readable` | `Freshness` | Capability for querying whether a node is fresh. |
| `Trackable` | `InputFieldOwner` | Structured value that owns input fields. |
| `Database` | `RuntimeContext` | User context that exposes an `incr` runtime. |

Keep these names:

```moonbit
Runtime
Scope
Effect
Accumulator
Relation
```

`Database` may remain only as a deprecated compatibility name if MoonBit
can express the migration cleanly. Final docs should use
`RuntimeContext`.

## Method Vocabulary

Use read names by context and failure mode:

| Method shape | Meaning |
|---|---|
| `get(...)` | Strict graph read that returns `Result`. Requires tracked context for derived nodes. |
| `get_or_abort(...)` | Strict graph read convenience that aborts on cycle or invalid context. |
| `read(...)` | Permissive read that returns `Result`. Works outside the graph; records a dependency if already tracking. |
| `read_or_abort(...)` | Permissive read convenience that aborts on cycle. |
| `peek(...)` | Raw input-style read that never records a dependency. |
| `watch()` | Create a long-lived outside read handle. |
| `Watch::read()` | Read through a watch handle. |
| `is_fresh()` | Current `is_up_to_date()` behavior. |
| `force_set(value)` | Current `set_unconditional(value)` behavior. |

For `Input[T]`, cycles are impossible, so `Input::get()` can return `T`
directly and record a dependency when a tracking frame is active.
`Input::peek()` remains the no-dependency read.

### Why `Result` over `T` for derived reads?

Two structural reasons, both rooted in the framework's design space rather
than aesthetic preference:

1. **`incr`'s task abstraction is Monadic.** In the "Build Systems à la
   Carte" sense (Mokhov, Mitchell, Peyton Jones 2020), compute functions
   discover dependencies dynamically by calling other reads, and they can
   branch on read values. A Monadic scheduler can discover a cycle only at
   runtime — the dependency graph is unknown ahead of time. `Result[T,
   CycleError]` is the type that correctly describes "a read that *could*
   fail, but whose failure mode is named and recoverable."

2. **`incr` chooses to support cycles as recoverable errors.** The
   build-systems literature assumes acyclic task graphs; cycles are
   undefined behavior or aborts in Make, Shake, Bazel, and Excel. `incr`
   makes the opposite choice: cycles are first-class, with `CycleError`
   carrying the offending path. Bare `T` returns force every cycle to be
   handled by `abort()`, which prevents callers from recovering. `Result[T,
   CycleError]` exposes the choice to the caller.

Together these mean the bare-`T` `get()` on derived cells today is a
historical artifact, not a design principle: it predates the introduction
of `CycleError` and the formal commitment to Monadic + cycle-tolerant
semantics. The ideal API surface returns `Result` from every derived read
and offers `_or_abort` shortcuts for callers that prefer to escalate
cycles to aborts.

`Input::get()` remains bare-`T` because inputs cannot cycle — they have no
deps to form a cycle with. The asymmetry is intentional and load-bearing.

For `DerivedMap[K, V]`, the target read surface is:

```moonbit
map.get(key)           // strict, Result[V, CycleError]
map.get_or_abort(key)  // strict, aborting convenience
map.read(key)          // permissive, Result[V, CycleError]
map.read_or_abort(key) // permissive, aborting convenience
map.read_or(key, fallback)
map.read_or_else(key, fallback)
```

Cache-management methods should say that they operate on the cache:

```moonbit
map.has_cached(key)
map.cache_len()
map.sweep_cache()
map.clear_cache()
```

## Construction

Use MoonBit custom struct constructors as the primary construction API:

```moonbit
Input(rt, value)
Derived(rt, () => ...)
ReachableDerived(rt, () => ...)
EagerDerived(rt, () => ...)
DerivedMap(rt, key => ...)
InputField(rt, value)
Scope(rt)
Accumulator(rt, label="events")
```

Constructors should take an explicit `Runtime`. Receiver-based
convenience methods may be provided on `Scope` or `RuntimeContext`, but
the final API should not rely on `create_*` free helper functions.

`Runtime` should not define the ideal read surface. Handles own reads,
`Watch` owns long-lived outside-the-graph read roots, and `Runtime` owns
coordination concerns such as batching, GC, fixpoint, and introspection.
Existing `Runtime::read*` methods are compatibility conveniences, not the
target naming pattern.

Target facade handles should not expose public bridge methods to or from the
current compatibility handles. During migration, old and target handles coexist;
users construct the surface they intend to use instead of converting between
them.

## Rationale

1. **Names should describe graph role, not implementation.** `Input` and
   `Derived` say where a value comes from. `Memo` and `Signal` require
   ecosystem knowledge and can be read inconsistently.

2. **`ReachableDerived` names the deterministic trait of the old
   `HybridMemo`.** The type is still lazy. Its defining difference from
   ordinary `Derived` is reachability propagation through eager/rooted
   dependents, not eagerness.

3. **Recoverable reads should own the simple names.** If a derived read
   can fail with a cycle, the `Result` form should be the default API.
   Aborting shortcuts should carry the explicit `_or_abort` suffix.

4. **`RuntimeContext` is more literal than `Database`.** User types may
   be apps, compiler contexts, editor sessions, or tests rather than
   databases. The trait only promises access to a runtime.

5. **Constructor syntax is now the MoonBit-native construction surface.**
   `create_*` helpers duplicate the type names and should not be part of
   the ideal final surface.

## Migration Notes

This ADR intentionally does not define the migration sequence. A later
implementation plan should decide staging, deprecated aliases, and whether
any compatibility traits can be expressed cleanly.

Relevant MoonBit migration tools:

- `#alias(new, deprecated="...")` for old `new` constructors.
- `#alias(old_name, deprecated="...")` for old method names where a
  direct alias is possible.
- `#label_migration` for parameter-label migrations only.

Do not keep duplicate canonical names in the final API. Compatibility
aliases should be temporary and documented as migration aids.
