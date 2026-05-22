# incr

A Salsa-inspired incremental recomputation library for [MoonBit](https://www.moonbitlang.com/).

`incr` tracks dependencies automatically, memoizes derived values, and skips unnecessary work when inputs change — so you write straight-line code and the runtime figures out what to recompute.

**Core primitives:**

- **`Input[T]`** — input cells you write to directly
- **`Derived[T]`** — derived computations that memoize and auto-track dependencies
- **`DerivedMap[K, V]`** — keyed memoization, one derived value per key, created lazily
- **Backdating + durability** — skip downstream work when values didn't really change or inputs rarely do

Advanced features (push-reactive `EagerDerived[T]` / `Effect`, reachable lazy `ReachableDerived[T]`, field-level `InputField[T]`, side-channel `Accumulator[T]`, Datalog `Relation` / `MapRelation` / fixpoint, batching, cycle-safe reads) are covered in [docs/](docs/README.md).

Naming note: the target facade names above are the recommended API. Legacy
compatibility names remain available during migration: `Signal`, `Memo`,
`HybridMemo`, `Reactive`, `MemoMap`, `TrackedCell`, and `Database`. The naming
direction is recorded in [ADR 2026-05-21](docs/decisions/2026-05-21-public-api-ideal-naming.md).

## Installation

Add `incr` to the `import` list of your `moon.pkg.json`:

```json
{
  "import": ["dowdiness/incr"]
}
```

The library has no runtime dependencies beyond `moonbitlang/core`.

## Quick Start

```moonbit nocheck
// Recommended: RuntimeContext pattern (encapsulates Runtime)
struct MyApp {
  rt : Runtime
}

fn MyApp::MyApp() -> MyApp {
  { rt: Runtime::new() }
}

impl RuntimeContext for MyApp with runtime(self) { self.rt }

let app = MyApp()

// Create inputs
let x = create_input(app, 10)
let y = create_input(app, 20)

// Create derived computations
let sum = create_derived(app, () => x.get() + y.get())

// `.get()` is only legal inside another derived computation.
// Outside the graph, use `read_or_abort()` or `read()`.
inspect(sum.read_or_abort(), content="30")

// Update an input — downstream derived values recompute on the next read
x.set(5)
inspect(sum.read_or_abort(), content="25")
```

For simple scripts, `Runtime` can also be used directly (`Input(rt, ...)`, `Derived(rt, ...)`). Both styles are fully supported — see [Getting Started](docs/getting-started.md).

> **Note on the example above:** It is `nocheck` because it embeds top-level statements alongside type declarations, which `moon check` does not run as a script. The same construction is exercised end-to-end by [`tests/quickstart_test.mbt`](tests/quickstart_test.mbt) — if you edit the example, update that test in lockstep.

## Learn More

- **New to `incr`?** Start with [Getting Started](docs/getting-started.md), then [Core Concepts](docs/concepts.md).
- **Looking for a specific pattern?** Backdating, durability, keyed queries, batched updates with rollback, cycle-safe reads, and more are covered in the [Cookbook](docs/cookbook.md).
- **Looking up a type or method?** See the [API Reference](docs/api-reference.md).
- **Working on `incr` itself?** [docs/architecture.md](docs/architecture.md) (package map) and [docs/design/internals.md](docs/design/internals.md) (algorithms).

Full documentation index: [docs/README.md](docs/README.md).

## Development

```bash
moon check    # Type-check
moon build    # Build
moon test     # Run all tests (~630 test blocks across cells/ and tests/)
moon bench    # Run benchmarks (always pass --release for representative numbers)
```

Contributor and coding-agent guidance lives in [AGENTS.md](AGENTS.md).

## Supported targets

Builds and tests pass on the WASM-GC backend (the default for `moon test`). Other MoonBit backends are not currently exercised in CI; treat them as unverified.

## License

Apache-2.0
