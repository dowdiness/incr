# Changelog

All notable changes to `dowdiness/incr` are documented in this file.

## Unreleased

### Deprecated

- Deprecated the standalone `dowdiness/incr/pipeline` traits (`Sourceable`, `Parseable`, `Checkable`, `Executable`). They were an early stringly-typed sketch with no production consumers; application build pipelines should define local `Source`, `Parser`, `ImportResolver`, `Checker`, and `Transformer` traits over concrete domain types.

### Documentation

- Added build-oriented trait-boundary and internal rebuild-boundary proposal specs.
- Removed the `CalcPipeline` fixture from integration tests so deprecated pipeline traits are no longer exercised by the test suite.

## [0.6.0] - 2026-05-24

### Added

- Added target facade handles `Input`, `Derived`, `ReachableDerived`, `EagerDerived`, and `DerivedMap` with constructor syntax and direct read methods. Compatibility handles remain source-compatible in this slice.
- Added `MapRelation[K, V]` as the target facade over `FunctionalRelation[K, V]`.
- Added `Watch[T]` for long-lived target-facade outside reads that preserve cycle errors as `Result` values.
- Added `InputField[T]`, `Freshness`, `InputFieldOwner`, and `add_input_fields(scope, owner)` target surfaces for field-level inputs; `Freshness` is implemented for `Input`, `InputField`, `Derived`, and `ReachableDerived`.
- Added target-facade constructors on `Scope` and `RuntimeContext` helper constructors for `Input`, `InputField`, `Derived`, `ReachableDerived`, `EagerDerived`, and `DerivedMap`.
- Added `Scope::add_watch(watch)` for scope-owned `Watch` lifetimes.
- Added `Derived::id` and `Derived::observe` forwarders on the public facade, lifting the underlying `HybridMemo` accessors so callers can inspect a derived cell's identity and acquire keep-alive `Observer`s without reaching through the wrapped handle.

### Changed

- Internal package-private read helpers on `Memo`, `HybridMemo`, and `Reactive` were renamed from `get_untracked` to `read_permissive` to clarify that they bypass the strict tracked-context guard but may still record a dependency when called with an active tracking frame. Deprecated package-private aliases keep the old names available during migration. No public API change.

### Deprecated

- `Runtime::read`, `Runtime::read_hybrid`, and `Runtime::read_reactive` are now legacy compatibility helpers; target facade `read*` and `watch()` methods are the preferred API.

### Documentation

- Updated the API reference, cookbook, architecture overview, docs index, and checked literate examples for the target-facade migration; added the public API naming ADR, the facade read-semantics design spec, and the rename/Phase 3a soak-window plans. `docs/design/internals.md` now positions `incr` in the Build Systems à la Carte design space.

## [0.5.2] - 2026-05-20

### Added

- **Memo event listener API.** `Runtime::on_memo_event` and `Runtime::clear_memo_event_listener` expose pull-memo recompute events via public `MemoEvent` payloads (`EnteringCompute`, `Completed`, `Aborted`). Listener mutation is rejected while an operation is in flight.

### Fixed

- **Disallow listener mutation during callback dispatch.** The memo listener API now prevents registering, removing, or clearing listeners while memo event callbacks are in progress, avoiding re-entrancy hazards and maintaining event order guarantees.

### Performance

- **Lazy memo commit allocation.** `ActiveQuery` accumulator fields are now allocated lazily, reducing push fanout overhead in hot paths. In current benchmarks this appears as roughly a 16% improvement in active push fanout throughput.

### Documentation

- **Information structure rebuilt against source code as primary truth.** `README.md` rewritten as a truthful entry point using the modern `fn MyApp::MyApp()` constructor and `app.runtime().read(memo)` for outside-graph reads. `AGENTS.md` expanded into a canonical contributor doc (build commands, doc rules, comment rules, pre-PR checklist, v0.9.2 deprecation status).
- **New `docs/architecture.md`** — principles-only architecture overview covering the package responsibility map, the four execution modes (pull / push / hybrid / Datalog), key types, invariants, and extension points. Linked from `docs/README.md`.
- **`docs/api-reference.mbt.md` softened** from "complete reference" to "common APIs" (the `.mbti` files are authoritative). Removed a documented method that did not exist (`HybridMemo::get_result`). Added entries for `Signal::peek`, `TrackedCell::peek`, `MemoMap::get_tracked`, `add_tracked`, and `Runtime::read*`. Tightened bound documentation on `MemoMap::new` / `create_memo_map`.
- **`docs/concepts.mbt.md` / `docs/cookbook.mbt.md`** swept for top-level `memo.get()` patterns — rewritten to use `rt.read(memo)` / `rt.read_hybrid(h)` where the example reads from outside the graph. `CycleDetected(_, _)` pattern updated to the actual 3-field variant `CycleDetected(cell, path, labels)`. The `gc_tracked` example replaced with `add_tracked(scope, t)`.
- **`HybridMemo` model correction.** The previous docs described it as receiving "dirty flags eagerly via push propagation". Source has always said otherwise: `HybridMemo` uses the same lazy revision-based verification as `Memo`, and "hybrid" refers to *reachability* (it participates in `push_reachable_count` so downstream observers keep upstream cells alive across `gc()`), not invalidation. Fixed in `traits.mbt`, `docs/architecture.md`, `docs/api-reference.mbt.md`, `docs/concepts.mbt.md`, `docs/design/internals.md`, and `docs/roadmap.md`.
- **Drift-catch test.** `tests/quickstart_test.mbt` instantiates the README's Database pattern end to end; future divergence between the README idiom and the actual compiled API will break this test.

### Changed

- **MoonBit v0.9.2 migration.** Updated stdlib calls: `@hashmap.new()` → `@hashmap.HashMap([])`, `@hashset.new()` → `@hashset.HashSet([])`, `@priority_queue.new()` → `@priority_queue.PriorityQueue([])`, `Ref::new(x)` → `Ref(x)`. Test snapshots using container `Show` impls (Option, Array, Map) migrated from `inspect` → `debug_inspect` since v0.9.2 deprecates `Show` on containers for debug output.
- **Constructor declarations modernized.** The in-struct `fn new(..)` declaration is deprecated in v0.9.2 in favour of a separated toplevel `fn Type::Type(..)`. Library types — `Runtime`, `Signal`, `Memo`, `HybridMemo`, `MemoMap`, `TrackedCell`, `Relation`, `FunctionalRelation`, plus internal `ActiveQuery` and `BatchFrame` — now declare an explicit `Type::Type` constructor alias that delegates to the existing `Type::new` body. Both forms remain in the public surface: `Type(args)` / `Type::Type(args)` constructor sugar and `Type::new(args)` direct calls.
- **Tightened type bounds** to match the new stdlib constructor signatures:
  - `MemoMap::new` / `create_memo_map`: `K : Hash + Eq` (was unconstrained `K`)
  - `InternTable::new`: `T : Hash + Eq` (was unconstrained `T`)

  These bounds were already required by every key-observing operation (`get`, `contains`, `intern`, `set`). Constructing an empty container and only using non-key-observing methods (e.g. `length`, `clear`, `len`) was technically possible without the bound and is now rejected at type-check time. No working caller relied on this path within the repository. Classified as a minor-bump tightening under the same "no external consumers yet" policy as the `.get()` tracked-context change in 0.5.0.

### Deprecated

- `gc_tracked(rt, tracked)` — was already a no-op; now carries a `#deprecated` attribute pointing to `add_tracked(scope, tracked)` for lifecycle management. Source-compatible.

## [0.5.1] - 2026-04-26

### Changed

- **Internal: kernel package split (R1).** Graph-mechanics algorithms and coordinator primitives moved out of `cells/` into `cells/internal/kernel/{state,dispatch,cycle,subscriber_diff,tracking,verify,push_propagate,fixpoint,propagate,batch,dispose,gc}.mbt`. Public API unchanged. Engine-isolation invariants enforced by `scripts/check-engine-isolation.sh` (no cross-engine sibling imports; `internal/shared` is the leaf; no back-edges from internal packages to `cells/`; kernel is one-way — engines and shared cannot import kernel).

### Performance

- Benchmark baseline methodology updated: `wasm-gc --release` is now the authoritative target, with JS cross-checks for web consumers. Added fixpoint benches and a `Runtime::new()` allocation bench (0.11 µs full-Runtime, anchoring the modal-split investigation deferral). `memo_restore_on_abort` O(n²) characteristic confirmed at large batch counts; not actionable at realistic accumulator counts (1–2 accumulators per memo).

## [0.5.0] - 2026-04-21

### Added

- **Accumulator API** — side-channel collector enabling aggregation patterns without full recomputation; per-memo `push_revised_at` drives incremental invalidation (#42)
- **`Observer[T]`** — explicit, GC-safe downstream attachment. `.observe()` methods on `Memo`, `HybridMemo`, and `Reactive` return an `Observer[T]` that keeps the subscription chain alive and is required for any persistent downstream attachment once `Runtime::gc()` is in use
- **`Runtime::gc()`** — mark-and-sweep that reclaims SoA slots of cells no longer reachable from roots
- **`Runtime::read()`** convenience methods — the recommended entry point for tracked reads from query context
- **`Scope`** — hierarchical disposal container with scoped cell constructors (`signal`, `memo`, `hybrid_memo`, `reactive`, `effect`), `add_tracked` for `Trackable` structs, `add_observer` for automatic `Observer` cleanup, and `create_scope` for nested child scopes
- **Manual `dispose()` + `is_disposed()`** for all cell types — `Signal`, `Memo`, `HybridMemo`, `Reactive`, `Effect`, `TrackedCell`, `Relation`, `FunctionalRelation`, `Rule` — with SoA free-list slot reuse
- **Push suspension** — `PushReactiveData::on_observe` / `on_unobserve` activate and suspend reactive nodes at 0↔1 observer transitions, avoiding wasted work on unobserved subgraphs
- **`InternTable`** — grow-only interning table providing stable identity for string / symbol keys across revisions (#34)
- **`Signal::peek()` and `TrackedCell::peek()`** — untracked reads that do not record dependencies
- **`get_untracked()`** on `Memo`, `HybridMemo`, `Reactive` — reads from outside the dependency graph without aborting
- **`MemoMap::get_tracked`** — misuse guardrail that aborts when called outside a tracked context (#41)
- **`MemoMap::clear`** — reset all entries for structural-rebuild sweeps
- **`MemoMap::sweep`** — remove disposed entries after `gc()`
- **`HasChangedAt` + `BackdateEq` traits**; `Memo::new_memo` and `new_no_backdate` constructors for custom equality semantics (#25)
- **`CellLifecycle` trait** — uniform dispose dispatch replacing ad-hoc per-kind dispose methods
- **`CellOps::gc_role` + `gc_dependencies`** — GC categorization for all cell types (via new `GcRole` enum)

### Changed

- **`.get()` is now restricted to tracked context.** Calling `memo.get()` / `hybrid.get()` / `reactive.get()` outside a tracked computation aborts with a migration hint. Previously the same call returned the value *without recording a dependency* — a silent, latently-unsound no-op on tracking. This is classified as a minor-bump behavior change under a "latently-unsound-is-not-API" policy while the library has no external consumers; future similar changes will bump major once external users exist. Migration recipes:
  - From outside the graph → `rt.read(&cell)` (tracked read via Runtime) or `cell.observe()` for persistent attachment
  - When you need the value without tracking → `cell.peek()` (`Signal` / `TrackedCell`) or `cell.get_untracked()` (`Memo` / `HybridMemo` / `Reactive`)
  - When you need cycle-safe handling → `.get_result()` / `.get_or()` / `.get_or_else()` remain callable from any context
- `CycleError` is now a pure-value type with no `Runtime` dependency, enabling use outside the `cells` package
- Internal SoA engine data moved to `cells/internal/{pull, push, datalog, shared}` packages — invisible to external consumers; the `@incr` public API is unchanged

### Fixed

- Preserve `push_revised_at` on aborted new-slot writes, preventing stale revision timestamps after transaction abort
- `dispose_cell` removes the `gc_root_counts` entry to prevent observer handle leaks after disposal
- `Scope`: clear arrays after dispose and validate `runtime_id` at registration to prevent use-after-free bugs
- Cross-runtime and fixpoint guards restored in `get_result_inner()`; `get_result()` remains callable from any context
- `MemoMap` updated to use `get_untracked()` for reads outside tracked context
- Disposed-dependency guards tightened across `Memo` / `HybridMemo` `get` paths

### Performance

- **`push_reachable_count`** — O(1) push-propagation gating; replaces a BFS traversal when checking for downstream push subscribers (#24)

## [0.4.1] - 2026-03-22

### Added
- **FunctionalRelation[K, V]** — key-value Datalog relation with delta tracking for value updates. Unlike `Relation[T]` (set semantics), `FunctionalRelation` maps each key to one value; updates produce deltas. Optional merge function resolves conflicts. (#21)

## [0.4.0] - 2026-03-22

### Added
- **Datalog primitives** — `Relation[T]`, `Rule`, `Runtime::fixpoint()` for semi-naive evaluation with staged deltas, delta iteration, and convergence detection (#18)
- **Push-mode cells** — `Reactive[T]` (eager recomputation) and `Effect` (eager side effects) with level-sorted BFS propagation (#14)
- **HybridMemo[T]** — push-dirty, pull-verify lazy cell combining eager invalidation with lazy verification (#15, #16)
- CellOps trait object dispatch for extensible cell types
- Committable trait for batch-aware cells
- Microbenchmarks for core operations

### Changed
- **BREAKING:** Package renamed from `dowdiness/incr/internal` to `dowdiness/incr/cells`
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

[Unreleased]: https://github.com/dowdiness/incr/compare/v0.5.2...HEAD
[0.5.2]: https://github.com/dowdiness/incr/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/dowdiness/incr/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/dowdiness/incr/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/dowdiness/incr/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/dowdiness/incr/compare/v0.3.3...v0.4.0
[0.3.3]: https://github.com/dowdiness/incr/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/dowdiness/incr/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/dowdiness/incr/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/dowdiness/incr/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/dowdiness/incr/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/dowdiness/incr/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/dowdiness/incr/releases/tag/v0.1.0
