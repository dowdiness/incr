# incr

An incremental computation library for [MoonBit](https://www.moonbitlang.com/).

When one input changes, `incr` recomputes only the values that actually depend
on it — and skips everything else. You write ordinary straight-line code; the
runtime figures out what is affected.

The mental picture is a **spreadsheet**: some cells hold values you type in,
other cells hold formulas. Change one input cell and only the formulas that
read it (directly or indirectly) update. `incr` gives your MoonBit program the
same behavior for any computation — editor state, build pipelines, reactive
app models, language tooling — without you writing any change-tracking code.

You can try exactly this picture live: the
[typed spreadsheet demo](https://typed-spreadsheet.pages.dev) is built on
`incr`. Edit one cell and its trace panels show which formulas recomputed,
which didn't, and why.

## Quick Start

Two kinds of cells cover most programs:

- **`Input[T]`** — a value you set directly (a spreadsheet cell you type into)
- **`Derived[T]`** — a value computed from other cells (a formula cell); it
  caches its result and notices which cells it read, automatically

```moonbit nocheck
let rt = Runtime()

// Create inputs
let x = rt.input(10, label="x")
let y = rt.input(20, label="y")

// Combine inputs and chain further derived stages
let sum = x.derived2(y, (a, b) => a + b, label="sum")
let doubled = sum.map(v => v * 2, label="doubled")

// Outside the graph, read with `read_or_abort()` or `read()`.
// (`.get()` is only legal inside another derived computation —
// use `Derived(rt, () => ...)` when a stage reads several cells.)
inspect(sum.read_or_abort(), content="30")
inspect(doubled.read_or_abort(), content="60")

// Update an input — downstream derived values recompute on the next read
x.set(5)
inspect(doubled.read_or_abort(), content="50")
```

There is no subscription or dependency declaration anywhere in that code:
`sum` knows it depends on `x` and `y` because it read them.

When a group of cells or long-lived reads shares a lifetime, construct cells
through a `Scope` (`scope.input(...)`, `scope.derived(...)`) and register
watches with `scope.add_watch(...)` so one `scope.dispose()` tears the group
down. See [Getting Started](../docs/getting-started.mbt.md).

> **Note on the example above:** It is `nocheck` because the snippet omits imports and a test wrapper. The same construction is checked in [`docs/target_api_examples.mbt.md`](../docs/target_api_examples.mbt.md) and exercised end-to-end by [`tests/quickstart_test.mbt`](tests/quickstart_test.mbt) — if you edit the example, update those in lockstep.

## Installation

Add `incr` to the `import` list of your `moon.pkg.json`:

```json
{
  "import": ["dowdiness/incr"]
}
```

The core library packages use only `moonbitlang/core`; optional repository demos may declare extra dependencies such as Rabbita.

## How It Works, in Plain Words

1. **Writes are cheap.** `x.set(5)` records "something changed" (a counter
   ticks up) and returns. Nothing recomputes yet.
2. **Reads check before they work.** When you later read `doubled`, the
   runtime walks back through what `doubled` read last time and asks: did any
   of it actually change? Untouched branches are skipped without running any
   of your code.
3. **"Same answer" stops the ripple.** If a recomputed value comes out equal
   to its previous value, everything downstream of it is also skipped. (The
   docs call this **backdating** — the value's "last changed" timestamp is
   kept in the past.)
4. **Dependencies can change between runs.** If a formula reads different
   cells this time (say, an `if` took the other branch), the recorded
   dependencies are simply replaced. Nothing is declared up front.

Guarantees you can rely on:

- Failed computations and cycle errors never corrupt the cache: the last
  successful result and its recorded dependencies stay authoritative.
- Reads that can fail return `Result` (`read()` / `get()`); a dependency
  cycle or a disposed cell comes back as an `Err` you can handle, not a
  crash. The `_or_abort` variants abort instead, for when failure is a bug.
- Caching is in-memory and per-process. Nothing persists across runs.

## Beyond Input and Derived

Most programs only need `Input` and `Derived`. The rest of the toolbox, from
most to least commonly needed:

| Type | What it is for |
|---|---|
| `DerivedMap[K, V]` | One cached derived value **per key** (e.g. `type_of(function_id)`), created lazily on first read |
| `InputField[T]` | One input cell per **field** of a struct, so changing one field doesn't disturb readers of the others |
| `EagerDerived[T]` / `Effect` | Values/side effects that update **immediately** when inputs change (push style) — for UI-facing state |
| `ReachableDerived[T]` | A lazy derived value that must stay alive across garbage collection while something downstream watches it |
| `Accumulator[T]` | A side channel for log-like data (diagnostics, traces) emitted during computation |
| `Relation` / `MapRelation` | Datalog-style facts and rules, computed to a fixed point |

Also available on any runtime: **batching** (`rt.batch` groups several `set`
calls into one atomic change, with rollback on error) and **durability**
(mark rarely-changing inputs like configuration so their whole subgraph can
skip checks).

### Which type should I use?

| Need | Use |
|---|---|
| Default cached computation, especially if it may not be read after every input write | `Derived` |
| One memoized value per semantic key, created lazily | `DerivedMap` |
| Field-level invalidation inside a larger object | `InputField` |
| UI-facing value that should stay eagerly current after input writes | `EagerDerived` |
| Side effect that should run eagerly when dependencies change | `Effect` |
| Lazy derived value that must stay alive through downstream push subscribers or long-lived watches | `ReachableDerived` |
| Relational/fixpoint computation | `Relation` / `MapRelation` |

When unsure, start with `Derived`. Move to `EagerDerived` only when the
consumer really benefits from push-first maintenance.

## Learn More

- **New to `incr`?** Start with [Getting Started](../docs/getting-started.mbt.md), then [Core Concepts](../docs/concepts.mbt.md).
- **Looking for a specific pattern?** Backdating, durability, keyed queries, batched updates with rollback, cycle-safe reads, and more are covered in the [Cookbook](../docs/cookbook.mbt.md).
- **Looking up a type or method?** See the [API Reference](../docs/api-reference.mbt.md).
- **Exploring the practical demo?** Try the live [typed spreadsheet](https://typed-spreadsheet.pages.dev), run the [CLI demo](../examples/typed_spreadsheet_cli_demo/README.md) for the fixed trace, or build the [editable Rabbita Web demo](../examples/typed_spreadsheet_rabbita_demo/README.md) locally.
- **Working on `incr` itself?** [docs/architecture.md](../docs/architecture.md) (package map) and [docs/design/internals.md](../docs/design/internals.md) (algorithms).

Full documentation index: [docs/README.md](../docs/README.md).

## Background and Theory

This section is for readers who know the incremental-computation literature;
skip it freely.

`incr` is inspired by [Salsa](https://github.com/salsa-rs/salsa) (the
demand-driven incremental recomputation model behind rust-analyzer) and
[Build Systems à la Carte](https://hackage.haskell.org/package/build) (the
separation between task meaning, store/trace data, scheduler, and rebuilder
strategy; see the [build-oriented boundary design](../docs/design/specs/2026-05-26-build-trait-boundaries.md)
and [internal evaluation boundaries](../docs/design/specs/2026-05-26-internal-rebuild-boundaries.md)).

In that vocabulary, the default pull engine is a **suspending scheduler**
plus a **revision-based verifying-trace** rebuilder:

- A `Derived` compute closure is the task; the runtime records the
  dependencies read by the last successful compute.
- `Input::set(...)` bumps a revision; it does not eagerly recompute the pull graph.
- A later read verifies the recorded trace on demand: no dependency changed →
  the closure does not run (**green path**); a dependency changed → the
  closure reruns and records a new trace (**red path**); an equal result on
  the red path preserves `changed_at` (**backdating**, the paper's early
  cutoff).

The push engine (`EagerDerived` / `Effect`) uses a different contract:
compute at construction, then recompute during `Input::set(...)` / batch
commit propagation in topological-level order. `ReachableDerived` is hybrid
only in reachability/GC behavior; its recomputation is the same lazy revision
check as `Derived`. Cross-session/content-addressed caching is not automatic —
see the [constructive traces feasibility note](../docs/research/constructive-traces-feasibility.md).

Naming note: as of v0.13.0 the compatibility names (`Reactive`, `TrackedCell`,
`FunctionalRelation`, `Database`, `Readable`, `Trackable`, and the older
`Memo`-family / `Signal` names) have been removed; use the target names
(`EagerDerived`, `InputField`, `MapRelation`, `RuntimeContext`, `Freshness`,
`InputFieldOwner`, `Derived`, `Input`) instead. Migrating older code? See the
[CHANGELOG](../CHANGELOG.md). The naming direction is recorded in
[ADR 2026-05-21](../docs/decisions/2026-05-21-public-api-ideal-naming.md).

## Development

```bash
moon check    # Type-check the workspace
moon build    # Build the workspace
moon test     # Run all workspace tests
moon bench    # Run benchmarks (always pass --release for representative numbers)
```

Contributor and coding-agent guidance lives in [AGENTS.md](../AGENTS.md).

## Supported targets

Builds and tests pass on the WASM-GC backend (the default for `moon test`). Other MoonBit backends are not currently exercised in CI; treat them as unverified.

## License

Apache-2.0
