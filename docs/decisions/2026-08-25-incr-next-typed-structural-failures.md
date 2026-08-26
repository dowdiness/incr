# ADR: Propagate Incr Next structural failures with typed raise

**Date:** 2026-08-25
**Status:** Accepted

## Context

The accepted pre-alpha interface returns `Result` from Store, Region, QueryContext, and Transaction operations. This keeps failures typed but forces successful Query definitions to forward `ReadError` manually and produces nested `Result` values when a derived value also contains a domain outcome. MoonBit provides checked, concrete error effects through typed `raise` and `catch`.

## Decision

Incr Next propagates kernel-owned structural failures through concrete typed `raise` channels. Structural failures include evaluation cycles, provenance violations, closed ownership, invalid or expired capabilities, and illegal execution phases. Read, Region definition/lifetime, and Transaction publication retain separate concrete error types because they are handled at different application seams; there is no umbrella `KernelError` in the primitive interface. Their variants are public read-only: consumers may catch and pattern match them, but only the kernel may construct and raise them. Each variant exposes a semantic failure category and carries one opaque public `Diagnostic` with an actionable message and optional help rather than internal Store IDs or Region generations. `Diagnostic` exposes only `message()` and `help()`; source locations and frames are rendered context, not structured public data. Derived Value and Query definitions capture compiler-autofilled source locations so cycle diagnostics identify definition sites without caller-managed labels. Cycle path evidence remains private.

Expected domain outcomes remain values. A derived value may therefore contain `Result[Value, DomainError]`. Each Query invocation records the first Structural Failure observed through its `QueryContext`; even if the callback catches that `ReadError` and returns a value, the kernel discards the temporary trace and value, preserves the previous successful memo, and raises the recorded failure. Domain fallback belongs in the dependency value itself. The single public Transaction operation accepts a callback returning a caller-owned `Result[T, E]`; `Ok(T)` commits and returns the same success value, while `Err(E)` rolls back and returns the same Domain Outcome. `TransactionError` remains a separate typed structural raise. Domain outcomes are not converted into kernel errors merely to use one control-flow mechanism everywhere.

## Rationale

Query computations normally cannot resolve a structural failure locally; they must propagate it without changing its meaning. Typed `raise` expresses that propagation directly while preserving exhaustive handling at application quarantine seams. Keeping domain outcomes as values preserves caching, equality, display, and ordinary domain branching without conflating them with kernel validity.

MoonBit's polymorphic `raise?` can forward a callback's error effect but cannot also inject an unrelated concrete kernel error. Where a higher-order operation must support arbitrary caller-owned domain rejection as well as `TransactionError`, the domain rejection remains a value while the structural failure is raised.

## Consequences

- Public error types become concrete MoonBit error types suitable for typed `raise` and `catch`.
- `ReadError`, `RegionError`, and `TransactionError` remain separate so each operation exposes only failures possible at its catch site. Applications map across these seams into their own error vocabulary when needed.
- Structural error variants are externally matchable but not constructible. Negative compile probes pin this kernel-only construction authority.
- `StoreId`, `RegionGeneration`, and other kernel identities are removed from public error payloads and public interfaces. Every variant carries the same opaque `Diagnostic`; the enclosing variant remains the programmatic category.
- `Diagnostic::message()` and `Diagnostic::help()` are the only public diagnostic accessors. Location ordering, formatting, and internal frames are not compatibility contracts.
- `Store::get` and `QueryContext::get` return values directly and raise `ReadError` only for structural failure.
- Query callbacks return derived values directly and raise `ReadError` only for structural failure.
- Catching a `ReadError` inside a Query callback cannot convert it to a successful memo. The first observed Structural Failure is sticky for that invocation and is re-raised before memo or trace installation. Structural recovery belongs at the root application seam; domain fallback is modeled as `Option` or `Result` data in a dependency.
- Cycle diagnostics include compiler-provided definition locations but do not capture Query keys or computed values. Call syntax remains unchanged through call-site autofill.
- `CycleWitness`, internal node paths, and path accessors are private kernel evidence. Public callers may display the Cycle variant's `Diagnostic` but cannot inspect graph identities or traces.
- There is one generic Transaction operation rather than separate infallible and domain-result variants. It preserves the callback's `Result[T, E]`, committing only `Ok(T)`. Call sites with no possible rejection may need an explicit empty outcome type because MoonBit has no standard bottom type and otherwise defaults an unresolved error type to `Unit` with a warning.
- Kernel internals catch structural failures where necessary to preserve last-successful memo, trace cleanup, rollback, and sticky-poison semantics in both Query invocation and Transaction publication.
- Existing K0 contracts, executable documentation, public consumer fixtures, generated interfaces, and four-target evidence must be revised and reaccepted before alpha publication.
- This decision does not authorize publication, registry mutation, or production integration.
