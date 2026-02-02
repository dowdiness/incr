# incr

A Salsa-inspired incremental recomputation library for [MoonBit](https://www.moonbitlang.com/).

## Features

- **Signal[T]** — Input cells with same-value optimization and durability levels
- **Memo[T]** — Derived computations with automatic dependency tracking and memoization
- **Backdating** — Unchanged recomputed values preserve their old revision, preventing unnecessary downstream recomputation
- **Durability** — Classify inputs by change frequency (Low/Medium/High) to skip verification of stable subgraphs
- **Cycle detection** — Aborts on direct or mutual recursion between memos

## Usage

```moonbit
let rt = Runtime::new()

// Create input signals
let x = Signal::new(rt, 10)
let y = Signal::new(rt, 20)

// Create derived computations
let sum = Memo::new(rt, fn() { x.get() + y.get() })

inspect(sum.get(), content="30")

// Update an input — downstream memos recompute on next access
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
let config = Signal::new_with_durability(rt, 100, High)
let source = Signal::new(rt, 1)
let config_derived = Memo::new(rt, fn() { config.get() * 2 })

inspect(config_derived.get(), content="200")

// Changing the low-durability source does not cause config_derived to reverify
source.set(2)
inspect(config_derived.get(), content="200")
```

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the high-level future direction and [TODO.md](TODO.md) for concrete next tasks.

## Development

```bash
moon check    # Type-check
moon build    # Build
moon test     # Run all tests
```

## License

Apache-2.0
