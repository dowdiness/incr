# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Salsa-inspired incremental recomputation library written in MoonBit. Provides automatic dependency tracking, memoization with backdating, and durability-based verification skipping.

@~/.claude/moonbit-base.md

## Commands

```bash
moon check          # Type-check without building
moon build          # Build the library
moon test           # Run all tests (273 total across all packages)
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
│   └── cell_id.mbt             (CellId + Hash impl)
│
├── cells/                      (all engine implementation + unit tests)
│   ├── cell.mbt                (using @incr_types declaration; CellMeta/CellKind removed)
│   ├── cell_ref.mbt            (CellRef enum: PullSignal | PullMemo | PushReactive | PushEffect | HybridMemo | Relation | FunctionalRelation | Rule | Disposed)
│   ├── cell_ops.mbt            (CellOps trait — 6-method read interface; Committable trait — batch commit interface)
│   │
│   │   # Pull mode (lazy verification)
│   ├── pull_signal.mbt         (PullSignalData — SoA entry for input cells; CellOps + Committable impls)
│   ├── pull_memo.mbt           (MemoData — unified SoA entry for pull and hybrid derived cells; CellOps impl)
│   ├── signal.mbt              (Signal[T])
│   ├── memo.mbt                (Memo[T])
│   ├── verify.mbt              (pull_verify, PullVerifyFrame, clear_verify_stack)
│   │
│   │   # Push mode (eager propagation)
│   ├── push_reactive.mbt       (PushReactiveData — SoA entry for push-mode derived cells)
│   ├── push_effect.mbt         (PushEffectData — SoA entry for push-mode side-effect cells)
│   ├── push_propagate.mbt      (push_propagate_from, propagate_level_change — level-sorted push propagation)
│   │
│   │   # Hybrid mode (push staleness + pull verification)
│   ├── hybrid_memo.mbt         (HybridMemo[T] — hybrid push-pull memo; uses unified MemoData)
│   │
│   │   # Datalog mode (fixpoint evaluation)
│   ├── datalog_relation.mbt    (Relation[T] — set with delta tracking; RelationData SoA entry)
│   ├── datalog_rule.mbt        (RuleData — derives new facts; Runtime::new_rule)
│   ├── datalog_fixpoint.mbt    (Runtime::fixpoint — semi-naive fixpoint evaluation)
│   │
│   │   # Shared
│   ├── cycle.mbt               (CycleError)
│   ├── tracking.mbt            (ActiveQuery)
│   ├── runtime.mbt             (Runtime, CellInfo)
│   ├── tracked_cell.mbt        (TrackedCell[T])
│   ├── memo_map.mbt            (MemoMap[K, V] — keyed memoization)
│   ├── scope.mbt               (Scope — hierarchical cell ownership with bulk disposal)
│   ├── *_test.mbt              (unit tests — black-box tests of the cells package)
│   └── *_wbtest.mbt            (whitebox tests — co-located for private field access)
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

