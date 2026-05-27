# Static Derived Public-Surface Options

**Status:** Options note — no public API accepted

**Date:** 2026-05-28

**Parent TODO:** [`docs/todo.md`](../../todo.md#investigation-queue)

**Evidence:** [Static/applicative Derived fast-path probe](../../performance/2026-05-27-static-derived-fast-path-probe.md), [Expr formula API proposal](2026-05-25-expr-formula-api.md), [Build-oriented boundary design](2026-05-26-build-trait-boundaries.md)

## Goal

Decide what public surface, if any, should expose the private
static/applicative `Derived` fast path.

The private probe has already answered the performance question: fixed-dependency
recomputation can win when many tiny `Derived` nodes form tree-shaped graphs.
This note is about API shape only. It does not choose an API and does not ask for
implementation.

## Current measured signal

The hardened private prototype reuses the existing pull backend storage
(`MemoData` / `PullMemo` internally), registers fixed dependencies once, skips
dynamic tracking and dependency-list diffing on recompute, and preserves normal
subscriber, GC, cycle, and commit-hook behavior.

Measured after hardening:

- Scalar stale recomputes: static recovers about half or more of the
  dynamic/manual gap.
  - wasm-gc: ~44–62% gap recovery; ~1.5–1.9× faster than dynamic `Derived`.
  - JS: ~50–59% gap recovery; ~1.8–2.1× faster than dynamic `Derived`.
- UI-shaped benches:
  - layered fanout: at noise level, because one derived recompute is amortized
    across 1000 eager leaves;
  - tree of tiny derived nodes: material win on both targets, roughly 1.5× on
    wasm-gc and 1.6× on JS in the latest run.

Conclusion: a static path is worth keeping private and is worth a public-surface
review. The signal does not justify rushing a broad public API.

## Hard requirements for any public surface

Any accepted public API must preserve these constraints.

1. **Use target facade vocabulary.** Public docs and examples should use
   `Input`, `Derived`, `ReachableDerived`, `EagerDerived`, `DerivedMap`,
   `Scope`, and `Watch`. Compatibility handles remain supported, but should not
   gain new static-derived convenience methods by default.
2. **No arbitrary undeclared-dependency closure.** A public API must not expose
   `Array[CellId] + () -> T` as the main user-facing shape. The closure must
   receive source values or declaration-bound source readers, not a way to read
   unrelated cells silently.
3. **Validate same runtime at construction.** Cross-runtime source composition is
   misuse and should fail before the first recompute where possible.
4. **Normalize duplicate fixed dependencies.** Duplicate sources should produce
   one dependency edge and one subscriber link.
5. **Preserve existing graph semantics.** Static derived cells must keep normal
   `Derived` behavior for subscribers, `Watch`/GC reachability, `changed_at`,
   `verified_at`, labels, cycle errors, event hooks, and disposal cleanup.
6. **Static-to-static reads must be declaration-bound.** A static derived cell may
   read another static derived cell only when that source was declared as one of
   its fixed dependencies.
7. **No accumulator support in static recompute.** Accumulator push/read paths
   rely on an active tracking frame. A static recompute path should reject them
   explicitly until a real driver proves a safe design is needed.
8. **Failure cleanup is non-negotiable.** A raised compute must clear
   `in_progress`, static recompute depth/state, and commit-hook active entries.
9. **Keep inside/outside read semantics unchanged.** Inside ordinary tracked
   closures, users read the resulting `Derived` with `.get()` or
   `.get_or_abort()`. Outside the graph, users read with `.read()`,
   `.read_or_abort()`, or `Watch`.

## Rejected baseline: public raw static installer

A raw public installer would look like this in spirit:

```moonbit
// Rejected shape.
Derived::static(rt, deps=[a.id(), b.id()], () => {
  // user can accidentally read c here with no declared edge
})
```

This is the private-probe shape, not a user API. It is too easy to create stale
values by reading an undeclared source. It also makes same-runtime validation and
typed source ergonomics worse than the dynamic `Derived` constructor users
already have.

A lower-level unsafe installer can remain package-private for experiments, but a
public surface should make the dependency declaration and value flow the same
thing.

## Option A: arity-specific fixed-source combinators

Expose a small family of fixed-source constructors, commonly described as
`map`, `map2`, and `map3`, that receive source handles and pass source values to
the user function.

Illustrative shape, not a final signature:

```moonbit
let doubled = input.map(x => x * 2, label="doubled")
let total = Derived::map2(price, quantity, (p, q) => p * q, label="total")
```

The essential property is that the closure receives values, not handles. The
runtime can install fixed dependencies from the source handles before the first
compute, and the closure has no reason to call `get()` / `peek()` on those
sources.

### Strengths

- Best matches the measured scalar shapes: map1/map2/map3.
- Makes dependency declaration explicit and type-directed.
- Gives the optimizer the strongest guarantee: fixed source list, no dynamic
  tracking frame, no dependency diff.
- Easy to explain for formulas and UI view-model nodes.

### Risks

- MoonBit does not have variadic generics, so arity grows as separate public
  functions.
- Mixed source kinds (`Input`, `Derived`, `ReachableDerived`, `EagerDerived`) are
  awkward without either duplicated method names or a public source-wrapper type.
- The name `map` may be read as ordinary value transformation, not as a promise
  of fixed graph shape. The docs would need to make the static-dependency
  contract explicit.
- If methods are added directly to compatibility handles too, the target-facade
  migration surface expands in the wrong direction. Avoid that.

### Fit

This is the smallest plausible public surface if the project wants users to get
the tree-shaped win soon. It should still wait for a concrete signature design
that handles mixed source kinds without broad API sprawl.

## Option B: scoped static constructors

Expose static construction through `Scope`, for example an arity-specific family
under a name such as `derived_static`.

Illustrative shape, not a final signature:

```moonbit
let total = scope.derived_static2(price, quantity, (p, q) => p * q, label="total")
```

The scope would own the created cell just like `Scope::derived` owns ordinary
`Derived` cells.

### Strengths

- Makes lifetime ownership explicit from the beginning.
- Avoids adding many methods to every source handle.
- The word `static` communicates the fixed-dependency contract better than
  plain `map`.
- Fits attachment-style code where a parser or analysis object already owns a
  `Scope` and terminal `Watch`.

### Risks

- It is less ergonomic for one-off formulas and small examples.
- It still needs arity-specific typed source parameters. A single
  `Array[CellId] + closure` version would violate the undeclared-dependency
  requirement.
- Users may expect `Scope::derived_static` to be a drop-in faster
  `Scope::derived`, but it is only valid when dependencies are structurally
  fixed and all source reads are represented by the parameters.

### Fit

This is a good candidate for code that already follows the attachment + scope
pattern. It is probably not sufficient as the only ergonomic surface for formula
work unless paired with source combinators or expression lowering.

## Option C: expression/formula lowering chooses the static path

The proposed `Expr[T]` formula layer can remain the ergonomic API. When an
expression is materialized, the implementation can lower purely applicative
expression graphs to the static engine and leave dynamic closures on ordinary
`Derived`.

Illustrative user shape from the formula proposal:

```moonbit
let subtotal = (cart.price.expr() * cart.quantity.expr()).derived(
  label="subtotal",
)
```

Under this option, users do not choose static vs dynamic directly for simple
formulas. The formula builder carries source structure, so materialization can
install fixed dependencies when safe.

### Strengths

- Best long-term ergonomics for scalar formulas.
- Avoids exposing performance vocabulary in common application code.
- Naturally prevents undeclared source reads for built-in operators because the
  expression graph owns its source list.
- Can share the same fixed-source internals as Options A/B.

### Risks

- Couples two unsettled API designs. The formula API already has its own open
  questions: constants, labels, same-runtime validation, operator coverage, and
  materialization shape.
- Does not help users who want a direct non-operator fixed-source constructor.
- A formula closure combinator that accepts arbitrary user code can reintroduce
  the undeclared-read footgun unless it is clearly separated from static-safe
  expression nodes.

### Fit

This is the best eventual ergonomic story, but it should not be the first and
only static-derived decision. It is better as a future lowering strategy once
`Expr[T]` itself is accepted.

## Option D: keep the static path private

Do not add a public API yet. Keep the private path for benchmarks and for future
internal consumers, and revisit after a real downstream tree-shaped UI graph
asks for it.

### Strengths

- Avoids committing to an arity or naming scheme before there is user pressure.
- Keeps the public API smaller while target-facade migration is still fresh.
- Lets implementation details evolve: source wrappers, mixed source kinds,
  accumulator policy, and expression lowering can be tested privately.

### Risks

- Users cannot access a measured tree-shaped win.
- Future formula or UI-library code may duplicate dynamic `Derived` patterns that
  the static path could avoid.
- The private probe can drift from public needs if no surface design is kept in
  view.

### Fit

This is acceptable if the next release should avoid new public API. It should be
paired with a short list of criteria that would reopen the decision.

## Cross-cutting design questions

Before implementation, answer these in a real design spec:

1. **Source abstraction:** Do public combinators operate on concrete handles only,
   or introduce a small public fixed-source wrapper? MoonBit traits cannot hide
   an associated value type, so a generic `Source[T]` shape may need to be a
   concrete wrapper rather than a trait.
2. **Mixed source kinds:** What combinations are supported in v1? `Input` +
   `Derived` is the common case; `ReachableDerived` and `EagerDerived` need
   explicit read semantics.
3. **Method placement:** Are map methods receiver methods on sources, static
   constructors on `Derived`, scoped constructors on `Scope`, or some mix?
4. **Arity limit:** Is v1 map1/map2/map3 only? The bench evidence covers those
   scalar arities plus tree composition through repeated map1.
5. **Backdating policy:** Should v1 require `T : Eq`, mirror ordinary
   `Derived`, or expose no-backdate/backdate-eq variants later?
6. **Labels:** How should labels propagate through map chains and formula
   lowering? Require an explicit `label?` on each materialized cell for v1.
7. **Docs wording:** How do docs make clear that static derived is a fixed-source
   optimization, not a replacement for dynamic `Derived`?
8. **Fallback path:** If a user needs dynamic dependencies or accumulator reads,
   the answer should remain ordinary `Derived`.

## Recommendation for the next step

Do not implement a public static-derived API from this note alone.

The private implementation is hardened enough that a public decision is now a
surface-design question, not a correctness-probe question. The next step should
be a short decision/spec pass that chooses between:

- **Option A** for the smallest direct user-facing API;
- **Option B** if scope-owned attachment pipelines are the first target driver;
- **Option D** if keeping the public API closed for one more release is more
  valuable than exposing the measured win now.

Treat **Option C** as a likely future lowering strategy for the formula API, not
as the first public static-derived surface.
