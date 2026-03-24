# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Salsa-inspired incremental recomputation library written in MoonBit. Provides automatic dependency tracking, memoization with backdating, and durability-based verification skipping.

## MoonBit Language Notes

- `pub` vs `pub(all)` visibility modifiers have different semantics — check current docs before using
- `._` syntax is deprecated, use `.0` for tuple access
- `try?` does not catch `abort` — use explicit error handling
- `?` operator is not always supported — use explicit match/error handling when it fails
- `ref` is a reserved keyword — do not use as variable/field names
- Blackbox tests cannot construct internal structs — use whitebox tests or expose constructors
- For cross-target builds, use per-file conditional compilation rather than `supported-targets` in moon.pkg.json

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

### Core Computation Model

The library implements Salsa's incremental computation pattern with eight cell types:

- **Signal[T]** (`cells/signal.mbt`) — Input cells with externally-set values. Support same-value optimization (skip revision bump if value unchanged) and durability levels (Low/Medium/High).
- **Memo[T]** (`cells/memo.mbt`) — Derived computations that lazily evaluate and cache results. Automatically track dependencies via the runtime's tracking stack. Implement **backdating**: when a recomputed value equals the previous value, `changed_at` is preserved, preventing unnecessary downstream recomputation.
- **HybridMemo[T]** (`cells/hybrid_memo.mbt`) — Hybrid push-pull memo. Receives push notifications eagerly via push propagation but verifies/recomputes lazily on `get()`. Fast path skips dep walk when `verified_at >= current_revision`.
- **Reactive[T]** (`cells/reactive.mbt`) — Push-mode derived cell. Recomputed eagerly during level-sorted push propagation when upstream cells change.
- **Effect** (`cells/effect.mbt`) — Terminal push-mode side-effect cell. Runs side effects eagerly; never read by other cells.
- **Relation[T]** (`cells/datalog_relation.mbt`) — Set-based Datalog relation with semi-naive delta tracking (`current`/`delta`/`staged_delta`). Used for monotone facts in fixpoint evaluation.
- **FunctionalRelation[K, V]** (`cells/datalog_functional_relation.mbt`) — Key-value Datalog relation with delta tracking. Unlike `Relation[T]`, maps each key to one value; updates produce deltas. Optional merge function resolves conflicts.
- **Runtime** (`cells/runtime.mbt`) — Central state: global revision counter, SoA arrays (`pull_signals`, `pull_memos`, `push_reactives`, `push_effects`, `relations`, `functional_relations`, `cell_index`, `cell_ops`), dependency tracking stack, per-durability revision tracking, push propagation engine, fixpoint engine, and batch state.

### Dependency Graph Internals

- **SoA storage** (`cells/cell_ref.mbt`, `cells/pull_signal.mbt`, `cells/pull_memo.mbt`, `cells/hybrid_memo.mbt`, `cells/reactive.mbt`, `cells/effect.mbt`, `cells/cell_ops.mbt`) — Cell metadata lives in parallel typed arrays on `Runtime`: `pull_signals : Array[PullSignalData]` (input cells), `pull_memos : Array[MemoData]` (unified storage for both pull-mode and hybrid-mode derived cells), `push_reactives : Array[PushReactiveData]` (push-mode derived cells), `push_effects : Array[PushEffectData]` (terminal side-effect cells), `cell_index : Array[CellRef]` (maps `CellId.id` → `PullSignal(idx)`, `PullMemo(idx)`, `HybridMemo(idx)`, `PushReactive(idx)`, `PushEffect(idx)`, `Relation(idx)`, `FunctionalRelation(idx)`, `Rule(idx)`, or `Disposed` for O(1) dispatch), and `cell_ops : Array[&CellOps]` (trait-object array for uniform read access — indexed by `CellId.id`). Both `PullMemo` and `HybridMemo` index into the same `pull_memos` array. All SoA data structs implement `CellOps`.
- **ActiveQuery** (`cells/tracking.mbt`) — Frame pushed onto `Runtime.tracking_stack` during memo computation. Collects dependencies (with HashSet-based O(1) deduplication) read via `Signal::get` or `Memo::get`.
- **Revision** / **Durability** (`types/revision.mbt`) — Monotonic revision counter bumped on input changes. Durability classifies input change frequency; derived cells inherit the minimum durability of their dependencies.
- **Verification** (`cells/verify.mbt`) — `pull_verify()` is the core algorithm. Dispatches directly on `cell_index`; signals are always fresh. For memos: checks the root durability shortcut first, then walks dependencies iteratively using an explicit `PullVerifyFrame` stack. Short-circuits on the first detected change (sets `dep_cursor` to end of dep list). If any dependency changed, calls the type-erased `compute` closure (enabling backdating). Green path marks `verified_at` without recomputation. Per-dep durability shortcuts skip traversal for individual stale deps.
- **CycleError** (`cells/cycle.mbt`) — Cycle detection error type. `CycleError::from_path(path, closing_id)` constructs a `CycleDetected` value from a collected path; `format_path(rt)` produces a human-readable chain string. The cycle path is built from the local `PullVerifyFrame` stack (traversal order).
- **Push propagation** (`cells/propagate.mbt`) — `push_propagate_from` does a level-sorted BFS from changed sources using a min-heap (`PushEntry` with negated levels). Notifies `HybridMemo` cells of upstream changes, recomputes `PushReactive` cells, and executes `Effect` cells. `propagate_level_change` recalculates topological levels when sources change. Only runs when `push_node_count > 0`.
- **CellOps / Committable** (`cells/cell_ops.mbt`) — `CellOps` is a 6-method trait providing uniform read access to any cell (`cell_id`, `changed_at`, `set_changed_at`, `subscribers`, `label`, `durability`); implemented by all five SoA data structs. `Committable` is a 3-method trait for batch-commit dispatch (`do_commit`, `cell_id`, `durability`); implemented only by `PullSignalData`. `Runtime.batch_pending : Array[&Committable]` stores trait-object references to pending signals, so `commit_batch` can call `do_commit()` without SoA lookup.
- **Traits** (`traits.mbt`) — `Database`, `Readable`, and `Trackable` public traits; `create_signal`, `create_memo`, `create_hybrid_memo`, `create_tracked_cell`, `batch`, and `gc_tracked` helper functions. Pipeline traits (`Sourceable`, `Parseable`, `Checkable`, `Executable`) live in `pipeline/pipeline_traits.mbt` and are marked experimental.

### Type Erasure

The `Runtime` holds cells of many different value types simultaneously. `MemoData` must be type-erased — it cannot be generic over `T`.

MoonBit has no trait objects (no `Box<dyn Trait>` equivalent), so the value type cannot be hidden behind a vtable. Instead, the bridge is a **captured closure**:

```
Memo[T]::new()
  ├── allocates cell_id
  ├── creates memo : Memo[T] = { compute, value: None, ... }
  ├── creates compute : () -> Result[Bool, CycleError]
  │     └── captures `memo` by reference (the full typed Memo[T])
  │         calls memo.recompute_inner() which reads/writes memo.value : T?
  │         returns only Bool (changed?) — runtime never sees T
  └── stores closure in MemoData (type-erased)
```

`pull_verify` calls `(memo.compute)()` and only receives a `Bool` or a `CycleError`. The typed value `T` never crosses the `MemoData` boundary.

**Consequence for contributors:** Do not attempt to:
- Move the cached value into `MemoData` (would require it to be generic or use `Any`)
- Make `Runtime` generic over a value type (Runtime holds cells of *many* different types simultaneously)
- Add a second type-erased closure that returns the value as a string or `Show` output directly from `MemoData` — if you need introspection, thread it through `CellInfo` (see `Runtime::cell_info`) which is populated by the typed layer

The `compute` and `commit_pending` closures follow the same pattern: capture the typed cell, perform typed operations, return only type-erased results (`Bool` or `Result[Bool, CycleError]`).

### Data Flow

1. `Signal::set()` bumps the global revision, records `changed_at` on the signal's `PullSignalData` (or defers to batch if inside `Runtime::batch()`), and triggers `push_propagate_from` if `push_node_count > 0`
2. Push propagation: BFS from changed signal through subscriber links; notifies `HybridMemo` cells, eagerly recomputes `Reactive` cells, and runs `Effect` cells (all level-sorted for glitch-free execution)
3. `Memo::get()` checks `verified_at` against current revision; if stale, calls `pull_verify()`
4. `HybridMemo::get()` fast path: if `verified_at >= current_revision`, returns cached value immediately; otherwise calls `pull_verify`
5. `pull_verify()` iteratively verifies dependencies using an explicit `PullVerifyFrame` stack, short-circuiting on the first change and recomputing only cells whose inputs actually changed
6. Backdating: if a Memo/HybridMemo recomputes to the same value, `changed_at` stays old, so downstream cells skip recomputation
7. Durability shortcut: if no input of a cell's durability level changed, verification is skipped entirely
8. Batch mode: `Runtime::batch(fn)` groups multiple signal updates into a single revision with two-phase commit and revert detection

### MoonBit Conventions

- Tests use `///|` doc-comment prefix followed by `test "name" { ... }` blocks
- Assertions use `inspect(expr, content="expected")` pattern
- Panic tests: `test "panic ..."` (name starting with `"panic "`) expects `abort()` to fire — the test runner marks it passed when the abort occurs
- Benchmarks use `test "name" (b : @bench.T) { b.bench(fn() { b.keep(expr) }) }` blocks; `b.keep()` prevents the optimizer from eliding pure computations
- Whitebox tests (`*_wbtest.mbt`): live in `cells/` alongside the private types they test; can access private fields and internal functions
- Unit tests (`*_test.mbt`): live in `cells/` alongside source; test the cells package API as a black-box consumer
- Integration tests: live in `tests/`; test the full `@incr` public API end-to-end across multiple scenarios
- The `cells/` package imports `moonbitlang/core/hashset` and `moonbitlang/core/hashmap` as external dependencies
- `cells/moon.pkg` suppresses warning 15 (`unused_mut`) because some `mut` fields on `MemoData`/`PullSignalData` are only written in whitebox test compilation, not source-only compilation
- Anonymous callbacks use arrow function syntax: `() => expr` (zero params, single expression), `() => { stmts }` (multi-statement), `x => expr` (one param), `(x, y) => expr` (multiple params). Empty bodies use `() => ()` — not `() => {}` which MoonBit parses as a map literal. Named functions (`pub fn`, `fn name(...)`) are unaffected.

## Documentation Hierarchy

### For Users
- **README.md** — Entry point: features, quick start, documentation index
- **docs/getting-started.md** — Step-by-step tutorial for new users (shows both Runtime and Database patterns)
- **docs/concepts.md** — Core concepts explained simply (Signals, Memos, Revisions, Durability, TrackedCell/Field-Level Tracking)
- **docs/api-reference.md** — Complete reference for all public types and methods
- **docs/cookbook.md** — Common patterns and recipes
- **docs/api-design-guidelines.md** — Design philosophy, best practices, planned improvements

### For Contributors
- **docs/design.md** — Deep technical internals: verification algorithm, backdating, durability, type erasure
- **CLAUDE.md** (this file) — Contributor and AI guidance: commands, architecture map, conventions
- **docs/roadmap.md** — Phased future direction (Phases 1–3 complete, Phase 4A–4C complete, remaining: Datalog primitives, GC, accumulators, interning)
- **docs/todo.md** — Concrete actionable tasks with checkboxes organized by priority
- **docs/comparison-with-alien-signals.md** — Analysis of alien-signals vs Salsa-style computation
- **docs/api-design-guidelines.md** — API design principles, patterns, and anti-patterns
- **docs/api-updates.md** — Summary of recent API documentation changes

When contributing, read [docs/design.md](docs/design.md) to understand the conceptual model (pull-based verification, backdating, durability shortcuts) before modifying core algorithm files like `cells/verify.mbt` or `cells/memo.mbt`.

## Code Review Standards

- Never dismiss a review request — always do a thorough line-by-line review even if changes seem minor
- Check for: integer overflow, zero/negative inputs, boundary validation, generation wrap-around
- Do not suggest deleting public API types (Id structs, etc.) as 'unused' — they may be needed by downstream consumers
- Verify method names match actual API before writing tests (e.g., check if it's `insert` vs `add_local_op`)

## Development Workflow

1. Make edits
2. `moon check` — Lint
3. `moon test` — Run tests
4. `moon test --update` — Update snapshots (if behavior changed)
5. `moon info` — Update `.mbti` interfaces
6. Check `git diff *.mbti` — Verify API changes
7. `moon fmt` — Format

## Git Workflow

- Always check if git is initialized before running git commands
- After rebase operations, verify files are in the correct directories
- When asked to 'commit remaining files', interpret generously even if phrasing is unclear
