# TODO

Concrete, actionable tasks for the `incr` library.

## Error Handling

- [x] Define a `CycleError` type and return it instead of calling `abort()` in verification
- [x] Add `Signal::get_result()` and `Memo::get_result()` that propagate `CycleError`
- [x] Ensure failed `get_result()` calls don't record dependencies (prevents spurious cycles)

## Performance

- [x] Use `HashSet` for deduplication in `ActiveQuery::record` — O(1) per dependency
- [x] Replace `HashMap[CellId, CellMeta]` in `Runtime` with `Array[CellMeta?]` indexed by `CellId.id`, then further migrated to SoA layout
- [x] Convert recursive `maybe_changed_after` to iterative with explicit stack (prevents stack overflow on deep graphs)
- [x] Diff old vs. new dependency lists in `Memo::force_recompute` instead of full replacement
- [x] Explore push-pull hybrid invalidation (requires subscriber/reverse links) — implemented as `HybridMemo`

## API Improvements

- [x] Add `Runtime::batch(fn)` that defers revision bump until the closure completes
- [x] Add two-phase signal values with revert detection in batch mode
- [x] Roll back pending batch writes when batch closure raises (graceful error path)
- [x] `Signal::set_unconditional(value)` already exists — always bumps the revision

### Introspection API (Phase 2A - High Priority)

- [x] Add `Signal::id(self) -> CellId`
- [x] Add `Signal::durability(self) -> Durability`
- [x] Add `Memo::dependencies(self) -> Array[CellId]`
- [x] Add `Memo::changed_at(self) -> Revision`
- [x] Add `Memo::verified_at(self) -> Revision`
- [x] Add `Runtime::cell_info(self, CellId) -> CellInfo?` struct
- [x] Define `CellInfo` struct with all cell metadata
- [x] Add `Signal::debug(self) -> String` for formatted output
- [x] Add `Memo::debug(self) -> String` for formatted output

### Error Diagnostics (Phase 2A - High Priority)

- [x] Change `CycleError` to include cycle path: `CycleDetected(CellId, Array[CellId])`
- [x] Add `CycleError::path(self) -> Array[CellId]`
- [x] Add `CycleError::format_path(self, Runtime) -> String` for human-readable output
- [x] Update cycle detection in `cells/verify.mbt` to track path during traversal

### Per-Cell Callbacks (Phase 2B - High Priority)

- [x] Add `on_change : (() -> Unit)?` field to `CellMeta` (or type-erased callback)
- [x] Add `Signal::on_change(self, f : (T) -> Unit) -> Unit`
- [x] Add `Memo::on_change(self, f : (T) -> Unit) -> Unit`
- [x] Add `Signal::clear_on_change(self) -> Unit`
- [x] Add `Memo::clear_on_change(self) -> Unit`
- [x] Fire per-cell callbacks before `Runtime::fire_on_change()`
- [x] Test callback execution order (per-cell before global)

### Builder Pattern / Ergonomics (Phase 2C - Done)

- [x] Unified `Signal::new` with `durability? : Durability = Low` (replaces `Signal::new_with_durability`)
- [x] Added `label? : String` to `Signal::new` and `Memo::new`
- [x] Added `label? : String` and `durability?` to `create_signal` (replaces `create_signal_durable`)
- [x] Added `label? : String` to `create_memo`
- [x] Labels propagate through `CellMeta`, `CellInfo`, `format_path`
- [x] Labels surface in `derive(Debug)` output for `Signal` and `Memo`
- ~~Define `SignalBuilder[T]` struct~~ — skipped (replaced by optional params)
- ~~Add `Signal::builder(Runtime) -> SignalBuilder[T]`~~ — skipped
- ~~Add `SignalBuilder::with_value(T) -> Self`~~ — skipped
- ~~Add `SignalBuilder::with_durability(Durability) -> Self`~~ — skipped
- ~~Add `SignalBuilder::with_label(String) -> Self`~~ — skipped
- ~~Add `SignalBuilder::build() -> Signal[T]`~~ — skipped
- ~~Define `MemoBuilder[T]` struct with similar pattern~~ — skipped
- ~~Document builder pattern in API reference~~ — skipped

### Ergonomics (Phase 2C - Medium Priority)

- ~~Add `Runtime::with_on_change(self, f) -> Runtime` for method chaining~~ — skipped (replaced by `on_change?` optional param in `Runtime::new`)
- [x] Unified `create_signal` with optional `durability?` replaces `create_signal_durable`
- [ ] Explore RAII `BatchGuard` if MoonBit adds destructors

### Graceful Error Handling (Phase 2D — Done)

- [x] Add raised-error rollback to `Runtime::batch` (accepts `() -> Unit raise?`)
- [x] Add `rollback_pending` closure to `CellMeta` for per-signal batch rollback hooks
- [x] Add `Runtime::batch_result` returning `Result[Unit, Error]` instead of re-raising
- [x] Add `@incr.batch_result(db, f)` Database helper form
- [x] Add `Memo::get_or(fallback : T) -> T` for cycle-safe reads without pattern matching
- [x] Add `Memo::get_or_else(fallback : (CycleError) -> T) -> T`
- [x] Add `MemoMap::get_or` and `MemoMap::get_or_else` with identical semantics

### Advanced (Phase 4)

- [x] Add subscriber (reverse) links for push-based invalidation
- [x] Add `Runtime::dependents(CellId) -> Array[CellId]` (requires subscriber links)
- [x] Add `CellOps` trait for uniform cell dispatch (`cells/cell_ops.mbt`)
- [x] Add `Committable` trait for batch-commit dispatch
- [x] Add `Reactive[T]` push-mode derived cell (`cells/reactive.mbt`)
- [x] Add `Effect` push-mode side-effect cell (`cells/effect.mbt`)
- [x] Add level-sorted push propagation engine (`cells/propagate.mbt`)
- [x] Add `HybridMemo[T]` push-pull hybrid memo (`cells/hybrid_memo.mbt`)
- [x] Add `create_hybrid_memo` Database helper and `Readable` impl
- [x] Re-export `HybridMemo` from root facade (`incr.mbt`)
- [x] Add Datalog primitives: `Relation[T]`, `Rule`, `Runtime::fixpoint()`

## Tracked Struct Support

- [x] Add `TrackedCell[T]` wrapping `Signal[T]` for field-level dependency isolation (`cells/tracked_cell.mbt`)
- [x] Add full `TrackedCell` API: `new`, `get`, `get_result`, `set`, `set_unconditional`, `id`, `durability`, `on_change`, `clear_on_change`, `is_up_to_date`, `as_signal`
- [x] Add `Trackable` trait with `cell_ids(Self) -> Array[CellId]`
- [x] Add `Readable` impl for `TrackedCell[T]`
- [x] Add `create_tracked_cell` helper function (mirrors `create_signal` pattern)
- [x] Add `gc_tracked[T : Trackable](rt, tracked)` no-op stub (call site established for Phase 4 migration)
- [x] Re-export `TrackedCell` from root facade (`incr.mbt`)
- [x] Whitebox tests in `cells/tracked_cell_wbtest.mbt`
- [x] Integration tests in `tests/tracked_struct_test.mbt`

## Cleanup: Vestigial `dirty` Flag

After the hybrid dirty-marking removal (HybridMemo no longer participates in push propagation),
the `dirty` field on `MemoData` is never set to `true`. All checks are no-ops. These tasks
clean up the dead logic.

- [x] Remove `dirty` field from `MemoData` in `cells/pull_memo.mbt`
- [x] Remove `not(root.dirty)` guards in `cells/verify.mbt` (lines ~92, ~97, ~152)
- [x] Remove `memo.dirty = false` assignment in `cells/verify.mbt` finalization (line ~205)
- [x] Remove `cell.dirty = false` in `HybridMemo::get()` slow path (`cells/hybrid_memo.mbt`)
- [x] Remove `not(cell.dirty)` from `HybridMemo::get()` fast path — collapse to `verified_at >= current_revision`
- [x] Update `HybridMemo::get()` doc comments that reference "dirty"
- [x] Update `cells/hybrid_memo.mbt` top-of-file doc comment referencing dirty flag

## HybridMemo Lifecycle

- [x] Add `HybridMemo::dispose()` — remove from subscriber sets, mark `cell_index` slot as `Disposed`
- [x] Add whitebox test for dispose (verify subscriber cleanup)

## Dispose / GC — Layer 4b: Push Suspension ✓ (PR #32)

- [x] Gate `on_observe` to 0→1 observer transition (`add_gc_root` returns previous count)
- [x] `PushReactiveData::on_unobserve` — suspend push by unsubscribing (guard: `subscribers.is_empty()`)
- [x] `PushReactiveData::on_observe` — recompute with fresh tracking on reactivation
- [x] `Scope::add_observer` — register observer with scope dispose hooks
- [x] `MemoMap::sweep` — remove disposed entries after gc()
- [x] Edge case tests: GC of suspended, dispose during suspension, source disposal, fixpoint abort
- [x] Integration tests via public API

## Push Propagation Efficiency

- [x] In mixed graphs (reactives + hybrid memos), `push_propagate_from` BFS traverses all reachable hybrid/pull memo subscriber links even when no push node is downstream of the changed signal. Consider per-signal transitive-push-subscriber tracking to skip unnecessary traversal. — Implemented via `push_reachable_count` (PR #24): O(1) per-source gate + inner BFS pruning; 62x–1335x speedup on mixed graphs.

## Internal Refactoring

- [x] Extract `Runtime::advance_revision(durability)` to consolidate duplicated revision-bump logic
- [x] Extract `Runtime::mark_input_changed(id)` helper to consolidate duplicated signal-commit logic
- [x] Replace silent `None => Ok(true)` fallback in `finish_frame_changed` with `abort(...)` assertion
- [x] Replace silent `None` skip in `commit_batch` with `abort(...)` assertion
- [x] Add runtime ownership check (`id.runtime_id != self.runtime_id`) in `Runtime::get_cell`
- [x] Simplify `Signal::get_result` to delegate to `Ok(self.get())`
- [x] Improve `Memo::get` abort message to use `CycleError::format_path`
- [x] Centralize cycle-path construction with `CycleError::from_path(path, closing_id)`
- [x] Move pipeline traits to `pipeline/pipeline_traits.mbt`; mark experimental in docs
- [x] Convert safe C-style loops to idiomatic `for .. in` syntax in `memo.mbt` and `runtime.mbt`
- [x] Replace `Array[CellMeta]` with SoA layout: `pull_signals : Array[PullSignalData]`, `pull_memos : Array[PullMemoData]`, `cell_index : Array[CellRef]`
- [x] Add `CellRef` enum (`PullSignal(Int) | PullMemo(Int)`) for O(1) dispatch via `cell_index`
- [x] Replace `maybe_changed_after` with `pull_verify` using explicit `PullVerifyFrame` stack
- [x] Add root durability fast-path to `pull_verify` (skip dep walk if no relevant-durability input changed)
- [x] Add per-dep durability shortcut and short-circuit on first detected change in `pull_verify`
- [x] Remove `CellMeta` and `CellKind` entirely; add `get_durability`, `get_pull_signal`, `get_pull_memo` helpers

## Testing

- [x] Stress test: deep dependency chain (250 levels) to verify iterative verification
- [x] Wide fanout test: single signal with many downstream memos
- [x] Test `Memo` with custom `Eq` types where structural equality differs from identity
- [x] Test cycle detection across 3+ mutually recursive memos

## Package Structure

- [x] Split flat single-package library into four MoonBit sub-packages (`types/`, `cells/`, `pipeline/`, root facade)
- [x] Move pure value types (`Revision`, `Durability`, `CellId`) to `dowdiness/incr/types`
- [x] Move all engine code to `dowdiness/incr/cells`
- [x] Move experimental pipeline traits to `dowdiness/incr/pipeline`
- [x] Re-export all public types from root via `pub type` transparent aliases in `incr.mbt`
- [x] Move whitebox tests (`*_wbtest.mbt`) to `cells/` for private field access
- [x] Move unit tests (`*_test.mbt`) to `cells/` (co-located with source)
- [x] Create `tests/` package for integration tests exercising the full `@incr` public API
- [x] Zero breaking changes — downstream users see identical `@incr` API

## Salsa-Style Query API (Phase 4E)

Each step builds on the previous. See [semantic-interning.md](semantic-interning.md) for interning design and [roadmap.md](roadmap.md) for context.

**Status (2026-03-28):** Partially deferred — see [roadmap.md](roadmap.md) Phase 4E for rationale.
Recommended next step before implementing these: add a simple type system to the lambda calculus
parser. Boundary ③ (CST → Typed AST) needs to exist before these features can be validated.

### Semantic Interning ✓ (PR #34)

- [x] `InternId` struct with `index : Int`, `Hash`, `Eq`, `Compare` (in `types/`)
- [x] `InternTable[T]` with `intern`, `get`, `len`
- [x] Unit tests for round-trip, dedup, len tracking
- [x] Integration test: `InternId` as `MemoMap` key (via lambda type-checker, loom#81)

### Semantic Interning — Follow-ups

- [ ] Add `InternId` table discriminator (table ID field) to prevent cross-table mixups.
      Currently `InternId { index }` only — an ID from one table silently indexes another.
      Add when multiple InternTables coexist in the same pipeline.
- [ ] Add `InternTable::clear()` or generation-based GC for long-lived sessions.
      Grow-only is acceptable for short editing sessions; production use needs cleanup.
- [ ] Add integration test: `InternId` in `Relation` for O(1) Datalog fact equality

### Tracked Structs

No new library code needed — `TrackedCell`, `Trackable`, and `MemoMap` already provide all
required infrastructure. The work here is demonstrating the pattern, not building it.

- [ ] Add integration test: `InternId` + `TrackedCell` fields, field-level dependency granularity
      (change one field, only dependent memos recompute; identity key stable across revisions)

### Accumulators — DEFERRED

Deferred until Boundary ③ (CST → Typed AST) exists with multiple interdependent queries.
The following design questions must be answered before implementation:
- Type erasure: `Runtime` is not generic — how does `accumulate(T)` store without making Runtime generic?
- Transitive collection: `accumulated(memo)` must collect from memo and all transitive sub-calls,
  requiring a second dependency graph (query call stack) on top of the existing one.
- Backdating: comparing `Array[T]` equality requires `T : Eq`; insertion order must be stable.
- Invalidation: if only accumulated values change (not the return value), dependents still need
  to recompute — this doesn't fit the existing model where backdating is keyed to the return value.

- [x] Build Boundary ③ use case first (lambda type-checker with type errors as diagnostics) — loom#81
- [ ] Design accumulator API informed by concrete use case (type-checker diagnostics are now available as `TypeResult.diagnostics`)
- [ ] Implement side-channel collection on `Runtime`
- [ ] Integrate with dependency tracking and backdating
- [ ] Add tests for diagnostic collection across multiple queries

## Boundary 3: Type-Checker Follow-ups

Boundary 3 (bidirectional type-checker) shipped in loom#81 + incr#34. These follow-ups
improve correctness, performance, and integration beyond the infrastructure validation scope.

### Incremental Pipeline

- [ ] **Incremental name resolution** — resolution is a single coarse `Memo[ResolvedModule]`;
      split into per-def resolution for finer-grained incrementality
- [ ] **MemoMap stale entries after structural rebuild** — MemoMap internal Memos survive scope
      dispose (Runtime-owned, not chain-scope-owned). The `is_disposed()` + name guard prevents
      wrong reads, but stale entries accumulate. Fix: scope MemoMap to chain, or add sweep-on-rebuild
- [ ] **Stable identity across insertions** — encounter-order shifts when inserting a def at position 0,
      invalidating all subsequent DefIds. Consider content-hashing or path-independent naming

### Type System Extensions (deferred — not needed for infra validation)

- [ ] Polymorphism / type variables / unification
- [ ] Position/span tracking in diagnostics (AST doesn't carry spans yet)

### Integration

- [ ] **Wire into ReactiveParser** — connect `build_typecheck_pipeline` to loom's `ReactiveParser`
      so type results flow through `Signal[String]` → parse → typecheck end-to-end
- [ ] **TypedTerm duplication cleanup** — `convert.mbt` is a full tree copy to add `None` annotations;
      consider a side-table of annotations keyed by node identity if the typechecker expands

## Pipeline Traits — Deferred (move to loom)

**Status (2026-04-08):** Deferred. Current pipeline traits (`Sourceable`, `Parseable`, `Checkable`,
`Executable` in `incr/pipeline/`) are too generic to be useful — everything returns `Array[String]`,
no typed AST/CST, no incremental semantics. Only exercised by a test fixture (`CalcPipeline`).
Zero production usage.

**Decision:** Don't integrate into loom's `ReactiveParser` now. The concrete methods on
`ReactiveParser` (`set_source`, `cst`, `diagnostics`, `term`) already serve as the de facto
pipeline interface. Extracting traits is premature — there isn't a second implementation that
needs the generic interface.

**When to revisit:** When one of these becomes true:
- A second pipeline implementation exists that needs to share an interface with `ReactiveParser`
  (e.g., a push-based pipeline using `Reactive`/`Effect`)
- Post-parse stages (type-checking, evaluation) land in canopy and need a composable extension
  mechanism on `ReactiveParser`
- Generic editor features (autocomplete, hover, go-to-definition) need to work across languages
  via trait dispatch

**Recommended approach when revisiting:**
- Move pipeline traits from `incr/pipeline/` to `loom/src/pipeline/`
- Use capability traits (trait-per-stage) on universally-typed stages only (`String`, `CstStage`,
  `Array[Diagnostic]`). Language-specific stages (AST, eval) stay concrete — MoonBit's `Self`-only
  traits can't abstract over the AST type parameter.
- Consider adding a diagnostics extension protocol to `ReactiveParser` so post-parse stages can
  register diagnostic sources (aggregated in `diagnostics()`)
- Finally Tagless is **not** the right pattern here — pipeline stages have heterogeneous types
  and linear composition, not tree-shaped construction. See conversation notes 2026-04-08.

**Current tasks (keep until migration):**
- [ ] Remove `incr/pipeline/` package when traits move to loom (update `incr.mbt` re-exports)
- [ ] Remove `CalcPipeline` test fixture from `incr/tests/traits_test.mbt`
- [ ] Add capability traits to `loom/src/pipeline/` with `ReactiveParser` impls

## Runtime Modularization (Phase 4 — Remaining)

Architecture analysis completed 2026-04-16. See [design.md](design.md#architecture-analysis-2026-04-16) for full diagnosis.

### Completed (PR #35)

- [x] Add `PropagationPhase` enum (`Idle`, `PushPropagating`, `InFixpoint`, `GarbageCollecting`) with `enter_phase`/`leave_phase` helpers
- [x] Replace `in_fixpoint : Bool` and `in_push_propagation : Bool` with phase checks
- [x] Add phase transition tests (mutual exclusion, panic on re-entry)
- [x] Extract `RevisionState` (`current_revision`, `durability_last_changed`) within RuntimeCore
- [x] Extract `TrackingState` (`tracking_stack`) within RuntimeCore
- [x] Extract `BatchState` (`batch_pending`, `batch_frames`, `batch_max_durability`, `batch_depth`) within RuntimeCore
- [x] Update all whitebox tests to access fields through new struct paths
- [x] Extract shared `diff_and_update_subscribers` function
- [x] Migrate `memo_force_recompute` to use shared function (preserves `seen` set optimization)
- [x] Migrate `finish_tracking` to use shared function

### Completed (PR #36)

- [x] Route batch→push propagation through coordinator (`propagate_changes`) instead of direct call
- [x] `push_propagate_from` now has exactly one caller (`propagate_changes`)
- [x] Delete dead `mark_input_changed` function

### Remaining

- [x] Internal package split — Engine types split across `cells/internal/{shared,pull,push,datalog}/`. Pull-engine split is partial: only `PullSignalData` moved; `MemoData` stays in `cells/` because its compute closure references `CycleError` (see [spec](superpowers/specs/2026-04-18-incr-stage5-internal-split-design.md) for rationale).
- [x] Verify engine packages do not import each other — `scripts/check-engine-isolation.sh` enforces pairwise engine isolation and the no-back-edge invariant.
- [ ] Complete pull-engine split: move `MemoData` to `cells/internal/pull/` once `CycleError` is untangled (requires redesigning `CycleError::format_path` or moving `CycleError` data into `types/` with a non-`Runtime` render pathway).
- [x] Factor duplicated `dispose_cell` bodies in `cells/datalog_lifecycle.mbt` — extracted `dispose_datalog_cell` helper (commit `309d904`). Design note at [archive/2026-04-18-datalog-dispose-factoring.md](archive/2026-04-18-datalog-dispose-factoring.md) records why a trait-default alternative was rejected.

## Documentation

- [x] Add doc comments to all public functions
- [x] Add usage examples for durability in README
- [x] Keep [design.md](design.md) in sync when core algorithms change
- [x] Organize user documentation in `docs/` folder (getting-started, concepts, api-reference, cookbook)
