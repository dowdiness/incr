# Changelog

All notable changes to `dowdiness/incr` are documented in this file.

## [Unreleased]

### Added

- Made the two runtime-global hooks composable so multiple observers can share one `Runtime` (#210). New additive APIs `Runtime::add_on_change_listener` and `Runtime::add_derived_event_listener` register listeners that coexist with each other and with the existing singletons, each returning a `ListenerId` for `Runtime::remove_on_change_listener` / `Runtime::remove_derived_event_listener` (idempotent removal). On-change listeners fire in registration order; derived-event listeners fire event-major (every listener per event, in registration order). On-change registration is unguarded (snapshot-before-fire makes mid-callback mutation safe); derived-event registration keeps the existing idle guard (the hook buffers events). The singleton APIs (`set_on_change`/`clear_on_change`, `on_derived_event`/`clear_derived_event_listener`) are unchanged and source-compatible — they now drive a reserved slot in the same registry. Added the public `ListenerId` handle.

### Examples

These changes are in `examples/` workspace members, not the published `dowdiness/incr` library.

- The `examples/incr_tea` browser renderer now separates DOM detachment from component disposal (#209). `BrowserRenderer::detach` removes a root's DOM subtree but keeps its `Program` scope and watch alive (re-mountable with preserved state), while `BrowserRenderer::destroy` disposes the program when the component instance is gone. `BrowserRenderer::dispose` removes the renderer's two stored `ListenerId`s — the `on_change` flush trigger and the derived-event view-recompute counter it registered via #210 — and destroys every mounted root. A `requestAnimationFrame` queued before `dispose` is a no-op, `mount` after `dispose` is rejected, and the browser demo gains child detach / re-mount / destroy / dispose controls.
- `examples/incr_tea` exposes an experimental reusable in-repo UI surface (#268): `Program`, cacheable `Html`, `Attrs`, pure event descriptors and payload ids, `BrowserRenderer` roots/stats, and post-render `Cmd::after_flush` / `Cmd::focus_element_by_id` commands for DOM work that must run after a renderer flush.
- `examples/incr_tea` adds Eq-safe spreadsheet event descriptors (#270) for submit, focus/blur, and double-click, plus renderer-boundary keyboard actions for `preventDefault` / `stopPropagation` without closure-valued `Html` handlers.
- `examples/incr_tea` adds a measurement-first activation-islands benchmark (#255) to the adjacent-framework mounted matrix: an editor/sidebar/inspector-shaped workspace compares collapsed, hidden-mounted, and visible update costs before any visibility/idle-driven `Watch` activation prototype.
- `examples/incr_tea` adds a first DOM-preserving inactive-root prototype (#255): `BrowserRenderer::deactivate` keeps a mounted root's DOM, `Program`, and view `Watch` alive while scheduled frames skip its watched-view read; `BrowserRenderer::activate` performs a catch-up flush. Renderer stats now expose inactive skipped flushes and activation catch-up flushes, the browser demo exposes deactivate/activate child-root controls, and `npm run bench:ui-compare-dom` includes an `incr_tea`-only inactive workspace root suite.

## [0.9.0] - 2026-06-09

### Added

- Added `AcceptedDerived[V, E]`, a success-gated derived authoring primitive: a fallible candidate `Result[V, E]` only advances the *accepted* state on a differing `Ok(v)`, while `Err(e)` retains the prior accepted value and still reports the error on the *current* channel. Surfaces `current`/`accepted`/`snapshot` (outside-graph, carrying `ReadError`), `accepted_get`/`accepted_get_or_abort` (inside-graph, gated by accepted-value changes), `accepted_changed_at`, and `watch_accepted`, plus the `AcceptedSnapshot[V, E]` view and `AcceptStatus` enum. Construct via `AcceptedDerived(rt, compute, label?)`, `AcceptedDerived::from_candidate`, or `Scope::accepted_derived`. See [the design spec](docs/design/specs/2026-06-05-committed-derived.md).
- Added a `BackdateEq` acceptance tier for `AcceptedDerived`: `AcceptedDerived::accepted_memo` and `Scope::accepted_memo` accept candidate value types that are *not* `Eq` but carry a `Revision` (so they implement `BackdateEq`), gating acceptance by revision identity instead of structural equality — mirroring `Memo::new` vs `Memo::new_memo`. `E : Eq` is retained. As part of this, `AcceptedDerived::from_candidate`'s `E` bound was relaxed from `Eq` to unconstrained (it wraps a pre-built candidate and never compares `E`). The no-`Eq` / no-backdate acceptance tier remains deferred.

### Fixed

- Corrected `push_reachable_count` maintenance for diamond dependency topologies. A push-reachable derived (e.g. a watched `AcceptedDerived` fold) could silently stop recomputing after a candidate dropped one arm of a dynamic diamond dependency: the previous deduplicated reachability "mass" model added and removed counts asymmetrically across diamonds, so dropping a shared dependency could leave a cell's reachable count above zero and freeze its eager updates. Push-reachability is now maintained as an incremental count of each cell's direct *live* subscribers, propagated only across `0 ↔ 1` liveness boundaries, making diamond add/remove symmetric. (#233)

### Examples

These changes are in `examples/` workspace members, not the published `dowdiness/incr` library.

- Added `examples/incr_tea`, an experimental `incr`-native TEA skeleton with scope-owned model fields, batched message dispatch, a minimal Rabbita-style `Cmd` scheduler, and watched tracked views.
- Typed spreadsheet snapshots now expose `last_dynamic_dependencies`, the logical cells read during the last completed cell evaluation.
- Typed spreadsheet cells now distinguish comparable worksheet facts from opaque formula evaluators: same-value inputs and same-AST formulas are semantic no-ops, closure formulas can opt into no-op detection with a fingerprint, and force paths remain available for deliberate revalidation.
- Typed spreadsheet formulas and cell snapshots now expose dependency-shape metadata (`Applicative`, `Selective`, `Dynamic`) for explaining static references versus active dynamic dependencies without changing engine APIs.
- Typed spreadsheet worksheets now expose `Worksheet::formula_ast` with structured `FormulaAstQueryError` results for reading AST-backed formulas without conflating missing, deleted, input, and opaque closure-backed cells.

## [0.8.0] - 2026-06-03

### Added

- `RuntimeId`: a nominal runtime-identity value type (`Eq` / `Hash` / `Show`). Obtain it from `Runtime::id()` to ask "are these two runtimes the same?" without allocating a probe cell, or from `CellId::runtime_id` / `AccumulatorId::runtime_id`. It is a debug / introspection identity, not a stable application key.
- `Runtime::id() -> RuntimeId` — direct runtime-identity accessor.
- `Input::id`, `ReachableDerived::id`, `EagerDerived::id` — `id() -> CellId` forwarders, completing single-cell identity exposure across the target facades (it was previously only on `Derived`, `InputField`, `MapRelation`). Keyed `DerivedMap` deliberately remains without `id()`.

### Changed

- **Breaking:** `CellId::runtime_id` and `AccumulatorId::runtime_id` are now `RuntimeId` instead of `Int`. Code that compared these against a raw `Int` must compare against a `RuntimeId` (`cell.id().runtime_id == rt.id()`); `RuntimeId == RuntimeId` comparisons and `to_string()` formatting are unchanged.
- Renamed the public derived-recompute event API to `Derived*` naming: the enum `MemoEvent` → `DerivedEvent` and its payload structs `MemoEnteringEvent` / `MemoCompletedEvent` / `MemoAbortedEvent` → `DerivedEnteringEvent` / `DerivedCompletedEvent` / `DerivedAbortedEvent`; the runtime methods `Runtime::on_memo_event` / `Runtime::clear_memo_event_listener` → `Runtime::on_derived_event` / `Runtime::clear_derived_event_listener`. The enum variant names (`EnteringCompute` / `Completed` / `Aborted`) are unchanged, so existing `match` arms keep compiling.
- Moved the typed spreadsheet boundary and tests out of the publishable `dowdiness/incr` module into the standalone `examples/typed_spreadsheet` workspace module.

### Deprecated

- `MemoEvent`, `MemoEnteringEvent`, `MemoCompletedEvent`, `MemoAbortedEvent`, `Runtime::on_memo_event`, and `Runtime::clear_memo_event_listener` are retained as deprecated aliases of their `Derived*` replacements and are scheduled for removal in a future major release.

### Fixed

- Closed a cross-runtime read guard hole on the direct read paths (`DerivedMap` / `MemoMap` reads and internal permissive reads). Reading a cell that belongs to one `Runtime` from inside an active computation on a *different* `Runtime` could previously succeed silently and corrupt the active runtime's tracking state; it now aborts, matching the strict `Derived` / `.get()` read paths. (#174)

### Documentation

- Clarified that the typed spreadsheet example is runtime-checked: formula installation validates worksheet boundaries, while operator and declared-result type mismatches surface as `CellResult::TypeError` on read.

## [0.7.1] - 2026-06-01

### Changed

- Reorganized the repository as a MoonBit workspace: the `dowdiness/incr` library module now lives under `incr/`, while typed-spreadsheet demos and retained spikes live under `examples/` as standalone workspace modules.

### Documentation

- Expanded the root README into a friendlier workspace landing page that explicitly points readers to the detailed library README.
- Refreshed ADR and plan references for the workspace layout so source paths use the `incr/` module prefix.

## [0.7.0] - 2026-06-01

### Added

- Added `ReadError` (`Cycle` / `Disposed`) and re-exported it from the root package so public read APIs can report disposed-cell failures separately from dependency cycles.
- Added `Derived::fallible` and `DerivedMap::fallible` for caching domain failures as `Result` values instead of raising graph/runtime failures.
- Added target-facade lifecycle and introspection helpers for long-lived editors: `Scope::add_watch`, `Derived::changed_at`, `Derived::is_disposed`, and `Runtime::gc_root_count`.
- Added target-facade accumulator reads on `Derived`: `accumulated`, `accumulated_or_abort`, and `accumulated_peek`.
- Added `Runtime::record_batch_rollback` for batch-aware extension code that owns mutable state outside ordinary input cells.
- Added `dowdiness/incr/typed_spreadsheet` with `Worksheet`, typed `CellValue` / `CellType`, formula AST (`Formula`), dependency snapshots, and `Worksheet::trace`.
- Added `scripts/migrate-to-target-facades.py`, a dry-run-by-default helper for moving consumer code from compatibility handles (`Memo`, `HybridMemo`, `MemoMap`) to target facades (`Derived`, `ReachableDerived`, `DerivedMap`). It applies mechanically safe rewrites with `--apply`, skips files that still need manual choices, and reports context-sensitive read sites for manual migration.
- Added `dowdiness/incr/examples/typed_spreadsheet_demo`, a thin demo operation runner that applies typed spreadsheet operations and returns outcome, trace, and before/after cell snapshots, including a batched runner for trace-correct atomic demo steps.
- Added `dowdiness/incr/examples/typed_spreadsheet_cli_demo`, an executable typed spreadsheet scenario that prints a fixed operation sequence with outcomes, trace buckets, and before/after snapshots in text or JSON.
- Added `dowdiness/incr/examples/typed_spreadsheet_rabbita_demo`, a browser demo that renders the shared typed spreadsheet scenario with Rabbita, including trace buckets, an A1/B1 grid, before/after snapshots, and a schema-versioned ViewModel JSON export.

### Changed

- **Breaking:** Changed `Derived`, `DerivedMap`, `ReachableDerived`, and `Watch` read APIs from `Result[..., CycleError]` to `Result[..., ReadError]`. `DerivedMap::read_or_else` and `Memo::accumulated*` now use `ReadError` as well.
- Changed the typed spreadsheet Rabbita demo from a fixed trace viewer into a small editable four-cell sheet while keeping the fixed scenario JSON export available for non-DOM consumers.

### Fixed

- Fixed Datalog relation publication so fixpoint runs publish relation cells only when net contents changed.
- Fixed `Runtime::dependents` to soft-fail on disposed cell IDs instead of indexing disposed metadata.
- Fixed accumulator read APIs so disposed-cell failures are preserved as `ReadError` rather than collapsed into cycle-only results.
- Fixed typed spreadsheet rollback, deletion, and formula-dependency paths so aborted batches and recreated cells restore dependency state correctly.
- Fixed typed spreadsheet worksheet slots so live inputs and formulas remain readable after `Runtime::gc()`.

### Deprecated

- Deprecated the standalone `dowdiness/incr/pipeline` traits (`Sourceable`, `Parseable`, `Checkable`, `Executable`). They were an early stringly-typed sketch with no production consumers; application build pipelines should define local `Source`, `Parser`, `ImportResolver`, `Checker`, and `Transformer` traits over concrete domain types.

### Performance

- Graduated the measured static `Derived` fast path as a package-private implementation path; no new public static-derived API is exposed in this release.
- Added DSL-shaped authoring pipeline benchmarks and graph-editor recompute path benchmarks, including durable edit, sparse inspector, viewport, and live-drag measurements for wasm-gc and JS.
- Cached typed spreadsheet grid snapshots in the Rabbita demo to reduce repeated view-model allocation during UI updates.

### Documentation

- Added a Phase 3a migration guide for moving from `Memo` / `HybridMemo` / `MemoMap` directly to `Derived` / `ReachableDerived` / `DerivedMap`, skipping same-receiver bridge methods on the compatibility handles.
- Added build-oriented trait-boundary and internal rebuild-boundary proposal specs.
- Added the honest read-error ownership spec, the ReachableDerived differentiate-or-collapse ADR resolution, the static-derived public-surface ADR, and target-facade authoring pipeline guidance.
- Removed the `CalcPipeline` fixture from integration tests so deprecated pipeline traits are no longer exercised by the test suite.

## [0.6.0] - 2026-05-24

### Added

- Added target facade handles `Input`, `Derived`, `ReachableDerived`, `EagerDerived`, and `DerivedMap` with constructor syntax and direct read methods. Compatibility handles remain source-compatible in this slice.
- Added `MapRelation[K, V]` as the target facade over `FunctionalRelation[K, V]`.
- Added `Watch[T]` for long-lived target-facade outside reads that preserve cycle errors as `Result` values.
- Added `InputField[T]`, `Freshness`, `InputFieldOwner`, and `add_input_fields(scope, owner)` target surfaces for field-level inputs; `Freshness` is implemented for `Input`, `InputField`, `Derived`, and `ReachableDerived`.
- Added target-facade constructors on `Scope` and `RuntimeContext` helper constructors for `Input`, `InputField`, `Derived`, `ReachableDerived`, `EagerDerived`, and `DerivedMap`.
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

[Unreleased]: https://github.com/dowdiness/incr/compare/v0.7.1...HEAD
[0.7.1]: https://github.com/dowdiness/incr/compare/4302e80...v0.7.1
[0.7.0]: https://github.com/dowdiness/incr/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/dowdiness/incr/compare/v0.5.2...v0.6.0
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
