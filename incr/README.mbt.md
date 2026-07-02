# incr

A Salsa- and [Build Systems à la Carte](https://hackage.haskell.org/package/build)-inspired incremental recomputation library for [MoonBit](https://www.moonbitlang.com/).

`incr` tracks dependencies automatically, memoizes derived values, and skips unnecessary work when inputs change — so you write straight-line code and the runtime figures out what to recompute.

Salsa informs the demand-driven incremental recomputation model. Build Systems à la Carte informs the separation between task meaning, store/trace data, scheduler, and rebuilder strategy; see the [build-oriented boundary design](../docs/design/specs/2026-05-26-build-trait-boundaries.md) and [internal evaluation boundaries](../docs/design/specs/2026-05-26-internal-rebuild-boundaries.md).

**Core primitives:**

- **`Input[T]`** — input cells you write to directly
- **`Derived[T]`** — derived computations that memoize and auto-track dependencies
- **`DerivedMap[K, V]`** — keyed memoization, one derived value per key, created lazily
- **Backdating + durability** — skip downstream work when values didn't really change or inputs rarely do

Advanced features (push-reactive `EagerDerived[T]` / `Effect`, reachable lazy `ReachableDerived[T]`, field-level `InputField[T]`, side-channel `Accumulator[T]`, Datalog `Relation` / `MapRelation` / fixpoint, batching, cycle-safe reads) are covered in [docs/](../docs/README.md).

Naming note: the target facade names above are the recommended API. Some legacy
compatibility names remain available: `Reactive`, `TrackedCell`, and
`Database`. The legacy `Memo`, `MemoMap`, `HybridMemo`, and `Signal` types were
removed in v0.12.0 — use `Derived`, `DerivedMap`, `ReachableDerived`, and
`Input` respectively.
The naming direction is recorded in [ADR 2026-05-21](../docs/decisions/2026-05-21-public-api-ideal-naming.md).
## Live practical demo

Want to see the runtime before reading the API? Try the live
[typed spreadsheet](https://typed-spreadsheet.pages.dev).

Edit one cell. The sheet routes the edit through MoonBit operations, formula
cells track the other cells they read, and trace/evidence panels separate
formulas that recomputed from values that actually changed. It is a small
example of the same shape behind editor state, build-like pipelines, and
reactive app models: derived values stay fresh without recalculating everything.

## Installation

Add `incr` to the `import` list of your `moon.pkg.json`:

```json
{
  "import": ["dowdiness/incr"]
}
```

The core library packages use only `moonbitlang/core`; optional repository demos may declare extra dependencies such as Rabbita.

## Quick Start

```moonbit nocheck
let rt = Runtime()

// Create inputs
let x = Input(rt, 10, label="x")
let y = Input(rt, 20, label="y")

// Create derived computations
let sum = Derived(rt, () => x.get() + y.get(), label="sum")

// `.get()` is only legal inside another derived computation.
// Outside the graph, use `read_or_abort()` or `read()`.
inspect(sum.read_or_abort(), content="30")

// Update an input — downstream derived values recompute on the next read
x.set(5)
inspect(sum.read_or_abort(), content="25")
```

When a group of cells or long-lived reads shares a lifetime, construct cells
through a `Scope` (`scope.input(...)`, `scope.derived(...)`) and register
watches with `scope.add_watch(...)` so one `scope.dispose()` tears the group
down. See [Getting Started](../docs/getting-started.mbt.md).

> **Note on the example above:** It is `nocheck` because the snippet omits imports and a test wrapper. The same construction is checked in [`docs/target_api_examples.mbt.md`](../docs/target_api_examples.mbt.md) and exercised end-to-end by [`tests/quickstart_test.mbt`](tests/quickstart_test.mbt) — if you edit the example, update those in lockstep.

## Mental Model

`incr` has three coordinated modes:

- **Pull-first by default**: `Input` + `Derived` verify recorded dependency traces lazily on read.
- **Push-first when requested**: `EagerDerived` + `Effect` recompute eagerly when upstream inputs change.
- **Hybrid reachability**: `ReachableDerived` is still lazy like `Derived`, but stays reachable through downstream push subscribers and `Watch` roots.

In the vocabulary of "Build Systems à la Carte", the pull engine is a
**suspending scheduler** plus a **revision-based verifying trace** rebuilder:

- A `Derived` compute closure is the task.
- The runtime records the dependencies read by the last successful compute.
- An `Input::set(...)` bumps a revision; it does not eagerly recompute the pull graph.
- A later `Derived::read()` / `get()` verifies the recorded trace on demand.
- If no dependency changed, the compute closure does not run — the **green path**.
- If a dependency changed, the closure reruns and records a new trace — the **red path**.
- If the red path produces an equal value, **backdating** preserves `changed_at`, so downstream derived values still skip work.

The push engine uses a different contract: `EagerDerived` computes immediately at construction, then recomputes during `Input::set(...)` / batch commit propagation in topological-level order. Reads return the already-maintained cached value.

Hard guarantees to rely on:

- Dynamic dependencies are supported: conditional reads replace the dependency trace on each successful recompute.
- Failed computations and cycle errors do not install a new valid trace.
- Pull mode verifies traces, not dirty flags; push dirty state is not the source of truth for `Derived` correctness.
- `ReachableDerived` is hybrid only in reachability/GC behavior; recomputation is still the same lazy revision check as `Derived`.
- Cross-session/content-addressed caching is not automatic. See the [constructive traces feasibility note](../docs/research/constructive-traces-feasibility.md) for why it remains opt-in research.

### Which mode should I use?

| Need | Use |
|---|---|
| Default cached computation, especially if it may not be read after every input write | `Derived` |
| One memoized value per semantic key, created lazily | `DerivedMap` |
| Field-level invalidation inside a larger object | `InputField` |
| UI-facing value that should stay eagerly current after input writes | `EagerDerived` |
| Side effect that should run eagerly when dependencies change | `Effect` |
| Lazy derived value that must stay alive through downstream push subscribers or long-lived watches | `ReachableDerived` |
| Relational/fixpoint computation | `Relation` / `MapRelation` |

When unsure, start with `Derived`. Move to `EagerDerived` only when the consumer really benefits from push-first maintenance.

## Learn More

- **New to `incr`?** Start with [Getting Started](../docs/getting-started.mbt.md), then [Core Concepts](../docs/concepts.mbt.md).
- **Looking for a specific pattern?** Backdating, durability, keyed queries, batched updates with rollback, cycle-safe reads, and more are covered in the [Cookbook](../docs/cookbook.mbt.md).
- **Looking up a type or method?** See the [API Reference](../docs/api-reference.mbt.md).
- **Exploring the practical demo?** Try the live [typed spreadsheet](https://typed-spreadsheet.pages.dev), run the [CLI demo](../examples/typed_spreadsheet_cli_demo/README.md) for the fixed trace, or build the [editable Rabbita Web demo](../examples/typed_spreadsheet_rabbita_demo/README.md) locally to change cells and inspect operation outcomes, trace buckets, and before/after snapshots.
- **Working on `incr` itself?** [docs/architecture.md](../docs/architecture.md) (package map) and [docs/design/internals.md](../docs/design/internals.md) (algorithms).

Full documentation index: [docs/README.md](../docs/README.md).

## Development

```bash
moon check    # Type-check the workspace
moon build    # Build the workspace
moon test     # Run all workspace tests (~878 test blocks)
moon bench    # Run benchmarks (always pass --release for representative numbers)
```

Contributor and coding-agent guidance lives in [AGENTS.md](../AGENTS.md).

## Supported targets

Builds and tests pass on the WASM-GC backend (the default for `moon test`). Other MoonBit backends are not currently exercised in CI; treat them as unverified.

## License

Apache-2.0
