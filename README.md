# incr

A Salsa-inspired incremental recomputation library for [MoonBit](https://www.moonbitlang.com/).

## Features

- **Signal[T]** — Input cells with same-value optimization and durability levels
- **Memo[T]** — Derived computations with automatic dependency tracking and memoization
- **MemoMap[K, V]** — Keyed memoization with one lazily-created memo per key
- **Backdating** — Unchanged recomputed values preserve their old revision, preventing unnecessary downstream recomputation
- **Durability** — Classify inputs by change frequency (Low/Medium/High) to skip verification of stable subgraphs
- **Batch updates** — Atomic multi-signal updates with revert detection and rollback on raised errors
- **Change hooks** — `Runtime::set_on_change` callback for committed updates (batch-aware)
- **Cycle detection** — Detects cycles with `get_result()` for graceful handling or `get()` for abort
- **Field-level tracking** — `TrackedCell` groups related signals into tracked structs; only changed fields invalidate downstream memos

## Quick Start

```moonbit
// Recommended: Database pattern (encapsulates Runtime)
struct MyApp {
  rt : Runtime

  fn new() -> MyApp
}

impl IncrDb for MyApp with runtime(self) { self.rt }

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

### Alternative: Direct Runtime Usage

For simple scripts or when you need more control:

```moonbit
let rt = Runtime()
let x = Signal(rt, 10)
let y = Signal(rt, 20)
let sum = Memo(rt, () => x.get() + y.get())

inspect(sum.get(), content="30")
x.set(5)
inspect(sum.get(), content="25")
```

### Backdating

When an intermediate memo recomputes to the same value, downstream memos skip recomputation:

```moonbit
let rt = Runtime()
let input = Signal(rt, 4)
let is_even = Memo(rt, () => input.get() % 2 == 0)
let label = Memo(rt, () => if is_even.get() { "even" } else { "odd" })

inspect(label.get(), content="even")

// 4 -> 6: is_even is still true, so label does not recompute
input.set(6)
inspect(label.get(), content="even")
```

### Durability

Signals that change rarely can be marked as high durability. Memos that only depend on high-durability inputs skip verification entirely when only low-durability inputs change:

```moonbit
let rt = Runtime()
let config = Signal(rt, 100, durability=High)
let source = Signal(rt, 1)
let config_derived = Memo(rt, () => config.get() * 2)

inspect(config_derived.get(), content="200")

// Changing the low-durability source does not cause config_derived to reverify
source.set(2)
inspect(config_derived.get(), content="200")
```

### Keyed Queries

Use `MemoMap` (or `create_memo_map`) when you want per-key memoization:

```moonbit
let app = MyApp()
let base = create_signal(app, 10)
let by_id = create_memo_map(app, (id : Int) => base.get() + id, label="by_id")

inspect(by_id.get(1), content="11")
inspect(by_id.get(1), content="11") // cache hit for key=1
inspect(by_id.get(2), content="12") // independent key cache
```

### Graceful Error Handling

Prefer `get_result()` when you want cycle-safe reads without aborting:

```moonbit
match sum.get_result() {
  Ok(v) => println(v.to_string())
  Err(e) => println(e.format_path(app.runtime()))
}
```

`Runtime::batch` (and `@incr.batch`) also supports raised-error rollback:

```moonbit
suberror BatchStop {
  Stop
}

let res : Result[Unit, Error] = try? rt.batch(fn() raise {
  x.set(1)
  y.set(2)
  raise Stop
})
// If res is Err(_), pending writes were rolled back.
```

For explicit `Result` handling without re-raising, use `batch_result`:

```moonbit
let res = batch_result(app, fn() raise {
  x.set(1)
  raise Stop
})
```

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started](docs/getting-started.md) | Step-by-step tutorial for new users |
| [Core Concepts](docs/concepts.md) | Understand Signals, Memos, Revisions, Durability, and Backdating |
| [API Reference](docs/api-reference.md) | Complete reference for all public types and methods |
| [Cookbook](docs/cookbook.md) | Common patterns and recipes |
| [API Design Guidelines](docs/api-design-guidelines.md) | Design philosophy, best practices, and planned improvements |

### For Contributors

| Document | Description |
|----------|-------------|
| [Design](docs/design.md) | Deep technical internals: verification algorithm, type erasure, implementation details |
| [Roadmap](docs/roadmap.md) | High-level future direction with phased improvements |
| [TODO](docs/todo.md) | Concrete actionable tasks with checkboxes |
| [Comparison with alien-signals](docs/comparison-with-alien-signals.md) | Analysis of different reactive frameworks |
| [API Updates](docs/api-updates.md) | Summary of recent API documentation changes |

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
| `dowdiness/incr/internal` | Engine implementation: `Signal`, `Memo`, `MemoMap`, `Runtime`, verification algorithm |
| `dowdiness/incr/pipeline` | Experimental pipeline traits: `Sourceable`, `Parseable`, `Checkable`, `Executable` |
| `dowdiness/incr/tests` | Integration tests exercising the full `@incr` public API |

Users always import the root `@incr` package — the sub-package structure is an implementation detail.

## License

Apache-2.0
