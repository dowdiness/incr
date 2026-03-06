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

### Phase 4 — Remaining

- **Accumulator queries**: Support Salsa-style accumulators that collect values across the dependency graph
- **Interning**: Deduplicate structurally equal values to reduce memory and speed up equality checks
- **Garbage collection**: Reclaim cells that are no longer reachable from any live memo or signal. Requires subscriber links for reference tracking.
- ~~**Datalog primitives**: `Relation[T]` (set with delta tracking), `Rule` (derives facts), `Runtime::fixpoint()` (semi-naive evaluation)~~ ✓ Implemented
- **Runtime modularization**: Investigate decomposing Runtime god object into composable subsystems per propagation mode (pull, push, hybrid, datalog) to improve maintainability without breaking encapsulation

## Phase 5 — Ecosystem

- **Persistent caching**: Serialize the dependency graph and cached values to disk for cross-session incrementality
- **Parallel computation**: Explore concurrent memo evaluation if MoonBit gains thread or async support
