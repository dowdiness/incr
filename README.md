# incr

A Salsa-inspired incremental recomputation library for [MoonBit](https://www.moonbitlang.com/).

`incr` tracks dependencies automatically, memoizes derived values, and skips unnecessary work when inputs change — so you write straight-line code and the runtime figures out what to recompute.

**Core primitives:**

- **`Signal[T]`** — input cells you write to directly
- **`Memo[T]`** — derived computations that memoize and auto-track dependencies
- **`MemoMap[K, V]`** — keyed memoization, one memo per key, created lazily
- **Backdating + durability** — skip downstream work when values didn't really change or inputs rarely do

Advanced features (push-reactive `Reactive[T]` / `Effect`, hybrid push-pull `HybridMemo`, field-level `TrackedCell`, Datalog `Relation` / `FunctionalRelation` / fixpoint, batching, cycle-safe reads) are covered in [docs/](docs/README.md).

## Quick Start

```moonbit
// Recommended: Database pattern (encapsulates Runtime)
struct MyApp {
  rt : Runtime

  fn new() -> MyApp
}

impl Database for MyApp with runtime(self) { self.rt }

fn MyApp::new() -> MyApp {
  { rt: Runtime() }
}

let app = MyApp()

// Create input signals
let x = create_signal(app, 10)
let y = create_signal(app, 20)

// Create derived computations
let sum = create_memo(app, () => x.get() + y.get())

inspect(sum.get(), content="30")

// Update an input — downstream memos recompute on next access
x.set(5)
inspect(sum.get(), content="25")
```

For simple scripts, `Runtime` can also be used directly (`Signal(rt, ...)`, `Memo(rt, ...)`). Both styles are fully supported — see [Getting Started](docs/getting-started.md).

## Learn More

- **New to `incr`?** Start with [Getting Started](docs/getting-started.md), then [Core Concepts](docs/concepts.md).
- **Looking for a specific pattern?** Backdating, durability, keyed queries, batched updates with rollback, cycle-safe reads, and more are covered in the [Cookbook](docs/cookbook.md).
- **Looking up a type or method?** See the [API Reference](docs/api-reference.md).

Full documentation index: [docs/README.md](docs/README.md).

## Development

```bash
moon check    # Type-check
moon build    # Build
moon test     # Run all tests
```

### Package Structure

The library is split into four MoonBit sub-packages:

| Package | Role |
|---------|------|
| `dowdiness/incr` | Public API facade — re-exports all types via `pub type` aliases |
| `dowdiness/incr/types` | Pure value types: `Revision`, `Durability`, `CellId` |
| `dowdiness/incr/cells` | Engine implementation: `Signal`, `Memo`, `MemoMap`, `HybridMemo`, `Reactive`, `Effect`, `Relation`, `FunctionalRelation`, `Runtime` |
| `dowdiness/incr/pipeline` | Experimental pipeline traits: `Sourceable`, `Parseable`, `Checkable`, `Executable` |
| `dowdiness/incr/tests` | Integration tests exercising the full `@incr` public API |

Users always import the root `@incr` package — the sub-package structure is an implementation detail.

## License

Apache-2.0
