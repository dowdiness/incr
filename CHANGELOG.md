# Changelog

All notable changes to `dowdiness/incr` are documented in this file.

## [Unreleased]

### Added
- **Datalog primitives** — `Relation[T]`, `Rule`, `Runtime::fixpoint()` for semi-naive evaluation with staged deltas, delta iteration, and convergence detection (#18)
- **Push-mode cells** — `Reactive[T]` (eager recomputation) and `Effect` (eager side effects) with level-sorted BFS propagation (#14)
- **HybridMemo[T]** — push-dirty, pull-verify lazy cell combining eager invalidation with lazy verification (#15, #16)
- CellOps trait object dispatch for extensible cell types
- Committable trait for batch-aware cells
- Microbenchmarks for core operations

### Changed
- **SoA storage** — replaced per-cell structs with struct-of-arrays layout (`PullSignalData`, `MemoData`) for cache-friendly access and type-erased dispatch (#11)
- **Runtime modularization** — split Runtime into `CoreState`, `PullState`, `PushState`, `DatalogState` sub-structs (#19)
- **MemoData unification** — merged `PullMemoData` and `HybridMemoData` into single `MemoData` struct
- **Cells simplification** — extracted `validate_cell`, `CellMeta`, batch/tracking/introspection into dedicated files (#20)
- Iterative `pull_verify` with explicit `VerifyFrame` stack (prevents stack overflow on deep graphs)
- Consolidated ID wrappers into `types/` package

### Fixed
- Fire `on_change` for HybridMemo and unify `verified_at` comparison
- Dirty check in `pull_verify_hybrid` fast-path
- Abort on disposed-dependency in verify paths
- Separate hybrid memos from push `node_count` gate

## [0.3.3] - 2026-03-01

### Added
- `Runtime::dependents()` introspection API for querying subscriber links (#9)
- Subscriber field in `CellInfo`
- Graceful batch rollback and non-panicking read APIs (`batch_result`, `get_or`, `get_or_else`) (#10)

### Changed
- Renamed `IncrDb` trait to `Database`
- Renamed `internal/` package to `cells/` for `pub using` re-exports

### Fixed
- Rollback failed nested batches before rethrow
- Fire global `on_change` exactly once after batch callbacks set more signals
- Abort on cross-runtime dependency reads instead of returning stale values

## [0.3.2] - 2026-02-24

### Added
- `MemoMap[K, V]` — keyed memoization with one memo per key
- Subscriber links maintained during memo recompute

## [0.3.1] - 2026-02-24

### Added
- `TrackedCell[T]` — field-level input cells for fine-grained dependency isolation
- `Trackable` trait and `gc_tracked` for struct-level tracking
- `Readable` trait implemented for `TrackedCell`

### Changed
- Unified constructors with optional `label~` and `durability~` params
- Arrow function syntax for all anonymous callbacks
- Reorganized tests — unit tests to `cells/`, integration tests to `tests/`
- Modularized into four sub-packages: `types/`, `cells/`, `pipeline/`, root facade

## [0.3.0] - 2026-02-04

### Added
- Trait-based type-safe API (`Database` trait pattern)
- `Runtime::on_change` global callback
- Per-cell `Signal::on_change` and `Memo::on_change` callbacks
- `Debug` trait for `Signal`, `Memo`, `CellId`
- `CellInfo` introspection with `Runtime::cell_info()`
- `CellId` and `Revision` public types
- `label` field on all cells

### Changed
- Dependency diff in `force_recompute` to skip unnecessary durability rescans

### Fixed
- `Memo::is_up_to_date` returns `false` for uncomputed memos

## [0.2.1] - 2026-02-03

### Added
- `CycleError` type with dependency path tracking
- `Memo::get_result()` for non-panicking cycle handling

## [0.2.0] - 2026-02-03

### Changed
- Made internal types private, improved public API surface
- Applied alien-signals-inspired optimizations

### Fixed
- Correctness issues in iterative verification and batch commit

## [0.1.0] - 2026-02-02

Initial release.

### Added
- `Signal[T]` — input cells with same-value optimization
- `Memo[T]` — derived computations with automatic dependency tracking
- Pull-based lazy verification with dependency walk
- Backdating — unchanged recomputed values preserve their old revision
- Durability levels (Low, Medium, High) for verification skipping
- Batch updates with atomic multi-signal commits
- Cycle detection

[Unreleased]: https://github.com/dowdiness/incr/compare/v0.3.3...HEAD
[0.3.3]: https://github.com/dowdiness/incr/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/dowdiness/incr/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/dowdiness/incr/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/dowdiness/incr/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/dowdiness/incr/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/dowdiness/incr/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/dowdiness/incr/releases/tag/v0.1.0
