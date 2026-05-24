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
- [ ] `memo_restore_on_abort` (cells/accumulator.mbt): replace O(n²) linear scan of `prev_contributions` during `touched` iteration with a HashSet lookup. **Validated 2026-04-26** ([bench](performance/2026-04-26-memo-restore-on-abort-bench.md), `cells/accumulator_restore_bench_wbtest.mbt`): N=5 → 0.28 µs, N=20 → 1.31 µs, N=100 → 12.51 µs (worst case, prev/touched disjoint). Quadratic scaling confirmed but constants small enough that linear setup dominates at N ≤ 20. Realistic drivers (lambda type-checker) use 1–2 accs per memo — not actionable. Reopen if a driver hits 50+ accs/memo with frequent aborts.

### Investigation queue

- [x] **Per-recompute allocation elimination (tracking-buffer reuse)** — `cells/internal/kernel/state.mbt` (`ActiveQuery`). **Shipped 2026-05-16** as lazy-allocation of the 2 accumulator-only fields (`accumulator_reads`, `touched_accumulator_slots`). Microbench probe rejected the pool-reuse half of the plan (~2% / within σ); lazy-allocation alone delivered −15.9% on 1000-reactive fanout (−46 ns/r). Result + corrected estimates: [docs/performance/2026-05-16-tracking-buffer-lazy-alloc.md](performance/2026-05-16-tracking-buffer-lazy-alloc.md).

- [x] **Disposed-cell-on-same-signal anomaly — retracted 2026-05-17.** The 2026-05-16 cost-decomp doc claimed 100 reactives disposed on one signal cost 27 µs per `Signal::set` vs 45 ns on a separate signal. Reproduction on `fed9428` measured both at ~45 ns — indistinguishable from the cold-runtime baseline. The 27 µs cost attributed to the disposed bench was actually the `100 abandoned reactives` bench (`tests/bench_test.mbt:216`), where the SoA still holds the live reactives because `rt.gc()` is never called and `push.node_count` is 100. Labels swapped in the original analysis; no bug exists. Regression guard: `cells/eager_derived_wbtest.mbt` "dispose: 100 reactives on one signal leave subscribers empty and node_count zero". Cost-decomp doc corrected in the same commit.

- [ ] **Push-engine scheduler rewrite** (deferred) — replace `@priority_queue.PriorityQueue[PushEntry]` heap with level-bucketed dirty list (`Array[Array[CellRef]]` indexed by topological level). Removes log N heap ops + one allocation per push entry. Estimated ~30–50 ns/reactive at N=1000. This is the *other half* of what alien-signals does in Vue 3.6. Defer until tracking-buffer reuse lands.

- [ ] **Push-engine link-list port (deprioritized)** — `cells/internal/push/`. The original investigation surfaced 1.2–1.5× speedup on the BFS iter path, smaller than the Vue 3.6 headline because incr is already SoA. Realistic but narrower than the targets above. Revisit if a future workload shifts the cost balance (very-low-cost compute closures making subscriber-set iter dominant). Investigation record: [docs/performance/2026-05-16-push-engine-linklist-microbench.md](performance/2026-05-16-push-engine-linklist-microbench.md).

- [ ] **Constructive traces — feasibility and cost-benefit study (research)**. `incr` is currently a (Suspending, Verifying-via-revisions) system in the "Build Systems à la Carte" taxonomy (Mokhov, Mitchell, Peyton Jones 2020). Promoting the rebuilder to **Constructive traces** would store hashed `(task description, input hash → output)` triples, enabling cross-process and cross-machine result reuse (the Bazel / Cloud Shake / Nix capability that revisions cannot support — revisions don't survive process boundaries). Open questions:
  - **(a) Closure hashing.** What is the right hash domain for `Memo` compute closures? Closure identity is not a stable hash; needs either content hashing of the closure body, user-supplied stable keys, or a `#[derive(Hash)]`-shaped annotation.
  - **(b) Workload fit.** Does the storage cost amortize for typical `incr` workloads (rust-analyzer-style query graphs vs. CRDT projection memos vs. live UI reactivity)? Different workloads have different read/write/cache-hit ratios.
  - **(c) Cycle interaction.** Does cycle handling translate? Constructive caches assume deterministic outputs, and `CycleError` paths violate that determinism per-cell. A cycle-positive read cannot be cached at all, or the cache must be keyed on the cycle structure rather than just inputs.
  - **(d) Interaction with durability shortcut.** Does the trace store subsume `durability_last_changed[level]`, or coexist with it? Durability is a coarse-grained invalidation that may be redundant in the presence of fine-grained constructive traces.
  - **(e) Distributed cache architecture.** If pursued, what is the storage backend (filesystem, KV store, content-addressable object store like Bazel's CAS)?

  Write a feasibility doc (`docs/research/constructive-traces-feasibility.md`) before committing to or rejecting this direction. Out of scope for the current architecture; tracked here so future "why doesn't incr cache across processes?" questions have a documented answer. See [docs/design/internals.md](design/internals.md) §"Where `incr` Sits in the Design Space".

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
- [x] Add `Reactive[T]` push-mode derived cell (`cells/eager_derived.mbt`)
- [x] Add `Effect` push-mode side-effect cell (`cells/push_effect.mbt`)
- [x] Add level-sorted push propagation engine (`cells/push_propagate.mbt`)
- [x] Add `HybridMemo[T]` push-pull hybrid memo (`cells/reachable_derived.mbt`)
- [x] Add `create_hybrid_memo` Database helper and `Readable` impl
- [x] Re-export `HybridMemo` from root facade (`incr.mbt`)
- [x] Add Datalog primitives: `Relation[T]`, `Rule`, `Runtime::fixpoint()`

## Tracked Struct Support

- [x] Add `TrackedCell[T]` wrapping `Signal[T]` for field-level dependency isolation (`cells/input_field.mbt`)
- [x] Add full `TrackedCell` API: `new`, `get`, `get_result`, `set`, `set_unconditional`, `id`, `durability`, `on_change`, `clear_on_change`, `is_up_to_date`, `as_signal`
- [x] Add `Trackable` trait with `cell_ids(Self) -> Array[CellId]`
- [x] Add `Readable` impl for `TrackedCell[T]`
- [x] Add `create_tracked_cell` helper function (mirrors `create_signal` pattern)
- [x] Add `gc_tracked[T : Trackable](rt, tracked)` no-op stub (call site established for Phase 4 migration)
- [x] Re-export `TrackedCell` from root facade (`incr.mbt`)
- [x] Whitebox tests in `cells/input_field_wbtest.mbt`
- [x] Integration tests in `tests/tracked_struct_test.mbt`

## Cleanup: Vestigial `dirty` Flag

After the hybrid dirty-marking removal (HybridMemo no longer participates in push propagation),
the `dirty` field on `MemoData` is never set to `true`. All checks are no-ops. These tasks
clean up the dead logic.

- [x] Remove `dirty` field from `MemoData` in `cells/internal/pull/memo_data.mbt` (formerly `cells/pull_memo.mbt` pre-R1)
- [x] Remove `not(root.dirty)` guards in `cells/verify.mbt` (lines ~92, ~97, ~152 pre-R1; `pull_verify` body now in `cells/internal/kernel/verify.mbt`)
- [x] Remove `memo.dirty = false` assignment in `cells/verify.mbt` finalization (line ~205 pre-R1; finalization now in `cells/internal/kernel/verify.mbt`)
- [x] Remove `cell.dirty = false` in `HybridMemo::get()` slow path (`cells/reachable_derived.mbt`)
- [x] Remove `not(cell.dirty)` from `HybridMemo::get()` fast path — collapse to `verified_at >= current_revision`
- [x] Update `HybridMemo::get()` doc comments that reference "dirty"
- [x] Update `cells/reachable_derived.mbt` top-of-file doc comment referencing dirty flag

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
- [x] Convert safe C-style loops to idiomatic `for .. in` syntax in `derived.mbt` and `runtime.mbt`
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

## Formal Verification

- [ ] Build a machine-checked proof of the core consistency theorem for a formal model of `incr`: model the pure, acyclic pull core; define `scratch_eval(root, inputs)` as the from-scratch reference semantics; prove that successful verification leaves the root cache equal to `scratch_eval` under the current signal store. Keep the proof scoped to the model first — production `Runtime` refinement, push, datalog, GC/dispose, batching, and user callback effects remain separate future work.

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

Each step builds on the previous. See [semantic-interning.md](research/semantic-interning.md) for interning design and [roadmap.md](roadmap.md) for context.

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
- [x] Add integration test: `InternId` in `Relation` for O(1) Datalog fact equality

### Tracked Structs

No new library code needed — `TrackedCell`, `Trackable`, and `MemoMap` already provide all
required infrastructure. The work here is demonstrating the pattern, not building it.

- [ ] Add integration test: `InternId` + `TrackedCell` fields, field-level dependency granularity
      (change one field, only dependent memos recompute; identity key stable across revisions)

### Accumulators — SHIPPED

Shipped 2026-04-20. See [ADR](decisions/2026-04-20-accumulator-api.md) and archived [implementation spec](archive/completed-phases/2026-04-19-accumulator-api-design.md).

Resolved design questions:
- **Type erasure:** handle-local typed `Array[T]` storage per accumulator; Runtime stores only erased `AccumulatorSlot`.
- **Transitive collection:** deferred — Path 1 is local-only. Module-level aggregation lives in driver code. Add `accumulated_transitive` as a separate method if a future driver needs it.
- **Backdating of `Array[T]`:** sidestepped via per-memo `push_revised_at : Revision` counter. Comparison is `current_rev > stored_rev`, not array equality.
- **Invalidation on diagnostic-only change:** synthetic dep `(accumulator_slot, producer_memo) → revision` recorded during tracked `accumulated(acc)` reads; mismatch invalidates consumer even when the producer's return value is backdate-equal.

- [x] Build Boundary ③ use case first (lambda type-checker with type errors as diagnostics) — loom#81
- [x] Design accumulator API informed by concrete use case — [archive/completed-phases/2026-04-19-accumulator-api-design.md](archive/completed-phases/2026-04-19-accumulator-api-design.md)
- [x] Implement side-channel collection — incr PR #42 + fix `1715981`
- [x] Integrate with dependency tracking and backdating — synthetic dep via `push_revised_at` per producer memo
- [x] Add tests for diagnostic collection across multiple queries — 41 accumulator tests (whitebox) + lambda driver incrementality test (loom PR #94)
- [x] Driver migration — lambda type-checker moved off `TypeResult.diagnostics` to `Accumulator[TypeDiagnostic]` (loom PR #94)

## Boundary 3: Type-Checker Follow-ups

Boundary 3 (bidirectional type-checker) shipped in loom#81 + incr#34. The infrastructure work that lived in incr is complete; the remaining follow-ups are **driver-layer concerns owned by `loom/examples/lambda` and canopy** — they should be tracked in those projects' own backlogs, not here.

### Shipped (incr-side anchors)

- [x] Incremental name resolution (per-def `resolve_memos` chain) — loom PR #95.
- [x] `MemoMap::clear()` for structural rebuild teardown — incr; integrated by loom/examples/lambda.
- [x] Stable identity across insertions (`name_to_idx` on PipelineState) — loom; first-wins + diagnostic on duplicates.
- [x] `attach_typecheck` bridge wiring `Signal[String]` → parse → typecheck end-to-end via the unified `@loom.Parser[Ast]` (loom ADR 2026-04-17).

### Delegated outward (not actionable from incr)

- **loom/examples/lambda:** Span-keyed unique identity for shadowed duplicates (needs CST span threading through `convert.mbt`); `TypedTerm` duplication cleanup (`convert.mbt` tree-copy → side-table keyed by node identity).
- **loom/examples/lambda type system:** Polymorphism / type variables / unification; position/span tracking in diagnostics. Not needed for infra validation; pursue when a driver demands it.

## Pipeline Traits — Deferred (delete from incr; new design owned by loom)

**Status (2026-04-08):** Deferred. Current pipeline traits (`Sourceable`, `Parseable`, `Checkable`, `Executable` in `incr/pipeline/`) are too generic to be useful — everything returns `Array[String]`, no typed AST/CST, no incremental semantics. Only exercised by a `CalcPipeline` test fixture; zero production usage.

**Decision:** The trait redesign + new home in `loom/src/pipeline/` is loom's call (gated on a second pipeline implementation, post-parse stages landing in canopy, or cross-language editor features). The only thing incr owes is removing the dead package once loom is ready to receive a replacement.

### Incr-owned tasks (when loom commits to the move)

- [ ] Remove `incr/pipeline/` package and update `incr.mbt` re-exports.
- [ ] Remove the `CalcPipeline` test fixture from `incr/tests/traits_test.mbt`.

### Delegated outward (not actionable from incr)

- **loom:** Design and host the replacement pipeline traits in `loom/src/pipeline/`. Approach notes (capability-traits over universally-typed stages, language-specific stages stay concrete, Finally Tagless is the wrong pattern) are recorded in the git history of this section if needed.

## Runtime Modularization (Phase 4 — Remaining)

Architecture analysis completed 2026-04-16. See [design/internals.md](design/internals.md#architecture-analysis-2026-04-16) for full diagnosis.

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

- [x] Internal package split — Engine types split across `cells/internal/{shared,pull,push,datalog}/`. Pull engine now contains both `PullSignalData` and `MemoData`; `CycleError` moved to `types/` as a pure-value error (see [spec](design/specs/2026-04-18-incr-stage5-internal-split-design.md) for Stage 5 rationale and the follow-up archive note for the CycleError untangle).
- [x] Verify engine packages do not import each other — `scripts/check-engine-isolation.sh` enforces pairwise engine isolation and the no-back-edge invariant.
- [x] Complete pull-engine split: `MemoData` moved to `cells/internal/pull/memo_data.mbt`. `CycleError` now lives in `types/` as a pure value; `format_path` drops its `Runtime` parameter (breaking change — labels are captured at error-construction time). `CellLifecycle` impl for `MemoData` stays in `cells/pull_memo_lifecycle.mbt` because it needs `Runtime`.
- [x] Factor duplicated `dispose_cell` bodies in `cells/datalog_lifecycle.mbt` — extracted `dispose_datalog_cell` helper (commit `309d904`). Design note at [archive/2026-04-18-datalog-dispose-factoring.md](archive/2026-04-18-datalog-dispose-factoring.md) records why a trait-default alternative was rejected.

## Refactor Audit Findings (2026-04-19)

Post-Stage-5 audit of `cells/` + Codex validation. Stage 6 (engine extraction) remains intentionally deferred; these are the remaining concrete items that survived Codex review.

### Target #1 — Cross-runtime check duplication (DONE)

Six cell read paths inlined the same ~10-line `current_computing_runtime_id` guard (abort on cross-runtime, reset global before aborting). `Memo::get_result_inner` uniquely had a *forgiving* variant that additionally repairs stale global state when this runtime's tracking stack is empty — required for panic-test isolation because `read_permissive` / `MemoMap` bypass the outer strict check.

- [x] Extract `Runtime::check_cross_runtime(cell_runtime_id, kind)` helper (strict variant) — `cells/tracking.mbt:68` (was `:149` pre-R1)
- [x] Replace 6 strict sites: `input.mbt`, `derived.mbt` (outer), `reachable_derived.mbt`, `eager_derived.mbt`, `datalog_relation.mbt`, `datalog_map_relation.mbt`
- [x] Leave `Memo::get_result_inner` with its original forgiving repair logic — it cannot be unified with the strict helper because "stale-global" vs "legitimate cross-runtime" cannot be distinguished locally without a global runtime registry (the forgiving repair relies on checking THIS runtime's stack, which is correct only because `read_permissive` / `MemoMap` paths are same-runtime by construction)

**What the audit got wrong:** the "latent bug" framing was overstated — the memo inner's repair is intentional defensive code for panic-test isolation, not a drifted invariant that should be applied everywhere. An attempted unified "repair everywhere" helper broke 5 tests (4 false-negative cross-runtime aborts + 1 surfaced state-leak). Codex's original direction (unify) was correct; the specific generalization (apply memo inner's heuristic uniformly) was not safe.

**Net change:** 6 sites deduplicated to one helper. No behavior change. ~51 source lines consolidated.

### Target #2 — Cell-registration ritual for free-list kinds (DONE, partial)

- [x] Introduce `Runtime::install_cell[T : CellOps + CellLifecycle]` helper (cells/runtime.mbt) — one generic helper covering all free-list SoA kinds, parameterized over (free_list, array, `fn(Int) -> CellRef`, `fn(CellId) -> T`). Returns `(CellId, Int)` so callers needing the slot index (reactive/effect for post-install sources/level update) can destructure.
- [x] Migrate `Signal::new`, `Reactive::new`, `Effect::new`; delete `Runtime::new_signal_id`
- [x] Leave `Memo::_create` and `HybridMemo::new` as-is — both have a closure-construction cycle (the typed handle is captured inside the stored compute closure); using `install_cell` there would force a `Ref[Memo[T]?]` dance that's worse than the current local pattern. The existing `_create` already factors the pattern within memo's own file.
- [x] Leave datalog constructors as-is — append-only, different shape.
- [x] Add debug invariant `Runtime::check_table_invariant` + whitebox test "runtime: dispatch tables stay index-aligned across all cell kinds" in `soa_wbtest.mbt`

**Net change:** 1 new helper (~24 lines), 1 new invariant + test (~30 lines), 3 sites migrated (signal/reactive/effect), 1 asymmetric helper deleted (`Runtime::new_signal_id`). Tests: 506 → 507 (invariant test added). Memo and HybridMemo keep their local `_create` / inline pattern by design.

### Target #3 — push_lifecycle dispose dedup (DECLINED)

`cells/push_lifecycle.mbt:5-16` (`PushReactiveData::dispose_cell`) and `:68-79` (`PushEffectData::dispose_cell`) are near-identical; differ only in variant arm, SoA array, and free-list. `datalog_lifecycle.mbt` factored this via `dispose_datalog_cell`.

- [x] Evaluated, declined — after Targets #1 and #2, remaining duplication is ~6–10 lines. Unlike #1 (correctness-adjacent drift) and #2 (parallel-array invariant), **no load-bearing invariant rides on unification**; the two inline impls function as self-documenting summaries of push-specific teardown (source-link removal + slot free + `node_count--`). Land opportunistically if `push_lifecycle.mbt` is ever touched for a real reason.

### Intentionally deferred / not recommended

- **Runtime.mbt topic split** — `runtime.mbt` is 570 lines across ~16 sections, but most sections are cohesive and splitting is cosmetic without a concrete driver. Hard constraint for anyone who revisits: **subscriber management (`add/remove_subscriber`) and push-reachable accounting (`push_contribution` / `adjust_push_reachable`) must stay co-located** — they form one invariant cluster.
- **Memo.mbt split** (620 lines) — coherent chapters, no duplication, no pain.
- **cells/ folder reorg** — Stage 5 just moved SoA into `internal/`; another restructure now would churn without a driver.
- **Stage 6 engine extraction** — was "waits for accumulators or similar"; accumulators shipped 2026-04-20 without needing this extraction, so the original motivation is void. Revisit only when parallel computation or a second major extension creates concrete need.

## R1 Kernel Split Follow-ups (2026-04-26)

Surfaced during the PR #48 final review. R1 itself is closed.

- [x] ~~**gc_sweep abort-safety leak.**~~ **CLOSED 2026-04-26 — not actionable in MoonBit's execution model.** Audit (option b from the original framing) confirms every per-kind `dispose_cell` impl is abort-free during a gc context: RelationData/FunctionalRelationData/RuleData are pure clears; PullSignalData's only abort path (`remove_batch_signal`) is pre-eliminated by gc's `batch.depth==0` guard; MemoData's `remove_subscriber` does not abort on disposed deps and `slot.dispose_memo` is gated by `!slot.disposed`; PushReactive/PushEffect are similarly clean. `validate_cell_for_dispose` and `check_dispose_guard` aborts are also pre-eliminated by gc's own entry guards (own-runtime, empty tracking stack, batch.depth==0, phase Idle). Even if a future change *did* introduce a reachable abort, MoonBit's `abort` terminates execution unconditionally — there is no continuation that could observe the stuck `GarbageCollecting` phase, and `core.phase` is per-Runtime so it cannot contaminate the next test (which constructs a fresh `Runtime`). Adding a defensive phase reset would violate CLAUDE.md's "don't add error handling for scenarios that can't happen" rule. **Reopen only if:** (a) MoonBit gains catchable panics or shared-memory parallelism, or (b) a future `dispose_cell` impl introduces a reachable abort that the gc entry guards do not pre-eliminate.
- [x] ~~**`Runtime::dispose_cell` thinning.**~~ **CLOSED 2026-04-26 — not actionable, same anti-pattern as R2.** Audit of `cells/runtime.mbt` confirms 14 of 22 methods are correct-shape 1-line `@kernel.X` delegators. The remaining bodies are: `install_cell`, `check_table_invariant`, `check_accumulator_cache_invariant` (cannot move — touch Runtime-only `cell_lifecycle` / accumulator state), and `bump_revision` / `get_pull_signal` / `get_memo_data` (could move but adds 3 kernel API surface fns + 3 wrapper bodies for ~24 LOC saved — same wrapper-without-driver pattern the [R2 ADR](decisions/2026-04-26-r2-runtime-decomposition-deferred.md) rejected). `dispose_cell` itself remains 3-line orchestration; collapsing requires retyping `CellLifecycle::dispose_cell(Self, Runtime, CellId)` to take `(RuntimeCore, PullState, PushState, DatalogState, accumulator state, Runtime-only methods)` — invasive change for cosmetic gain. **Reopen only if** the `CellLifecycle` trait is being restructured for an unrelated reason (e.g. T1b MemoCommitPhase landing, which would refactor lifecycle traits anyway).

## Reactive Collections (2026-04-19)

Research + design sketches landed in the 2026-04-19 session. See
[reactive-collections.md](research/reactive-collections.md) for the survey and
four-family taxonomy; individual design sketches linked below. All
items here are exploratory — validate via Codex / plan-writing before
implementing.

### Prerequisites (small, independent)

- [x] Add `MemoMap::get_tracked(key) -> V` — thin tracked wrapper over
      the inner Memo's `.get()`. Shipped standalone.
- [ ] Add `MemoMap::remove_except(keys : Set[K]) -> Int` — **blocked on
      Blocker 1** (cross-key dispose aborts verify; see
      [reactive-map-design.md](research/reactive-map-design.md) Codex review
      2026-04-19). Do not land alone.

### Delegated outward — driver discovery owned by canopy

The remaining Reactive Collections work is **driver discovery**, which belongs to canopy (the system that would consume any of these). Research notes stay in `incr/docs/research/` for historical reference, but the next move is not an incr decision.

- **canopy:** Identify a concrete driver for `ReactiveMap[K, V]` (Family B). v1 framing refuted in PR #41; remaining value is upstream-key-set coordination + tracked `iter()`, not per-key deps. Do not commission an implementation plan in incr until canopy presents a driver `MemoMap` + `get_tracked` cannot supply. See [reactive-map-design.md](research/reactive-map-design.md) "Why v1's framing was wrong" + "Codex review 2026-04-19" for context. (`MemoMap::remove_except` API addition above is also gated on the same driver — Blocker 1 is unresolved.)
- **canopy:** Identify a concrete driver for `Relation::subscribe_delta` (Family A — logging / UI reconciliation / IPC). Plus, **redesign needed** before implementation: plain `Relation[T]` is monotonic with no retractions, no commit seam exists for direct inserts, failed batches don't roll back relation writes. See [relation-delta-observer-design.md](research/relation-delta-observer-design.md).
- **canopy:** Identify a concrete driver for Family C (nominal memoization + persistent trees) — evaluator / layout / tree-shaped type-checker state. Long-horizon bet. See [reactive-collections.md](research/reactive-collections.md) "Family C" section.

## API Naming Cleanup (Migration In Progress)

Context: PR #41 review surfaced that the old `get_untracked`/`get_tracked`
naming misled — the package-private memo read still recorded per-key deps
when a tracking frame was active (via `get_result_inner` calling
`record_dependency`); the real distinction is **strict tracked-context guard
vs permissive top-level read**, not tracking itself. Follow-up design work
expanded this into a first-principles ideal API vocabulary: `Signal ->
Input`, `Memo -> Derived`, `HybridMemo -> ReachableDerived`,
`Reactive -> EagerDerived`, `MemoMap -> DerivedMap`, `TrackedCell ->
InputField`, `Observer -> Watch`, `FunctionalRelation -> MapRelation`,
`Readable -> Freshness`, `Trackable -> InputFieldOwner`, and `Database ->
RuntimeContext`. This misread propagated through three revisions of
`reactive-map-design.md` before Codex caught it.
See [reactive-map-design.md](research/reactive-map-design.md) "Why v1's framing
was wrong" and
`~/.claude/projects/*/memory/feedback_code_verify_before_design.md`.

Package-private cleanup shipped: `Memo::get_untracked`,
`HybridMemo::get_untracked`, and `Reactive::get_untracked` were renamed to
`read_permissive`, with deprecated aliases left behind as a compile-time
migration guard.

Public target facades have now shipped for the main handle families
(`Input`, `Derived`, `ReachableDerived`, `DerivedMap`, `InputField`,
`EagerDerived`, `Watch`, `MapRelation`) and for target extension traits
(`RuntimeContext`, `Freshness`, `InputFieldOwner`). Compatibility names remain
available; final removal or breaking semantic flips are still deferred to a
dedicated migration window.

### Method-name candidates

- [x] Rename package-private `Memo::get_untracked`,
      `HybridMemo::get_untracked`, and `Reactive::get_untracked` to
      `read_permissive`, leaving deprecated aliases under the old names.
      Body: "reads value, records dep iff tracking frame active, never
      aborts on missing context."
- [x] Reconsider public naming from first principles. Decision:
      recoverable derived reads own the simple names (`get` for strict
      graph reads, `read` for permissive reads); aborting shortcuts carry
      `_or_abort`; `MemoMap` becomes `DerivedMap`; `Database` becomes
      `RuntimeContext`; constructor syntax replaces `create_*` helper
      names in the ideal final API. See
      [ADR 2026-05-21](decisions/2026-05-21-public-api-ideal-naming.md).
- [x] Add package-private strict/permissive `Result` read primitives for
      `Memo`, `HybridMemo`, and `MemoMap` as the internal substrate for target
      read semantics.
- [x] Add public target facades and helpers for `Input`, `Derived`,
      `ReachableDerived`, `DerivedMap`, `InputField`, `EagerDerived`,
      `Watch`, `MapRelation`, `RuntimeContext`, `Freshness`, and
      `InputFieldOwner`, while preserving compatibility handles.
- [x] Mark legacy `Runtime::read*` helpers as compatibility APIs after
      migrating in-repo callers off the new deprecation warnings.
- [x] Start Phase 2 docs/examples migration: README, getting-started,
      concepts, API reference, cookbook, and architecture now prefer target
      names where target facades cover the behavior.
- [x] Audit other `*_untracked` / `*_tracked` suffixes across
      `cells/` for the same misnaming pattern. Known candidates:
      `Runtime::ensure_computed_untracked` is retained because it
      explicitly avoids ordinary dependency recording; Observer methods
      now call `read_permissive`.
- [ ] Convert high-value target examples to checked `.mbt.md` examples or
      ` ```mbt check` blocks so future docs/API drift is caught by tooling.
      Split the remaining work into two buckets:
      - **Checked companions added:** README / getting-started target,
        callback, and batch snippets are covered by
        `docs/target_api_examples.mbt.md`; concepts behavior by
        `docs/concepts_examples.mbt.md`; cookbook target, accumulator, and
        memo-event snippets by `docs/cookbook_examples.mbt.md`; API-reference
        target facade and compatibility accumulator snippets by
        `docs/api_reference_examples.mbt.md`. `docs/concepts.md` and
        `docs/cookbook.md` have been reduced to pointers for already-covered
        behavior, with only summary syntax / lower-priority narrative fences
        left.
      - **Narrative snippets still present:** current non-archive docs no
        longer contain explicit `moonbit nocheck` fences, but many untagged
        ` ```moonbit` fences remain. Prioritize public user docs first
        (`docs/getting-started.md`, `docs/concepts.md`, `docs/cookbook.md`,
        `docs/api-reference.md`) by either replacing already-covered snippets
        with checked-companion pointers or adding missing checked companion
        coverage; then triage lower-priority ADR/design/performance snippets.

### Doc-comment audits

- [x] Sweep public doc comments for "tracked" / "untracked" shorthand
      that doesn't reflect the actual leaf-level behavior
      (`record_dependency` conditional on tracking frame). Prefer
      describing the abort vs silent distinction directly.
- [x] Update current design docs that referenced "untracked means
      doesn't record deps." Currently known:
      [reactive-map-design.md](research/reactive-map-design.md) (marked
      [SUPERSEDED] in-line; a proper rewrite would fold these into the
      v3 narrative) and
      `docs/design/specs/2026-04-15-boundary3-bidirectional-typechecker.md`
      (has an inline [Correction 2026-04-19] note; could be reworked
      if the spec is revisited). Historical archive docs are left as
      historical records.

## Documentation

- [x] Add doc comments to all public functions
- [x] Add usage examples for durability in README
- [x] Keep [design/internals.md](design/internals.md) in sync when core algorithms change
- [x] Organize user documentation in `docs/` folder (getting-started, concepts, api-reference, cookbook)
