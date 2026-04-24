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
├── cells/                      (coordinator + handles + lifecycle; algorithms live in internal/kernel)
│   ├── moon.pkg                (imports @shared, @pull, @push, @datalog, @kernel)
│   ├── runtime.mbt             (Runtime struct + Runtime::new + thin @kernel delegators for propagate_changes, publish_cell_changes, dispose_cell, gc, add/remove_gc_root, advance_revision; RevisionManager + Tracker trait impls; accumulator fields — 427 LOC)
│   ├── pull_memo_lifecycle.mbt (CellLifecycle for MemoData)
│   ├── pull_lifecycle.mbt      (CellLifecycle for PullSignalData)
│   ├── push_lifecycle.mbt      (CellLifecycle for PushReactiveData, PushEffectData)
│   ├── datalog_lifecycle.mbt   (CellLifecycle for Relation/Functional/Rule)
│   ├── push_reactive.mbt       (Reactive[T] handle; SoA moved to internal/push)
│   ├── push_effect.mbt         (Effect handle; SoA moved to internal/push)
│   ├── push_propagate.mbt      (Runtime::push_propagate_from wrapper + recompute_level wrapper)
│   ├── datalog_relation.mbt    (Relation[T] handle; SoA moved to internal/datalog)
│   ├── datalog_functional_relation.mbt
│   ├── datalog_rule.mbt        (Runtime::new_rule + helpers; RuleData moved)
│   ├── datalog_fixpoint.mbt    (Runtime::fixpoint wrapper — body in kernel)
│   ├── verify.mbt              (Runtime::pull_verify wrapper — body in kernel)
│   ├── batch.mbt               (Runtime::batch/batch_result + frame/rollback + Runtime::commit_batch 1-line wrapper — commit_batch body in kernel)
│   ├── subscriber_diff.mbt     (Runtime::diff_and_update_subscribers wrapper for wbtests)
│   ├── signal.mbt, memo.mbt    (Signal[T], Memo[T] handles)
│   ├── hybrid_memo.mbt         (HybridMemo[T] handle)
│   ├── tracked_cell.mbt        (TrackedCell[T] handle)
│   ├── memo_map.mbt            (MemoMap[K, V])
│   ├── scope.mbt, tracking.mbt, introspection.mbt, kernel_using.mbt
│   ├── cell.mbt, cell_ops.mbt  (local CellLifecycle trait + using re-exports)
│   ├── internal/               (engine sub-packages, MoonBit `internal` visibility)
│   │   ├── shared/             (CellOps, HasCellMeta, Committable, CellMeta, CellRef, SlotSnapshot)
│   │   ├── pull/               (PullSignalData, MemoData)
│   │   ├── push/               (PushReactiveData, PushEffectData)
│   │   ├── datalog/            (RelationData, FunctionalRelationData, RuleData)
│   │   └── kernel/             (graph mechanics — R1 Stages 2–4 shipped)
│   │       ├── state.mbt           (RuntimeCore + state sub-structs + PropagationPhase + ActiveQuery + runtime-id helpers + enter/leave_phase)
│   │       ├── dispatch.mbt        (validate_cell*, is_cell_disposed, cell_id_*, get_changed_at/durability/subscribers, add/remove_subscriber, push_contribution, collect_reachable_cells, adjust_push_reachable)
│   │       ├── cycle.mbt           (construct_cycle_error)
│   │       ├── subscriber_diff.mbt (diff_and_update_subscribers)
│   │       ├── tracking.mbt        (push/pop_tracking, record_dep, top_active_query, collect_tracking_path, collect_in_progress_path, check_cross_runtime)
│   │       ├── verify.mbt          (pull_verify + synthetic_accumulator_changed + PullVerifyFrame — takes slot_snapshots explicitly)
│   │       ├── push_propagate.mbt  (push_propagate_from + PushEntry + level helpers)
│   │       ├── fixpoint.mbt        (run_fixpoint)
│   │       ├── propagate.mbt       (advance_revision, fire_on_change, propagate_changes, publish_cell_changes)
│   │       ├── batch.mbt           (commit_batch — I4 callback-snapshot invariant lives here)
│   │       ├── dispose.mbt         (validate_cell_for_dispose, drop_gc_root, check_dispose_guard — pure-state dispose helpers)
│   │       └── gc.mbt              (gc, gc_sweep, mark_reachable, collect_gc_roots, add/remove_gc_root — gc_sweep/gc take dispose_fn callback)
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

For deep internals (verification algorithm, type erasure, SoA storage, push propagation, data flow), see [docs/design/internals.md](docs/design/internals.md).

### Key Facts

- `cells/moon.pkg` suppresses warning 15 (`unused_mut`) because some `mut` fields on `MemoData`/`PullSignalData` are only written in whitebox test compilation, not source-only compilation
- The `cells/` package imports `moonbitlang/core/hashset` and `moonbitlang/core/hashmap` as external dependencies
- `cells/internal/{shared,pull,push,datalog,kernel}/` use MoonBit's `internal` package feature. External consumers cannot import them. Engine packages (`pull`, `push`, `datalog`) must not import each other — enforced by `scripts/check-engine-isolation.sh`. `kernel/` owns graph-mechanics algorithms + coordinator primitives after R1 Stages 2–4. Stage 5 extends the isolation script to enforce kernel's one-way dependency direction.

## Documentation

**Main docs:** [docs/](docs/)

- **For users:** [getting-started.md](docs/getting-started.md), [concepts.md](docs/concepts.md), [api-reference.md](docs/api-reference.md), [cookbook.md](docs/cookbook.md)
- **For contributors:** [design/internals.md](docs/design/internals.md) (deep internals), [roadmap.md](docs/roadmap.md), [todo.md](docs/todo.md), [design/api-design-guidelines.md](docs/design/api-design-guidelines.md)
- **Archive:** `docs/archive/` — completed plans and stale documents. Do not search here unless you need historical context.

**Documentation rules:**
- Architecture docs = principles only, never reference specific types/fields/lines. Link to files instead.
- Plans = implementation details (struct defs, code examples, file paths). Archived on completion.
- Performance docs = dated snapshots. New measurements go in new files, old ones are not updated.
- Code is the source of truth — if a doc and the code disagree, the doc is wrong.

When contributing, read [docs/design/internals.md](docs/design/internals.md) before modifying core algorithm files like `cells/verify.mbt` or `cells/memo.mbt`.

