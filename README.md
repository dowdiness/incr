# incr

[![CI](https://github.com/dowdiness/incr/actions/workflows/ci.yml/badge.svg)](https://github.com/dowdiness/incr/actions/workflows/ci.yml)

`incr` is a MoonBit library for computations that need to stay fresh as their
inputs change. It records what each derived value depends on, verifies those
records on demand, and recomputes only the parts of the graph that need work.

Think editor state, language tooling, reactive models, build-like pipelines,
spreadsheet cells, or any system where "just recalculate everything" stops
being pleasant.

> **Start here, then go deeper:** this page is the repository front door. Before
> using the library seriously or changing its code, read the detailed library
> guide in [`incr/README.mbt.md`](incr/README.mbt.md). It contains installation,
> examples, the mental model, API guidance, and supported-target notes.

## What you will find here

- **The published library module:** [`incr/`](incr/)  
  Source for the `dowdiness/incr` package, plus the detailed README you should
  read next: [`incr/README.mbt.md`](incr/README.mbt.md).
- **Documentation:** [`docs/`](docs/README.md)  
  Getting started, concepts, cookbook patterns, API reference, architecture,
  design notes, decisions, and performance snapshots.
- **Examples and spikes:** [`examples/`](examples/)  
  Typed-spreadsheet examples, browser/CLI demos, and retained exploratory work
  that exercise the library from separate workspace modules.
- **Contributor guidance:** [`AGENTS.md`](AGENTS.md)  
  Repository conventions, validation commands, documentation rules, and agent
  workflow notes.

## See `incr` in action

Edit one cell. Watch only the necessary work happen.

The live typed spreadsheet turns `incr`'s dependency graph into something you
can touch: cell values are backed by MoonBit incremental computations, formulas
record the cells they read, and the trace panels show which formulas recomputed,
which values changed, and where work produced the same result. Try it at
[typed-spreadsheet.pages.dev](https://typed-spreadsheet.pages.dev), or run the
browser demo from
[`examples/typed_spreadsheet_rabbita_demo/`](examples/typed_spreadsheet_rabbita_demo/).

## The short version

Core `incr` programs usually combine:

- `Input[T]` for values you update directly.
- `Derived[T]` for memoized computations that automatically track reads.
- `DerivedMap[K, V]` for one cached derived value per semantic key.
- Backdating, durability, batching, cycle-safe reads, and optional push-reactive
  or relational layers when the problem needs them.

The detailed README explains when to use each mode and why `Derived` is the
right default starting point.

## Workspace commands

Run these from the repository root:

```bash
moon check
moon test
moon fmt
moon info
```

For release validation of the published package, use the module directory:

```bash
moon -C incr publish --dry-run
```

## Useful next links

- Detailed library README: [`incr/README.mbt.md`](incr/README.mbt.md)
- Documentation index: [`docs/README.md`](docs/README.md)
- Getting started: [`docs/getting-started.mbt.md`](docs/getting-started.mbt.md)
- Core concepts: [`docs/concepts.mbt.md`](docs/concepts.mbt.md)
- API reference: [`docs/api-reference.mbt.md`](docs/api-reference.mbt.md)
- Changelog: [`CHANGELOG.md`](CHANGELOG.md)

## License

Apache-2.0
