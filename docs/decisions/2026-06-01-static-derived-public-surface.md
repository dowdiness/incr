# ADR: Static Derived Public Surface — Keep Private

**Date:** 2026-06-01
**Status:** Accepted — keep private; reopen only with a concrete driver
**Issue:** [#138](https://github.com/dowdiness/incr/issues/138)
**Implementation plan:** None. This is a no-public-API decision. The option analysis and hard requirements remain in [2026-05-28 Static Derived Public-Surface Options](../design/specs/2026-05-28-static-derived-public-options.md).
**Evidence:** [2026-05-27 Static/applicative Derived fast-path probe](../performance/2026-05-27-static-derived-fast-path-probe.md), [2026-05-25 `Expr[T]` Formula API](../design/specs/2026-05-25-expr-formula-api.md), [2026-05-26 Build-oriented boundary design](../design/specs/2026-05-26-build-trait-boundaries.md)

## Context

PR [#135](https://github.com/dowdiness/incr/pull/135) shipped a package-private static/applicative `Derived` fast path. It returns normal target-facade `Derived` handles backed by the pull backend, registers a fixed dependency list once, and recomputes without dynamic tracking-stack allocation or dependency-list diffing. The private entry points remain package-local (`StaticDerivedSource`, `Runtime::install_static_derived`, and helpers in `cells/static_derived_probe.mbt`).

The measured signal is real: scalar map1/map2/map3 stale recomputes are roughly 1.4–1.9× faster than dynamic `Derived`, and the UI tree-shaped graph still wins on both wasm-gc and JS. The layered fanout shape is noise/small-win level because one derived recompute is amortized across many eager leaves.

Issue #138 asked whether this private fast path should become a public API now. The options note compared three public directions — arity-specific map/map2/map3, scope-owned static constructors, and `Expr[T]` lowering — plus keeping the path private. The current repo has no concrete consumer that needs a public static surface: `Expr[T]` is still a proposed formula layer, no scope-owned attachment pipeline has shown an end-to-end win from the private path, and the recent typed-spreadsheet render-cache work was a demo-side sparse snapshot optimization, not a static-derived driver.

## Decision

Choose **Option D: keep the static path private**.

Do not add public `Derived::map`, `Derived::map2`, `Derived::map3`, `Scope::derived_static*`, compatibility-handle static conveniences, or a raw `Array[CellId] + () -> T` installer from the options note.

The private engine path may continue to support benchmarks, white-box tests, and future internal probes. Any future public surface must still satisfy the hard requirements from the options note: target-facade vocabulary, same-runtime validation, duplicate-dependency normalization, declaration-bound static-to-static reads, no accumulator support without a safe design, normal `Derived` semantics, failure cleanup, and unchanged inside/outside read semantics.

Reopen the public-surface decision only when at least one concrete driver exists:

1. an accepted `Expr[T]` / formula layer needs to lower a pure fixed-source expression graph into materialized cells;
2. a scope-owned attachment pipeline creates a tree of tiny fixed-dependency nodes where the private path changes an end-to-end benchmark;
3. a UI library or downstream app duplicates fixed-source `Derived` wrappers often enough that the private path is inaccessible where it matters.

When a trigger fires, design the first public API from that consumer's shape. Treat `Expr[T]` lowering as the likely ergonomic path for formulas, scope-owned constructors as the likely path for attachment pipelines, and direct map/map2/map3 only as a candidate if a direct fixed-source API has its own driver. The raw installer remains rejected.

## Rationale

- The measurements justify retaining and hardening the private engine path, but they do not identify a public signature that users need now.
- Adding arity-specific combinators before a consumer exists would commit to names, arity limits, mixed-source-kind rules, and backdating policy while the target facade migration is still fresh.
- Scope-owned constructors are attractive only if the first driver is an attachment pipeline with a measured end-to-end tree-shaped win.
- `Expr[T]` lowering is the best long-term formula story, but coupling static-derived exposure to an unimplemented formula API would settle two public designs at once.
- Keeping the API closed preserves the hard safety requirements without exposing a footgun that can read undeclared dependencies.

## Consequences

- The public `.mbti` surface should not change for this decision.
- Users continue to use ordinary `Derived` / `Scope::derived` unless a future accepted API adds a fixed-source surface.
- The private static path remains available for benchmark coverage and future implementation experiments.
- Issue #138 can close as a docs/decision outcome, with no public API implementation.
- A future public static-derived API requires a fresh design/spec pass tied to one of the reopen triggers above.
