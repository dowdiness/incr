# Roadmap

High-level future direction for the `incr` library, organized by phase. Each phase builds on the previous one. For a detailed explanation of the current architecture, see [design.md](design.md).

## Phase 1 — Error Handling ✓

- ~~**Cycle error recovery**: Replace `abort()` in cycle detection with a `CycleError` type that callers can handle gracefully~~ ✓ Implemented with `CycleError` suberror type
- ~~**Result-based APIs**: Offer `get_result()` variants on `Signal` and `Memo` that return `Result[T, CycleError]` instead of panicking~~ ✓ Implemented

## Phase 2 — API & Usability

- ~~**Batch updates**: Allow multiple `Signal::set` calls within a single revision bump to avoid redundant intermediate verifications~~ ✓ Implemented with two-phase signal values and revert detection

### Phase 2A: Introspection & Debugging ✓

- ~~**Introspection API**: Public methods to query the dependency graph~~ ✓ Implemented
  - Per-cell methods: `Signal::id()`, `Signal::durability()`, `Memo::dependencies()`, `Memo::changed_at()`, `Memo::verified_at()`
  - Runtime methods: `Runtime::cell_info(CellId)` returning structured `CellInfo` (with `label` field)
- ~~**Enhanced error diagnostics**: Include cycle path in `CycleError`~~ ✓ Implemented with `CycleDetected(CellId, Array[CellId])` and `format_path()`
- ~~**Debug output**: `Signal::debug()` and `Memo::debug()` methods~~ ✓ Implemented
- **Graph visualization**: Textual or DOT format dump of dependency graph

### Phase 2B: Observability ✓

- ~~**Per-cell change callbacks**~~ ✓ Implemented
  - `Signal::on_change(f : (T) -> Unit)`, `Memo::on_change(f : (T) -> Unit)`
  - `Signal::clear_on_change()`, `Memo::clear_on_change()`
  - Fires per-cell callbacks before `Runtime::fire_on_change()`
  - Stored on `CellMeta` via type-erased closures

### Phase 2C: Unified Constructors & Labels ✓

- ~~**Unified constructors with optional params**~~ ✓ Implemented (replaced builder pattern)
  - `Signal::new(rt, val, durability?=Low, label?=String)` replaces `Signal::new_with_durability`
  - `Memo::new(rt, f, label?=String)` with optional label
  - `create_signal(db, val, durability?=Low, label?=String)` replaces `create_signal_durable`
  - `create_memo(db, f, label?=String)` with optional label
- ~~**Labels**~~ ✓ Labels propagate through `CellMeta`, `CellInfo`, `format_path`, and debug output
- **Method chaining**: Fluent configuration for Runtime — deferred
- **Convenience helpers**: Shorter names for common patterns — deferred

### Phase 2D: Graceful Error Handling ✓

- ~~**Raised-error rollback in `Runtime::batch`**~~ ✓ Implemented
  - `Runtime::batch` accepts `f : () -> Unit raise?`; raised errors roll back all pending signal writes before re-raising (`abort()` is still unrecoverable)
  - `rollback_pending` closure added to `CellMeta` for per-signal rollback hooks
- ~~**`batch_result`**: Transactional batch returning `Result` instead of re-raising~~ ✓ Implemented
  - `Runtime::batch_result(f) -> Result[Unit, Error]` and `@incr.batch_result(db, f)` Database helper form
- ~~**Convenience reads**: `get_or` and `get_or_else` for cycle-safe reads without pattern matching~~ ✓ Implemented
  - `Memo::get_or(fallback : T) -> T`, `Memo::get_or_else(fallback : (CycleError) -> T) -> T`
  - `MemoMap::get_or`, `MemoMap::get_or_else` with identical semantics

## Phase 3 — Performance

- ~~**HashSet-based dependency deduplication**: Replace linear scan in `ActiveQuery::record` with a `HashSet` for O(1) dedup~~ ✓ Implemented
- ~~**Array-based cell storage**: Use `CellId` as a direct index into an array instead of a `HashMap` lookup~~ ✓ Implemented
- ~~**Iterative verification**: Convert recursive `maybe_changed_after` to iterative with explicit stack, then replaced by `pull_verify` in Phase 3F~~ ✓ Implemented
- ~~**Incremental dependency diffing**: When a memo recomputes, diff the new dependency list against the old one to skip durability rescans for unchanged deps~~ ✓ Implemented

### Phase 3B: Package Modularization ✓

- ~~**Sub-package split**: Reorganize the flat single-package library into four MoonBit sub-packages~~ ✓ Implemented
  - `dowdiness/incr/types` — pure value types (`Revision`, `Durability`, `CellId`) with zero dependencies
  - `dowdiness/incr/cells` — all engine code (`Signal`, `Memo`, `Runtime`, verification algorithm)
  - `dowdiness/incr/pipeline` — experimental pipeline traits, standalone with zero dependencies
  - Root facade re-exports all public types via `pub type` transparent aliases — zero breaking changes

### Phase 3C: Tracked Struct Support ✓

- ~~**`TrackedCell[T]`**: Field-level input cell wrapping `Signal[T]`~~ ✓ Implemented
  - Full Signal-equivalent API: `get`, `set`, `set_unconditional`, `id`, `durability`, `on_change`, `clear_on_change`, `is_up_to_date`, `as_signal`
  - Implements `Readable` trait; runtime sees only the inner Signal — zero changes to verification algorithm
- ~~**`Trackable` trait**: `cell_ids(Self) -> Array[CellId]` contract for structs with TrackedCell fields~~ ✓ Implemented
- ~~**`create_tracked_cell` helper**: Mirrors `create_signal` for Database-pattern usage~~ ✓ Implemented
- ~~**`gc_tracked` stub**: No-op call site for future Phase 4 GC integration~~ ✓ Implemented

### Phase 3D: Internal Quality Refactoring ✓

- ~~**Consolidate revision-bump logic**: `Runtime::advance_revision` and `Runtime::mark_input_changed` extracted~~ ✓ Implemented
- ~~**Invariant assertions**: Silent fallbacks in `finish_frame_changed` and `commit_batch` replaced with `abort`~~ ✓ Implemented
- ~~**Centralize cycle-path construction**: `CycleError::from_path(path, closing_id)` added~~ ✓ Implemented
- ~~**Idiomatic loops**: C-style index loops converted to `for .. in` where semantics allow~~ ✓ Implemented

### Phase 3E: Keyed Query Ergonomics ✓

- ~~**`MemoMap[K, V]`**: Minimal parameterized-query helper with one memo per key~~ ✓ Implemented
  - Lazy key instantiation: per-key memo created on first read
  - API: `new`, `get`, `get_result`, `contains`, `length`
- ~~**`create_memo_map` helper**: Database-style constructor for keyed memo maps~~ ✓ Implemented

### Phase 3F: SoA Storage Refactor ✓

- ~~**Structure-of-Arrays storage**: Replace `Array[CellMeta]` with three parallel typed arrays~~ ✓ Implemented
  - `pull_signals : Array[PullSignalData]`, `pull_memos : Array[PullMemoData]`, `cell_index : Array[CellRef]`
  - `CellRef` enum (`PullSignal(Int) | PullMemo(Int)`) for O(1) dispatch via `cell_index`
  - `CellMeta` and `CellKind` removed entirely
- ~~**SoA-native verification (`pull_verify`)**: Replace `maybe_changed_after` with a direct SoA-dispatch algorithm~~ ✓ Implemented
  - Explicit `PullVerifyFrame` stack; no recursion; same backdating and durability semantics
  - Root durability fast-path skips full dep walk when no relevant-durability input changed
  - Per-dep durability shortcuts for intermediate stale deps
  - Short-circuits dep traversal on first detected change (prevents stale dynamic-branch verification)
  - Cycle path collected from traversal-order stack frames (fixes storage-order bug in `collect_in_progress_path`)

## Phase 4 — Advanced Features

- ~~**Subscriber (reverse) links**: Add bidirectional edges so cells know their dependents~~ ✓ Implemented
  - `subscribers : HashSet[CellId]` on SoA data structs, maintained incrementally during dep diffing
  - `Runtime::dependents(CellId) -> Array[CellId]` introspection API
  - `subscribers` field added to `CellInfo`
  - Prerequisite for push-based invalidation, automatic cleanup, and the effect system

### Phase 4A: CellOps Trait ✓

- ~~**`CellOps` trait**: Uniform 6-method read interface for all cell types~~ ✓ Implemented
  - `cell_id`, `changed_at`, `set_changed_at`, `subscribers`, `label`, `durability`
  - `Runtime.cell_ops : Array[&CellOps]` trait-object array indexed by `CellId.id`
  - Implemented by `PullSignalData`, `PullMemoData`, `HybridMemoData`, `PushReactiveData`, `PushEffectData`
- ~~**`Committable` trait**: Batch-commit dispatch for signals~~ ✓ Implemented
  - `do_commit`, `cell_id`, `durability` methods
  - `Runtime.batch_pending : Array[&Committable]` replaces direct SoA lookup

### Phase 4B: Push-Reactive Cells ✓

- ~~**`Reactive[T]`**: Eager push-mode derived cell~~ ✓ Implemented
  - Recomputed eagerly during push propagation (level-sorted priority queue for glitch-free execution)
  - SoA entry `PushReactiveData` with `dirty`, `level`, `sources`, `subscribers` fields
- ~~**`Effect`**: Terminal push-mode side-effect cell~~ ✓ Implemented
  - Runs side effects eagerly when upstream changes; never read by other cells
  - SoA entry `PushEffectData`
- ~~**Push propagation engine** (`cells/propagate.mbt`)~~ ✓ Implemented
  - `push_propagate_from`: level-sorted BFS from changed sources
  - `propagate_level_change`: recalculates topological levels when sources change

### Phase 4C: HybridMemo ✓

- ~~**`HybridMemo[T]`**: Hybrid push-pull memo~~ ✓ Implemented
  - Receives dirty flags eagerly via push propagation; verifies/recomputes lazily on `get()`
  - Fast path: `not(dirty) && verified_at >= current_revision` → return cached, no dep walk
  - SoA entry `HybridMemoData` with `dirty : Bool` flag
  - Public API: `HybridMemo::new`, `get`, `get_result`, `id`, `is_up_to_date`
  - `create_hybrid_memo` Database helper; `Readable` impl

### Phase 4D: Datalog Primitives ✓

- ~~**`Relation[T]`**: Set with delta tracking for semi-naive fixpoint~~ ✓ Implemented
  - `insert`, `contains`, `iter`, `delta_iter` with staged delta for fixpoint iterations
- ~~**`Rule`**: Derives new facts from input relations~~ ✓ Implemented
  - `Runtime::new_rule(input_relations, output_relations, apply_delta)`
- ~~**`Runtime::fixpoint()`**: Semi-naive evaluation until no new facts derived~~ ✓ Implemented
  - Drain → apply rules → promote staged → repeat until stable

### Phase 4E: Salsa-Style Query API (partially deferred — 2026-03-28)

The following features build toward a Salsa-style query API where users write normal functions that are automatically memoized with incremental invalidation. Each step builds on the previous one. See [semantic-interning.md](semantic-interning.md) for the interning design exploration.

**Recommended next step:** Add a simple type system to the lambda calculus parser to create a real Boundary ③ (CST → Typed AST). Building the use case first validates API shapes before committing to them — the accumulator and interning designs are sound in the abstract but may need adjustment once a concrete type-checker drives them.

1. **Semantic interning (`InternTable[T]`)** — Generic interning table. Maps `T : Hash + Eq` values to stable `InternId` integers. Enables O(1) equality for Datalog facts, stable `MemoMap` keys across revisions, and efficient Memo backdating on rich domain types. Standalone (no Runtime dependency). Design: [semantic-interning.md](semantic-interning.md).

   **Simplification (2026-03-28):** Start with `InternId { index: Int }` only — no generation counter. The table is grow-only initially (no slot reuse), making the generation counter vestigial until GC/slot-reuse is implemented. Add `generation: Int` when implementing GC.

2. **Tracked structs** — No new library code needed. `TrackedCell`, `Trackable`, and `MemoMap` already provide all required infrastructure. Work is demonstrating the pattern via an integration test: `InternId` as MemoMap key + `TrackedCell` fields for field-level granularity.

3. **Accumulators** — **Deferred until Boundary ③ exists.** Side-channel value collection during query computation (e.g., diagnostics without threading through return types). Deferred because: (a) no concrete use case yet, (b) key design questions unresolved — type erasure in a non-generic Runtime, transitive collection requiring a second dependency graph, backdating of `Array[T]` equality, and invalidation when only accumulated values change. See [todo.md](todo.md) for the full list of open questions.

4. **Multi-key MemoMap (optional ergonomics)** — `MemoMap2[K1, K2, V]`, `MemoMap3[K1, K2, K3, V]` as sugar for multi-argument queries. Low priority because tuple keys `MemoMap[(K1, K2), V]` already work.

### Phase 4F: Dispose / GC ✓

- ~~**Manual dispose**: Signal, Memo, HybridMemo, Reactive, Effect dispose with slot reuse~~ ✓ PR #28
- ~~**Scope**: Hierarchical cell ownership with bulk disposal~~ ✓ PR #29
- ~~**Composed traits**: CellOps + CellLifecycle for uniform dispose/gc dispatch~~ ✓ PR #30
- ~~**Observer + gc()**: Observer[T] keep-alive handle, mark-and-sweep gc(), gc_root_counts~~ ✓ PR #31
- ~~**Push suspension**: on_observe/on_unobserve for PushReactive, Scope::add_observer, MemoMap::sweep~~ ✓ PR #32

### Phase 4 — Remaining

- **Layer 5: API boundary**: Restrict `memo.get()`, `hybrid_memo.get()`, `reactive.get()` to tracked context only. Add `signal.peek()`. Migrate tests/benchmarks to `rt.read()` or observers.
- **Recursive suspension**: Auto-suspend when `push_reachable_count` drops to 0 on unobserved cells (deferred from Layer 4b — gc() handles cleanup for now).
- **Runtime modularization**: Investigate decomposing Runtime god object into composable subsystems per propagation mode (pull, push, hybrid, datalog) to improve maintainability without breaking encapsulation

## Phase 5 — Ecosystem

- **Persistent caching**: Serialize the dependency graph and cached values to disk for cross-session incrementality. Prerequisite: stable `InternId` across revisions (Phase 4E).
- **Parallel computation**: Explore concurrent memo evaluation if MoonBit gains thread or async support
