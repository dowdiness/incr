# ADR: Distinguish derived values from keyed queries

**Date:** 2026-08-25
**Status:** Accepted

## Context

The accepted pre-alpha kernel represents every tracked computation as `Query[K, V]`. Computations that produce one value use `Unit` as a key, requiring an unused callback parameter and explicit `view(())`. Executable documentation and the public consumer fixture predominantly use this unkeyed shape, while keyed lookup remains a strategically important capability for demand-driven analysis.

## Decision

Incr Next treats a Derived Value and a Query as different public domain concepts.

A Derived Value is one tracked value without a caller-supplied lookup key. `Region::derived` constructs it and returns its `View[V]` directly; there is no separate public Derived Value handle. The `derived` name aligns with current `incr`; MoonBit reserves `derive`, so that spelling is unavailable.

A Query is a key-indexed family of derived values. A caller binds a key with `Query::view(key)` to obtain one member's `View[V]`.

The kernel may implement a Derived Value with an internal unit-keyed recipe, but `Unit`, an unused key parameter, and `view(())` do not appear in its public caller contract.

Derived Value and Query construction each accept one optional opaque `Cutoff[V]` policy. Omission selects conservative AlwaysChanged propagation. The only public policy constructor is `Cutoff::equal()`, which requires `V : Eq`; no arbitrary or type-owned comparison predicate is public.

## Rationale

The distinction makes the common single-value case direct without weakening the keyed model. Returning `View[V]` gives callers all currently commissioned authority while Region retains ownership of the compute closure, memo, trace, cutoff policy, and lifetime. A dedicated handle would expose no additional responsibility and would reserve interface surface for uncommissioned public eviction, debug, or policy mutation.

An opaque policy value keeps the common path to one construction operation while allowing advanced callers to opt into equality cutoff. The constructor bound preserves `V : Eq` without imposing it on AlwaysChanged callers. A manual `Eq` implementation used for cutoff remains responsible for ensuring that equality preserves every downstream observation; the kernel does not accept a separate unchecked relation.

## Consequences

- The primary introductory operation is `Region::derived`; it constructs a Derived Value and returns `View[V]`.
- `Query[K, V]` is taught only for caller-keyed families.
- Unit-key Query spelling is removed from successful public examples and consumer fixtures where the computation has no domain key.
- Derived Value and Query construction each have one common method rather than separate AlwaysChanged and Eq method families.
- Cutoff remains an optional advanced capability represented by an opaque generic policy, not a public enum, type-owned policy, or arbitrary predicate.
- Adding a public Derived Value handle later requires a concrete new responsibility and separate evidence.
- Existing contracts, documentation, generated interfaces, and consumer evidence must be revised and reaccepted before alpha publication.
