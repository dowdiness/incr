# Honest Read-Error Ownership

**Status:** Tier 1 Shipped (#100); Tier 2 Proposed

**Date:** 2026-05-28

**Related:** [Ideal API Facades and Read Semantics](2026-05-21-ideal-api-facade-read-semantics.md) (strict/permissive read contracts), [Static Derived Public-Surface Options](2026-05-28-static-derived-public-options.md)

## Goal

Decide how the library should *honestly* express failure on reads. Today the
read surface under-reports its failure modes: a memo's compute closure is typed
`() -> T raise Failure`, but the read API is typed `-> Result[T, CycleError]`
(no raise). When a compute actually raises `Failure`, the kernel re-raises it up
`pull_verify` (`cells/internal/kernel/verify.mbt`) and the read path catches it
and converts it to an **uncatchable `abort`** (`cells/derived.mbt`,
`cells/derived_map.mbt`). So the signature claims only cycles can fail a read,
while in reality a compute failure crashes the process.

This spec establishes the target contract and a staged, non-breaking migration.

## First principles: what an error *is* in a cached memo graph

A read asks for a **stored graph snapshot**, not for the execution of an
arbitrary effect. The compute that produced the value ran at a *different* time
than the read that observes it, may have run zero times (cache hit) or
transitively on behalf of another cell, and its result is shared and replayed to
many later readers. An *effect* cannot be cached — only a *value* can. This
forces a three-way split of failures by ownership:

1. **Graph-read failures** — intrinsic to the read mechanism, uniform across
   every cell, and unrecoverable by any domain reader: cycles, disposal,
   cross-runtime misuse. These belong in the **read channel** (`Result`'s `Err`).
   Cross-runtime misuse is a programmer defect and may `abort`.
2. **Domain failures** — a compute's own failure outcome (a parse error, a
   validation failure). These are **part of the computed state** and belong in
   the **value**, reified as `Derived[Result[V, E]]`. They are then cached,
   shared, replayed, change-detected, and backdated like any other value.
3. **Defects** — invariant violations that "can't happen". These `abort` (or
   `fail`). A retained `raise Failure` from a compute is *defined* to mean this.

### Why value-as-Result is the ideal, not a workaround

The tempting alternative — a unified `ReadError = Cycle | Compute(E)` carried in
the read channel — fights memoization:

- **Caching question.** Must `Compute(E)` be cached, or re-run every read? If
  cached, it is a value (so make it one). If re-run, reads become effects and
  deterministic sharing is destroyed.
- **Change detection.** Backdating/invalidation is driven by value `Eq`
  (`cells/derived.mbt`). A reified `Err(e)` participates in invalidation exactly
  like `Ok(v)`: an `Err → Ok` transition correctly invalidates downstream. An
  error carried in the channel does not diff this way.
- **Viral propagation.** Every transitive reader would inherit an error arm it
  can only re-propagate, collapsing to "everyone re-raises" — observationally an
  abort that is merely typed.

So domain fallibility belongs in the value. The read channel carries only
mechanism failures, which *are* uniform and unrecoverable by domain readers.

### Error polymorphism does not apply to the read API

`raise?` / `-> T raise E` is honest and free for *synchronous pass-through*
higher-order functions (a conduit that forwards the callee's effect up the same
call). A `Derived` is a **store**, not a conduit. An audit of the public read
surface (2026-05-28) found it is *entirely* cached — `Input`, `InputField`,
`Derived`, `ReachableDerived`, `Memo`, `HybridMemo`, `DerivedMap`, `MemoMap`,
`Watch`, `Observer`, the `Runtime` read helpers, and the relations all serve
stored values; there are **no** pass-through reads. Across a cache boundary,
`Derived[T, E]` (error-polymorphic) necessarily degenerates into
`Derived[Result[T, E]]` — caching forces reification. So error polymorphism adds
nothing on the public read API; it remains the right model only for the
*internal* recompute path, where `pull_verify` already carries `raise Failure`.

`EagerDerived` is also cached (compute runs at construction/propagation, not at
read; its closure is `() -> T`, no raise) — it has no dishonesty to fix.

## Target API

```text
// Mechanism failures only. (Full ideal; cheapest increment keeps CycleError
// + abort-on-dispose and introduces this later.)
enum ReadError {
  Cycle(CycleError)
  Disposed(CellId)
}

// Infallible-at-the-mechanism compute. Fallibility lives in T.
Derived(rt, compute : () -> T raise Failure, label?)   // unchanged; raise = defect
Derived::fallible(rt, compute : () -> Result[V, E], label?) -> Derived[Result[V, E]]
DerivedMap::fallible(rt, compute : (K) -> Result[V, E], label?) -> DerivedMap[K, Result[V, E]]

Derived::read(self)          -> Result[T, ReadError]   // full ideal
Derived::read_or_abort(self) -> T                      // unwraps; survives
// ... mirrored on ReachableDerived, DerivedMap, Watch.
Memo::accumulated(acc)       -> Result[Array[A], ReadError]
Memo::accumulated_peek(acc)  -> Array[A]               // pure cached side-data
```

A domain-recovering consumer (e.g. a workspace diagnostics aggregator that must
*report*, not crash, on a failed parse) watches `Derived[Result[Ast, ParseError]]`:
it treats `Err(Cycle | Disposed)` from `read()` as a graph-health report, an
`Ok(Err(parse_error))` as a diagnostic to emit, and `Ok(Ok(ast))` as the AST. It
never catches a compute exception.

### The `accumulated*` fork

`accumulated*` is the one path that reads cached side-data while *synchronously*
forcing target-memo verification, so it is neither cleanly cached nor
pass-through. Treatment: `accumulated_peek` stays a pure cached read;
`accumulated` returns `Result[Array[A], ReadError]` for mechanism failures, and a
domain failure is simply the target memo's cached value. Open semantic question:
whether accumulator pushes during an `Err` value are committed — recommended
**yes**, because `Err` is a successful cached value.

## Migration

### Tier 1 — cheapest honest increment (this spec's accompanying PR)

Non-breaking; downstream `canopy` (which already wraps `Watch::read` in an
`AbortReport`) is untouched.

- Keep all current signatures (`read -> Result[T, CycleError]`, etc.).
- Add `Derived::fallible` and `DerivedMap::fallible`. Their closure is
  **noraise** (`() -> Result[V, E]`), so domain errors are *forced* into the
  value at the type level — you cannot raise for a domain error through this
  path.
- Redefine the meaning of a compute `raise Failure` as **defect-only** in the
  docs (api-reference, cookbook); stop advertising it as a domain-error channel.

### Tier 2 — full ideal (later, breaking)

- Introduce `ReadError`; widen the read family from `Result[T, CycleError]` to
  `Result[T, ReadError]`.
- Convert disposed-read `abort` sites to `Err(Disposed(_))`.
- Ripple through `Watch`, `Derived`, `ReachableDerived`, `DerivedMap`,
  `accumulated*`, and downstream (`canopy`'s `WorkspaceMemoHandle::read`,
  `ProtectedCell`). `_or_abort` variants survive as unwrapping convenience.

## Risks & open questions

- **`CycleError → ReadError` widening** touches many call sites (Tier 2 cost).
- **`E : Eq` quality.** A poor `Eq` on the domain error causes missed
  invalidation (stale) or noisy recomputation. Reified errors are change-detected
  like values; transient/non-deterministic failure should be modeled as an
  *input* cell, never hidden inside a compute.
- **`accumulated*` push-during-`Err`** commit semantics (recommended: commit).
