# incr

A Salsa-inspired incremental recomputation library for [MoonBit](https://www.moonbitlang.com/).

## Features

- **Signal[T]** — Input cells with same-value optimization and durability levels
- **Memo[T]** — Derived computations with automatic dependency tracking and memoization
- **Backdating** — Unchanged recomputed values preserve their old revision, preventing unnecessary downstream recomputation
- **Durability** — Classify inputs by change frequency (Low/Medium/High) to skip verification of stable subgraphs
- **Batch updates** — Atomic multi-signal updates with revert detection
- **Change hooks** — `Runtime::set_on_change` callback for committed updates (batch-aware)
- **Cycle detection** — Detects cycles with `get_result()` for graceful handling or `get()` for abort

## Quick Start

```moonbit
// Recommended: Database pattern (encapsulates Runtime)
struct MyApp {
  rt : Runtime
}

impl IncrDb for MyApp with runtime(self) { self.rt }

fn MyApp::new() -> MyApp {
  { rt: Runtime::new() }
}

let app = MyApp::new()

// Create input signals
let x = create_signal(app, 10)
let y = create_signal(app, 20)

// Create derived computations
let sum = create_memo(app, fn() { x.get() + y.get() })

inspect(sum.get(), content="30")

// Update an input — downstream memos recompute on next access
x.set(5)
inspect(sum.get(), content="25")
```

### Alternative: Direct Runtime Usage

For simple scripts or when you need more control:

```moonbit
let rt = Runtime::new()
let x = Signal::new(rt, 10)
let y = Signal::new(rt, 20)
let sum = Memo::new(rt, fn() { x.get() + y.get() })

inspect(sum.get(), content="30")
x.set(5)
inspect(sum.get(), content="25")
```

### Backdating

When an intermediate memo recomputes to the same value, downstream memos skip recomputation:

```moonbit
let rt = Runtime::new()
let input = Signal::new(rt, 4)
let is_even = Memo::new(rt, fn() { input.get() % 2 == 0 })
let label = Memo::new(rt, fn() { if is_even.get() { "even" } else { "odd" } })

inspect(label.get(), content="even")

// 4 -> 6: is_even is still true, so label does not recompute
input.set(6)
inspect(label.get(), content="even")
```

### Durability

Signals that change rarely can be marked as high durability. Memos that only depend on high-durability inputs skip verification entirely when only low-durability inputs change:

```moonbit
let rt = Runtime::new()
let config = Signal::new(rt, 100, durability=High)
let source = Signal::new(rt, 1)
let config_derived = Memo::new(rt, fn() { config.get() * 2 })

inspect(config_derived.get(), content="200")

// Changing the low-durability source does not cause config_derived to reverify
source.set(2)
inspect(config_derived.get(), content="200")
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

## License

Apache-2.0
