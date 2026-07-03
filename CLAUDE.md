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
moon test incr/cells/derived_test.mbt                           # Run tests in a specific file
moon test incr/cells/derived_test.mbt -i 0                      # Run a single test by index
moon test incr/tests                                            # Run integration tests only
moon check docs/target_api_examples.mbt.md                  # Check literate target API examples
moon test docs/target_api_examples.mbt.md                   # Run checked docs examples
moon bench          # Run benchmarks (incr/tests/bench_test.mbt)
```

## Architecture

The canonical package map is [docs/architecture.md](docs/architecture.md).
The repository root is a MoonBit workspace. The publishable `dowdiness/incr`
module lives under `incr/`; checked documentation examples live under `docs/`;
demos and spikes live under `examples/` as standalone workspace modules. The tree below is
a working orientation for Claude Code.

```
incr/                           (module `dowdiness/incr`)
├── moon.pkg                    (root facade — imports types + cells)
├── incr.mbt                    (transparent pub type aliases for target facades + compatibility handles)
├── traits.mbt                  (RuntimeContext/Freshness/InputFieldOwner plus compatibility traits and helpers)
│
├── types/                      (pure value types, zero dependencies)
│   ├── revision.mbt            (Revision, Durability, DURABILITY_COUNT)
│   ├── cell_id.mbt             (CellId + Hash impl)
│   └── cycle_error.mbt         (CycleError + pure-value format_path)
│
├── cells/                      (coordinator + handles + lifecycle; algorithms live in internal/kernel)
│   ├── moon.pkg                (imports @shared, @pull, @push, @datalog, @kernel)
│   ├── runtime.mbt             (Runtime struct + Runtime::new + thin @kernel delegators for propagate_changes, publish_cell_changes, dispose_cell, gc, add/remove_gc_root, advance_revision; RevisionManager + Tracker trait impls; accumulator fields + commit_hooks/accumulator_commit_hook fields — 686 LOC)
│   ├── pull_memo_lifecycle.mbt (CellLifecycle for MemoData)
│   ├── pull_lifecycle.mbt      (CellLifecycle for PullSignalData)
│   ├── push_lifecycle.mbt      (CellLifecycle for PushReactiveData, PushEffectData)
│   ├── datalog_lifecycle.mbt   (CellLifecycle for Relation/Functional/Rule)
│   ├── eager_derived.mbt       (Reactive[T] compatibility handle; SoA moved to internal/push)
│   ├── push_effect.mbt         (Effect handle; SoA moved to internal/push)
│   ├── push_propagate.mbt      (Runtime::push_propagate_from wrapper + recompute_level wrapper)
│   ├── datalog_relation.mbt    (Relation[T] handle; SoA moved to internal/datalog)
│   ├── datalog_map_relation.mbt (FunctionalRelation[K, V] compatibility handle + MapRelation[K, V] target facade)
│   ├── datalog_rule.mbt        (Runtime::new_rule + helpers; RuleData moved)
│   ├── datalog_fixpoint.mbt    (Runtime::fixpoint wrapper — body in kernel)
│   ├── verify.mbt              (Runtime::pull_verify wrapper — body in kernel)
│   ├── batch.mbt               (Runtime::batch/batch_result + frame/rollback + Runtime::commit_batch 1-line wrapper — commit_batch body in kernel)
│   ├── subscriber_diff.mbt     (Runtime::diff_and_update_subscribers wrapper for wbtests)
│   ├── input.mbt, derived.mbt  (Signal[T] and Memo[T] compatibility handles)
│   ├── reachable_derived.mbt   (HybridMemo[T] compatibility handle)
│   ├── input_field.mbt         (TrackedCell[T] compatibility handle)
│   ├── derived_map.mbt         (MemoMap[K, V] compatibility handle)
│   ├── target_facade.mbt       (Input, InputField, Derived, ReachableDerived, EagerDerived, DerivedMap target facades)
│   ├── memo_commit_phase.mbt   (priv MemoCommitPhase trait — commit-path extension point dispatched from memo_force_recompute; lives in cells/ not kernel/ because methods take Runtime)
│   ├── accumulator_commit_hook.mbt (AccumulatorCommitHook — first MemoCommitPhase impl; owns per-recompute snapshot/restore/finalize state previously inline in accumulator.mbt)
│   ├── scope.mbt, tracking.mbt, introspection.mbt, kernel_using.mbt
│   ├── cell.mbt, cell_ops.mbt  (local CellLifecycle trait + using re-exports)
│   ├── internal/               (engine sub-packages, MoonBit `internal` visibility)
│   │   ├── shared/             (CellOps, HasCellMeta, Committable, CellMeta, CellRef, SlotSnapshot)
│   │   ├── pull/               (PullSignalData, MemoData)
│   │   ├── push/               (PushReactiveData, PushEffectData)
│   │   ├── datalog/            (RelationData, FunctionalRelationData, RuleData)
│   │   └── kernel/             (graph mechanics + coordinator primitives — R1 complete 2026-04-25)
│   │       ├── state.mbt           (RuntimeCore + state sub-structs + PropagationPhase + ActiveQuery + runtime-id helpers + enter/leave_phase)
│   │       ├── dispatch.mbt        (validate_cell*, is_cell_disposed, cell_id_*, get_changed_at/durability/subscribers, add/remove_subscriber, is_live_subscriber, propagate_liveness)
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
│
├── tests/                      (integration tests — exercises the full @incr public API)
│   ├── moon.pkg                (imports dowdiness/incr for test)
│   ├── integration_test.mbt    (end-to-end graph scenarios)
│   ├── fanout_test.mbt         (wide fanout stress tests)
│   ├── traits_test.mbt         (Database, Readable, and helper constructor tests)
│   ├── tracked_struct_test.mbt (TrackedCell, Trackable, and gc_tracked tests)
│   ├── reachable_derived_test.mbt (HybridMemo / ReachableDerived public API integration tests)
│   ├── subscriber_test.mbt     (subscriber link integration tests)
│   └── bench_test.mbt          (microbenchmarks — run with moon bench)
│
docs/                           (workspace-root checked docs module)
├── moon.mod                    (imports dowdiness/incr)
├── moon.pkg                    (imports dowdiness/incr for literate tests)
├── target_api_examples.mbt.md
└── pkg.generated.mbti
```

The root package re-exports all public types via transparent `pub type` aliases
in `incr.mbt`, so downstream users see a unified `@incr` API with no awareness
of the internal package structure.

Current public API direction: target facade names are preferred in docs and new
examples (`Input`, `Derived`, `ReachableDerived`, `DerivedMap`, `InputField`,
`EagerDerived`, `Watch`, `MapRelation`, `RuntimeContext`, `Freshness`,
`InputFieldOwner`). Compatibility names (`Signal`, `Memo`, `HybridMemo`,
`MemoMap`, `TrackedCell`, `Reactive`, `Observer`, `FunctionalRelation`,
`Database`, `Readable`, `Trackable`) remain available and should still be used
for behavior with no target facade yet, especially accumulator and low-level
memo/introspection recipes.

For deep internals (verification algorithm, type erasure, SoA storage, push propagation, data flow), see [docs/design/internals.md](docs/design/internals.md).

### Key Facts

- `incr/cells/moon.pkg` suppresses warning 15 (`unused_mut`) because some `mut` fields on `MemoData`/`PullSignalData` are only written in whitebox test compilation, not source-only compilation
- The `incr/cells/` package imports `moonbitlang/core/hashset` and `moonbitlang/core/hashmap` as external dependencies
- `incr/cells/internal/{shared,pull,push,datalog,kernel}/` use MoonBit's `internal` package feature. External consumers cannot import them. `scripts/check-engine-isolation.sh` enforces four invariants (R1 Stage 5, 2026-04-25): no cross-engine sibling imports; `shared` is the leaf; no back-edges from any internal package to `cells/`; kernel is one-way (engines/shared cannot import kernel — only `incr/cells/*.mbt` may). Kernel owns graph-mechanics algorithms + coordinator primitives.
- Cross-module workspace contracts are enforced by `scripts/check-workspace-boundaries.sh` (#343, CI job "Check architecture boundaries"): non-library workspace members (`docs/`, `examples/*`) import only the `dowdiness/incr` root facade (never `/cells`, `/types`, or deeper), and their `dowdiness/incr@X` pins must equal the version in `incr/moon.mod`.

## Documentation

**Main docs:** [docs/](docs/)

- **For users:** [getting-started.mbt.md](docs/getting-started.mbt.md), [concepts.mbt.md](docs/concepts.mbt.md), [api-reference.mbt.md](docs/api-reference.mbt.md), [cookbook.mbt.md](docs/cookbook.mbt.md)
- **For contributors:** [design/internals.md](docs/design/internals.md) (deep internals), [roadmap.md](docs/roadmap.md), [todo.md](docs/todo.md), [design/api-design-guidelines.md](docs/design/api-design-guidelines.md)
- **Archive:** `docs/archive/` — completed plans and stale documents. Do not search here unless you need historical context.

**Documentation rules:**
- Architecture docs = principles only, never reference specific types/fields/lines. Link to files instead.
- Plans = implementation details (struct defs, code examples, file paths). Archived on completion.
- Performance docs = dated snapshots. New measurements go in new files, old ones are not updated.
- Code is the source of truth — if a doc and the code disagree, the doc is wrong.
- High-value target API examples should be checked in `.mbt.md` files or
  ` ```mbt check` blocks. The primary public docs are literate `.mbt.md`
  files, with high-value behavior pinned by companion checked examples. See
  `docs/todo.md` for the remaining lower-priority ADR/design/performance
  snippet migration work.

When contributing, read [docs/design/internals.md](docs/design/internals.md) before modifying core algorithm files like `incr/cells/verify.mbt` or `incr/cells/derived.mbt`.
