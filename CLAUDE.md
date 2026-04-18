# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Salsa-inspired incremental recomputation library written in MoonBit. Provides automatic dependency tracking, memoization with backdating, and durability-based verification skipping.

@~/.claude/moonbit-base.md

## Commands

```bash
moon check          # Type-check without building
moon build          # Build the library
moon test           # Run all tests across all packages
moon test -p dowdiness/incr/cells -f memo_test.mbt           # Run tests in a specific file
moon test -p dowdiness/incr/cells -f memo_test.mbt -i 0      # Run a single test by index
moon test -p dowdiness/incr/tests                               # Run integration tests only
moon bench          # Run benchmarks (tests/bench_test.mbt)
```

## Architecture

This library is organized into four MoonBit sub-packages:

```
dowdiness/incr/
├── moon.pkg                    (root facade — imports types + cells + pipeline)
├── incr.mbt                    (pub type re-exports for all public types)
├── traits.mbt                  (Database, Readable, Trackable traits; create_signal, create_memo, create_hybrid_memo, create_tracked_cell, batch, gc_tracked helpers)
│
├── types/                      (pure value types, zero dependencies)
│   ├── revision.mbt            (Revision, Durability, DURABILITY_COUNT)
│   ├── cell_id.mbt             (CellId + Hash impl)
│   └── cycle_error.mbt         (CycleError + pure-value format_path)
│
├── cells/                      (coordinator + handles + algorithms + lifecycle)
│   ├── moon.pkg                (imports @shared, @pull, @push, @datalog)
│   ├── runtime.mbt             (Runtime + sub-states)
│   ├── cycle.mbt               (private from_path helper — captures labels from Runtime)
│   ├── pull_memo_lifecycle.mbt (CellLifecycle for MemoData)
│   ├── pull_lifecycle.mbt      (CellLifecycle for PullSignalData)
│   ├── push_lifecycle.mbt      (CellLifecycle for PushReactiveData, PushEffectData)
│   ├── datalog_lifecycle.mbt   (CellLifecycle for Relation/Functional/Rule)
│   ├── push_reactive.mbt       (Reactive[T] handle; SoA moved to internal/push)
│   ├── push_effect.mbt         (Effect handle; SoA moved to internal/push)
│   ├── push_propagate.mbt      (push algorithm + PushEntry)
│   ├── datalog_relation.mbt    (Relation[T] handle; SoA moved to internal/datalog)
│   ├── datalog_functional_relation.mbt
│   ├── datalog_rule.mbt        (Runtime::new_rule + helpers; RuleData moved)
│   ├── datalog_fixpoint.mbt    (fixpoint algorithm)
│   ├── verify.mbt              (pull verification algorithm + PullVerifyFrame)
│   ├── batch.mbt               (batch algorithm)
│   ├── signal.mbt, memo.mbt    (Signal[T], Memo[T] handles)
│   ├── hybrid_memo.mbt         (HybridMemo[T] handle)
│   ├── tracked_cell.mbt        (TrackedCell[T] handle)
│   ├── memo_map.mbt            (MemoMap[K, V])
│   ├── scope.mbt, tracking.mbt, introspection.mbt
│   ├── cell.mbt, cell_ops.mbt  (local CellLifecycle trait + using re-exports)
│   ├── internal/               (engine sub-packages, MoonBit `internal` visibility)
│   │   ├── shared/             (CellOps, HasCellMeta, Committable, CellMeta, CellRef)
│   │   ├── pull/               (PullSignalData, MemoData)
│   │   ├── push/               (PushReactiveData, PushEffectData)
│   │   └── datalog/            (RelationData, FunctionalRelationData, RuleData)
│   └── *_test.mbt, *_wbtest.mbt
│
├── pipeline/                   (experimental pipeline traits, zero dependencies)
│   └── pipeline_traits.mbt     (Sourceable, Parseable, Checkable, Executable)
│
└── tests/                      (integration tests — exercises the full @incr public API)
    ├── moon.pkg                (imports dowdiness/incr and dowdiness/incr/pipeline for test)
    ├── integration_test.mbt    (end-to-end graph scenarios)
    ├── fanout_test.mbt         (wide fanout stress tests)
    ├── traits_test.mbt         (Database, Readable, and pipeline trait tests)
    ├── tracked_struct_test.mbt (TrackedCell, Trackable, and gc_tracked tests)
    ├── hybrid_test.mbt         (HybridMemo public API integration tests)
    ├── subscriber_test.mbt     (subscriber link integration tests)
    └── bench_test.mbt          (microbenchmarks — run with moon bench)
```

The root package re-exports all public types via `pub type` transparent aliases in `incr.mbt`, so downstream users see a unified `@incr` API with no awareness of the internal package structure.

For deep internals (verification algorithm, type erasure, SoA storage, push propagation, data flow), see [docs/design.md](docs/design.md).

### Key Facts

- `cells/moon.pkg` suppresses warning 15 (`unused_mut`) because some `mut` fields on `MemoData`/`PullSignalData` are only written in whitebox test compilation, not source-only compilation
- The `cells/` package imports `moonbitlang/core/hashset` and `moonbitlang/core/hashmap` as external dependencies
- `cells/internal/{shared,pull,push,datalog}/` use MoonBit's `internal` package feature. External consumers cannot import them. Engine packages (`pull`, `push`, `datalog`) must not import each other — enforced by `scripts/check-engine-isolation.sh`.

## Documentation

**Main docs:** [docs/](docs/)

- **For users:** [getting-started.md](docs/getting-started.md), [concepts.md](docs/concepts.md), [api-reference.md](docs/api-reference.md), [cookbook.md](docs/cookbook.md)
- **For contributors:** [design.md](docs/design.md) (deep internals), [roadmap.md](docs/roadmap.md), [todo.md](docs/todo.md), [api-design-guidelines.md](docs/api-design-guidelines.md)
- **Archive:** `docs/archive/` — completed plans and stale documents. Do not search here unless you need historical context.

**Documentation rules:**
- Architecture docs = principles only, never reference specific types/fields/lines. Link to files instead.
- Plans = implementation details (struct defs, code examples, file paths). Archived on completion.
- Performance docs = dated snapshots. New measurements go in new files, old ones are not updated.
- Code is the source of truth — if a doc and the code disagree, the doc is wrong.

When contributing, read [docs/design.md](docs/design.md) before modifying core algorithm files like `cells/verify.mbt` or `cells/memo.mbt`.

