# incr

[![CI](https://github.com/dowdiness/incr/actions/workflows/ci.yml/badge.svg)](https://github.com/dowdiness/incr/actions/workflows/ci.yml)

`incr` is a MoonBit library for computations that must stay fresh as their
inputs change. It records what each derived value reads, verifies those records
on demand, and recomputes only what changed — use it where "recalculate
everything" is too expensive: editor state, language tooling, reactive models,
spreadsheet cells, build-like pipelines.

This page is the repository front door. The library guide —
[`incr/README.mbt.md`](incr/README.mbt.md) — has installation, a quick-start
example, the mental model, and the mode-selection table. Read it before using
the library seriously.

## Core API in one paragraph

Write to `Input[T]`, compute with `Derived[T]` (memoized, auto-tracked
dependencies), and use `DerivedMap[K, V]` when you need one cached value per
key. Start with `Derived`; reach for the push-reactive (`EagerDerived`,
`Effect`), hybrid (`ReachableDerived`), or relational (`Relation`,
`MapRelation`) layers only when the library guide's
["Which mode should I use?"](incr/README.mbt.md) table says so. Backdating,
durability, batching, and cycle-safe reads come with the pull engine by
default.

## Repository layout

| You want to... | Go to |
|---|---|
| Use the published `dowdiness/incr` package | [`incr/`](incr/) + [`incr/README.mbt.md`](incr/README.mbt.md) |
| Learn the model step by step | [`docs/getting-started.mbt.md`](docs/getting-started.mbt.md), then [`docs/concepts.mbt.md`](docs/concepts.mbt.md) |
| Look up a type, method, or pattern | [`docs/api-reference.mbt.md`](docs/api-reference.mbt.md), [`docs/cookbook.mbt.md`](docs/cookbook.mbt.md) |
| Browse all docs (architecture, decisions, performance) | [`docs/README.md`](docs/README.md) |
| See runnable demos and spikes | [`examples/`](examples/README.md) |
| Contribute or run validation commands | [`AGENTS.md`](AGENTS.md) |
| Track released changes | [`CHANGELOG.md`](CHANGELOG.md) |

## Live demo

Edit one cell of the [typed spreadsheet](https://typed-spreadsheet.pages.dev)
and watch only the necessary work happen: formulas record the cells they read,
and the trace panels show which formulas recomputed, which values changed, and
where recomputation produced the same result (backdating). Source:
[`examples/typed_spreadsheet_rabbita_demo/`](examples/typed_spreadsheet_rabbita_demo/).

## Workspace commands

Run from the repository root:

```bash
moon check    # type-check; run after every edit
moon test     # full workspace test suite
moon fmt      # format
moon info     # regenerate pkg.generated.mbti interfaces
```

Release validation for the published package:

```bash
moon -C incr publish --dry-run
```

## License

Apache-2.0
