# incr

A Salsa-inspired incremental recomputation library for [MoonBit](https://www.moonbitlang.com/).

`incr` tracks dependencies automatically, memoizes derived values, and skips unnecessary work when inputs change — so you write straight-line code and the runtime figures out what to recompute.

**Core primitives:**

- **`Signal[T]`** — input cells you write to directly
- **`Memo[T]`** — derived computations that memoize and auto-track dependencies
- **`MemoMap[K, V]`** — keyed memoization, one memo per key, created lazily
- **Backdating + durability** — skip downstream work when values didn't really change or inputs rarely do

Advanced features (push-reactive `Reactive[T]` / `Effect`, hybrid push-pull `HybridMemo`, field-level `TrackedCell`, side-channel `Accumulator[T]`, Datalog `Relation` / `FunctionalRelation` / fixpoint, batching, cycle-safe reads) are covered in [docs/](docs/README.md).

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
// Recommended: Database pattern (encapsulates Runtime)
struct MyApp {
  rt : Runtime
}

fn MyApp::MyApp() -> MyApp {
  { rt: Runtime::new() }
}

impl Database for MyApp with runtime(self) { self.rt }

let app = MyApp()

// Create input signals
let x = create_signal(app, 10)
let y = create_signal(app, 20)

// Create derived computations
let sum = create_memo(app, () => x.get() + y.get())

// `.get()` is only legal inside a memo's compute. Outside the graph
// (top-level code, tests, event handlers) read with `rt.read(memo)`.
inspect(app.runtime().read(sum), content="30")

// Update an input — downstream memos recompute on the next read
x.set(5)
inspect(app.runtime().read(sum), content="25")
```

For simple scripts, `Runtime` can also be used directly (`Signal::new(rt, ...)`, `Memo::new(rt, ...)`). Both styles are fully supported — see [Getting Started](docs/getting-started.md).

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
moon test     # Run all tests (~590 test blocks across cells/ and tests/)
moon bench    # Run benchmarks (always pass --release for representative numbers)
```

Contributor and coding-agent guidance lives in [AGENTS.md](AGENTS.md).

## Supported targets

Builds and tests pass on the WASM-GC backend (the default for `moon test`). Other MoonBit backends are not currently exercised in CI; treat them as unverified.

## License

Apache-2.0
