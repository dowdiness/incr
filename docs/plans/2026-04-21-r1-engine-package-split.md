# R1 — Split Reactive Kernel from Cells

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement stage-by-stage. Each stage ships as a single PR, green tests + benchmarks before the next starts. No big-bang commits.

**Goal:** Extract graph-mechanics code (algorithms + propagation machinery + cross-state traversal) into a dedicated `cells/internal/kernel/` package. `cells/` retains `Runtime`, handle types, and per-cell-kind logic; `kernel/` never depends on `cells/`-only state (`SlotMeta`, handle types) or handle-specific logic. Kernel MAY branch on `CellRef` variants (already in `internal/shared/`); the boundary is "no handle state, no `cells/` imports," not "no cell-kind awareness." Runtime's methods become thin wrappers — or disappear entirely where only cells/ internal code calls them — over kernel free functions taking explicit state references.

**Non-goals (explicit):** no public API change; no behavior change; no accumulator restructuring (R5); no `MemoCommitPhase` trait (R3); no `RuntimeRegistry` (R4); no `pipeline/` retirement (R6); no Runtime-as-services decomposition (R2, must follow R1).

**Architecture:** Introduce `cells/internal/kernel/` as a sibling of `cells/internal/{shared,pull,push,datalog}/`. Kernel owns state sub-struct definitions, the phase state machine, and all algorithms (pull-verify, push-propagate, datalog-fixpoint, batch commit, tracking, subscriber maintenance, cycle construction, dispatch traversal). Kernel depends on `types/` + `internal/shared/` + `internal/{pull,push,datalog}/`. Kernel imports nothing inside `cells/` proper. Runtime remains defined in `cells/runtime.mbt` and owns state as fields; Runtime methods call kernel free functions.

**Tech Stack:** MoonBit; `moon check`, `moon test`, `moon fmt`, `moon info`, `moon bench --release`.

**Spec basis:** `docs/design/specs/2026-04-20-architecture-assessment.md` (Target architecture → Separation A).

---

## Stage 0 — Prerequisites (must complete before Stage 1)

**Status: Complete** (2026-04-24). All five artifacts landed; v3 plan incorporates the Codex findings below.

- [x] **Codex design review of this plan.** See [2026-04-21-r1-stage0-codex-review.md](2026-04-21-r1-stage0-codex-review.md). Verdict: READY WITH CAVEATS. Four substantive findings folded into v3 (SlotSnapshot trait signature, Stage 3c ordering, Stage 3g fixpoint wrapper, Stage 4 dispose scoping) plus the narrower kernel-boundary statement and D8 softening.
- [x] **Establish benchmark baseline.** See [docs/performance/2026-04-21-pre-r1-baseline.md](../performance/2026-04-21-pre-r1-baseline.md). 32 benches captured on native target (wasm-gc OOMs the moonrun heap; Stage 3 must use `--target native` for apples-to-apples). Tight-σ rows flagged as the Stage 3 gate.
- [x] **Audit `dispose_cell` flow.** See [2026-04-21-r1-stage0-audits.md](2026-04-21-r1-stage0-audits.md) §1. Plan claim verified — accumulator cleanup lives in `pull_memo_lifecycle.mbt` via CellLifecycle dispatch. `guard_dispose` body is pure coordinator over `phase` + `tracking.stack` (cells/runtime.mbt:713) and moves cleanly.
- [x] **Audit `ActiveQuery` field set.** See audit doc §2. Plan undercount corrected — **two** accumulator-typed fields: `accumulator_reads : HashMap[(AccumulatorId, CellId), Revision]` and `touched_accumulator_slots : HashSet[AccumulatorId]`. Both use types from `types/`; no structural blocker.
- [x] **Verify `check-engine-isolation.sh` extensibility.** See audit doc §3. Three-change extension plan specified for Stage 5 (add `internals` array, add invariant 4 "no sibling imports of kernel," update invariant 2 comment).

## Package Layout — Target State

```
types/                       (unchanged)
cells/internal/shared/       (receives SlotSnapshot trait in Stage 2)
cells/internal/pull/         (unchanged)
cells/internal/push/         (unchanged)
cells/internal/datalog/      (unchanged)
cells/internal/kernel/       NEW
├── moon.pkg                 imports types, shared, pull, push, datalog, priority_queue, hashmap, hashset
├── state.mbt                RevisionState, TrackingState, BatchState, PullState, PushState, DatalogState, RuntimeCore, PropagationPhase, ActiveQuery, runtime-id globals
├── dispatch.mbt             validate_cell_soft, cell_id_for, is_cell_disposed, get_changed_at, get_durability, get_subscribers, add_subscriber, remove_subscriber, push_contribution, collect_reachable_cells, adjust_push_reachable, cell_id_at
├── tracking.mbt             push_tracking, pop_tracking, record_dep, check_cross_runtime
├── cycle.mbt                construct_cycle_error
├── subscriber_diff.mbt      diff_and_update_subscribers
├── verify.mbt               pull_verify (takes `Array[&SlotSnapshot]`; SlotSnapshot has `push_revised_at_for(CellId)`)
├── push_propagate.mbt       push_propagate_from
├── fixpoint.mbt             run_fixpoint
├── propagate.mbt            propagate_changes, publish_cell_changes, fire_on_change
├── batch.mbt                commit_batch (depends on propagate.mbt)
├── dispose.mbt              dispose_cell coordinator (dispatches via CellLifecycle; per-kind cleanup stays in cells/*_lifecycle.mbt)
└── gc.mbt                   gc, collect_gc_roots, mark_reachable, gc_sweep, add_gc_root, remove_gc_root

cells/ (RETAINS):
├── runtime.mbt              Runtime struct def; Runtime::new; set/clear_on_change; thin wrappers for public-API methods only; accumulator fields unchanged
├── signal.mbt, memo.mbt, hybrid_memo.mbt, push_reactive.mbt, datalog_*.mbt, tracked_cell.mbt, accumulator.mbt, memo_map.mbt, scope.mbt, observer.mbt, introspection.mbt
├── *_lifecycle.mbt          Per-kind CellLifecycle impls (includes accumulator cleanup for memo dispose)
├── cell.mbt, cell_ops.mbt   Trait glue (unchanged)
└── *_test.mbt, *_wbtest.mbt Cell-kind tests stay with handles; engine-level wbtests move to kernel/ with their subjects
```

## Key Design Decisions

**D1. Kernel is `cells/internal/kernel/`, not top-level.** External consumers never import kernel; facade contract preserved.

**D2. Runtime struct stays in `cells/runtime.mbt`.** Public handle lives with other public handles. Kernel takes state refs explicitly; never mentions `Runtime`.

**D3. State sub-structs move to kernel with `pub(all)`.** Required so `cells/runtime.mbt` can construct them in `Runtime::new`. Caveat: `pub(all)` in an internal package means siblings (pull/push/datalog) *can* read kernel's state fields. They won't today because `check-engine-isolation.sh` bans the imports — the language guarantee is weaker than the enforced rule. Accepted.

**D4. Accumulator state stays on Runtime; verify gets a SlotSnapshot trait indirection.** `accumulator_slots`, `accumulator_contributions`, `next_accumulator_id`, `SlotMeta` type — all remain in `cells/`. But kernel's `pull_verify` currently reads `rt.accumulator_slots[id].{disposed, push_revised_at_for(target_id)}` (cells/verify.mbt:86) for synthetic-dep freshness. The revision is **per-memo**, not slot-wide — backed by `push_revised_at : HashMap[CellId, Revision]` on `SlotMeta` (cells/accumulator.mbt:16, :97). Resolution: introduce `pub trait SlotSnapshot` in `internal/shared/` with methods `disposed(Self) -> Bool` and `push_revised_at_for(Self, CellId) -> Revision`. `SlotMeta` in `cells/accumulator.mbt` implements it. Kernel `pull_verify` signature takes `slot_snapshots : Array[&SlotSnapshot]`. Runtime provides the slice via a thin `Runtime::slot_snapshots()` method. This keeps kernel kind-agnostic and accumulator state fully in cells/.

**Zero-copy caveat for `slot_snapshots()`:** Stage 2 must confirm MoonBit can materialize `Array[&SlotSnapshot]` from `Array[SlotMeta]` without per-call array allocation — either via struct-layout compatibility or a cached view. If allocation is forced, verify must take `Array[SlotMeta]` concretely (re-export from `cells/accumulator.mbt` via a narrow internal module) as a fallback. Decide in Stage 2 once the trait is compiled against the existing verify code.

**D5. Algorithms are free functions over state refs.** Example: `fn Runtime::pull_verify(self, cell)` becomes kernel's `fn pull_verify(core : RuntimeCore, pull : PullState, slot_snapshots : Array[&SlotSnapshot], cell : CellId) -> Result[Bool, CycleError] raise Failure`. Public Runtime methods that users call become thin wrappers. Methods that ONLY cells/ internal code calls get no wrapper; call-sites in handles import `@kernel` and call directly. This is decision D8 below — the wrapper economy.

**D6. `check-engine-isolation.sh` extended.** Kernel may import pull/push/datalog/shared/types; pull/push/datalog may not import kernel (would create a cycle); only `cells/*.mbt` (top level) may import kernel; `cells/internal/{pull,push,datalog,shared}/*.mbt` may not.

**D7. Cycle construction takes a dispatch slice, not Runtime.** Already pure-value after `6c7b5c1`; kernel's `construct_cycle_error(cell_ops : Array[&CellOps], path : Array[CellId], closing : CellId) -> CycleError` is the target.

**D8. Wrapper economy.** For each Runtime method that moves its body to kernel, classify:
  - **Public wrapper kept:** method is part of `@incr` public API (e.g., `Runtime::dispose_cell`, `Runtime::gc`, `Runtime::cell_info`). Keep the thin wrapper.
  - **Semantic internal wrapper kept:** method is a high-fan-out protocol verb used across many `cells/*.mbt` files. Keeps call-sites readable; wrapper body is one line delegating to `@kernel.*`. Reserved list: `pull_verify`, `push_tracking` / `pop_tracking` / `finish_tracking`, `top_active_query`, `propagate_changes`, `publish_cell_changes`. Fan-out references: `cells/memo.mbt:422`, `cells/hybrid_memo.mbt:121`, `cells/push_reactive.mbt:63`, `cells/push_effect.mbt:39`, `cells/signal.mbt:227`, `cells/accumulator.mbt:403`.
  - **No wrapper:** method is a trivial accessor OR called from only one or two internal sites. Drop the wrapper; call-sites migrate to `@kernel.foo(rt.core, ...)`. Applies to most subscriber helpers, dispatch helpers, internal traversal primitives.

  This shrinks `cells/runtime.mbt` materially and makes "what is public API" legible by inspection, without forcing every internal call-site into the verbose form.

## Rejected Alternatives

- **Kernel as top-level package.** Rejected: expands public API surface for zero user benefit.
- **Kernel methods on Runtime, algorithms as private helpers.** Rejected: no independent test surface for kernel; Runtime remains the only entry point.
- **Move Runtime into kernel.** Rejected: users expect Runtime to live with public handles; facade re-export would become awkward.
- **Move SlotMeta into kernel or types/.** Rejected: SlotMeta is accumulator-implementation data; the SlotSnapshot trait is the minimal boundary.
- **Single big-bang PR.** Rejected: ~2000-line boundary shift; bisection + review both fail at that size.
- **Defer SlotSnapshot, accept verify keeps reading Runtime fields.** Rejected: forces an "engine reads cell-kind-specific fields" exception that undermines the whole separation.

## Invariants Preserved

- **I1. Public API parity.** `pkg.generated.mbti` shows only additions (new kernel `.mbti`). No Runtime/Signal/Memo/etc. signature change.
- **I2. Behavior parity.** All existing tests pass without modification.
- **I3. Engine isolation extended, not weakened.** pull/push/datalog sibling-isolation rule stays; kernel added as an importer-only exception. Kernel may branch on `CellRef` variants (defined in `internal/shared/`); the boundary forbids kernel depending on `cells/`-only state (`SlotMeta`, handles) and on `cells/` imports, not on cell-kind awareness.
- **I4. Callback-snapshot-before-propagation** (from 2026-04-16 coordinator-routing plan). Kernel owns the full `propagate_changes → fire_on_change` sequence.
- **I5. Subscriber management + push-reachable accounting co-located** (hard constraint, 2026-04-19 audit). Both in `kernel/dispatch.mbt` or adjacent files; no cross-file split.
- **I6. Memo inner's forgiving-repair untouched.** Stays in `cells/memo.mbt`. Reads `rt.core.tracking.stack.is_empty()` via field access; TrackingState's `pub(all)` fields make this work across the package boundary.
- **I7. Benchmarks within ±2%** per stage on tracked paths vs Stage 0 baseline.

## Staged Migration

Each stage = one PR. Green `moon check && moon test && moon bench --release` before next stage.

### Stage 1 — Kernel skeleton

- [ ] Create `cells/internal/kernel/moon.pkg` with imports listed in "Package Layout → kernel/moon.pkg."
- [ ] Add `@kernel` import to `cells/moon.pkg`.
- [ ] One dummy `pub fn` in kernel so `moon check` passes (removed in Stage 2).
- [ ] Update `CLAUDE.md` (incr root) package map to mention kernel.

**Verification:** `moon check && moon test` green. `scripts/check-engine-isolation.sh` green (script unchanged yet; kernel has no dependents).

### Stage 2 — State types + SlotSnapshot trait

- [ ] Move to `kernel/state.mbt`: `RevisionState`, `TrackingState`, `BatchState`, `PullState`, `PushState`, `DatalogState`, `RuntimeCore`, `PropagationPhase` + phase transition helpers `enter_phase` / `leave_phase` (currently `cells/runtime.mbt:241`; referenced from `cells/push_propagate.mbt:129` and `cells/datalog_fixpoint.mbt:30`) and `ActiveQuery` (currently in `cells/tracking.mbt`).
- [ ] Move to `kernel/state.mbt`: the two file-scope `Ref[Int]`s — `next_runtime_id` (cells/runtime.mbt:7) and `current_computing_runtime_id` (cells/runtime.mbt:22). Kernel exposes them via `fn get_current_computing_runtime_id() -> Int`, `fn set_current_computing_runtime_id(Int)`, `fn alloc_runtime_id() -> Int`. Memo's forgiving-repair path in cells/ reads via the getter.
- [ ] Add `pub trait SlotSnapshot` to `cells/internal/shared/cell_meta.mbt` (or a new `slot_snapshot.mbt`) with methods `disposed(Self) -> Bool`, `push_revised_at_for(Self, CellId) -> Revision`.
- [ ] Verify `Array[&SlotSnapshot]` construction in `Runtime::slot_snapshots()` does not allocate per-call — test with a debug counter or read moonc output. If it does, fall back to passing `Array[SlotMeta]` concretely via a narrow `cells/accumulator_bridge.mbt` re-export.
- [ ] Implement `SlotSnapshot` for `SlotMeta` in `cells/accumulator.mbt`. No behavior change.
- [ ] Add `fn Runtime::slot_snapshots(self) -> Array[&SlotSnapshot]` in `cells/runtime.mbt`.
- [ ] All moved types declared `pub(all)` — required for Runtime::new to construct.
- [ ] Delete Stage 1's dummy function.
- [ ] **Move whitebox tests with their subjects:** `cells/soa_wbtest.mbt` → `kernel/soa_wbtest.mbt` (SoA invariants on state types). Tests accessing RuntimeCore internals follow.

**Verification:** `moon check && moon test` green. `moon info && moon fmt` produce no `.mbti` diff beyond import rewiring. Benchmarks within ±1% (pure file move; no semantic change).

### Stage 3 — Algorithms + dispatch helpers (leaf-first)

One PR; multiple commits inside, each commit is one functional group moving. Order matters — each move's callees must already be in kernel.

**Ordering (strict):**

- [ ] **3a. Dispatch helpers first.** Move to `kernel/dispatch.mbt` as free functions: `validate_cell_soft`, `cell_id_for`, `is_cell_disposed`, `get_changed_at`, `get_durability`, `get_subscribers`, `add_subscriber`, `remove_subscriber`, `push_contribution`, `collect_reachable_cells`, `adjust_push_reachable`, `cell_id_at`. Per D8, drop Runtime wrappers for internal-only helpers; keep wrappers for those reachable via public API.
- [ ] **3b. `cycle.mbt`.** Move `CycleError::from_path(rt, path, id)` body to `kernel/cycle.mbt` as `construct_cycle_error(cell_ops, path, closing)`. Existing `cells/cycle.mbt` becomes a thin forwarder or is deleted if no cells/ call-site remains.
- [ ] **3c. `subscriber_diff.mbt`.** Move `diff_and_update_subscribers` to `kernel/subscriber_diff.mbt`. Move `cells/subscriber_diff_wbtest.mbt` + `cells/subscriber_link_wbtest.mbt` + `cells/push_reachable_wbtest.mbt` → `kernel/`. **Ordered before tracking because `finish_tracking` calls `diff_and_update_subscribers` (cells/tracking.mbt:154); leaf-first requires the callee to move first.**
- [ ] **3d. `tracking.mbt`.** Move `push_tracking`, `pop_tracking`, `record_dep`, `check_cross_runtime`, `finish_tracking`, plus ActiveQuery-manipulation helpers to `kernel/tracking.mbt`. ActiveQuery itself already moved in Stage 2. Move `cells/tracking_wbtest.mbt` → `kernel/tracking_wbtest.mbt`.
- [ ] **3e. `verify.mbt`.** Move `pull_verify`, `maybe_changed_after`, in-progress-path helpers. Signature takes `slot_snapshots : Array[&SlotSnapshot]` per D4. `CycleError` construction uses the kernel helper from 3b. Move `cells/verify_wbtest.mbt` + `cells/verify_path_test.mbt` with it (path test is blackbox; keep blackbox test in place if it works through Runtime only).
- [ ] **3f. `push_propagate.mbt`.** Move `push_propagate_from`. Uses subscriber_diff + dispatch helpers already in kernel.
- [ ] **3g. `fixpoint.mbt`.** Move `run_fixpoint` + rule firing. **Not self-contained before Stage 4:** `fixpoint()` ends with `publish_cell_changes` (cells/datalog_fixpoint.mbt:107), which stays on Runtime until Stage 4. Keep a thin `Runtime::fixpoint` public wrapper whose body calls `@kernel.run_fixpoint(...)` and then `self.publish_cell_changes(...)`. When Stage 4 moves `publish_cell_changes` to kernel, the wrapper collapses to `@kernel.run_fixpoint(...)` end-to-end.

**Per-sub-step verification:**
- `moon check && moon test` green.
- `moon bench --release` delta ≤ 2% on tracked hot paths vs Stage 0 baseline.
- If a sub-step exceeds 2%, stop: diagnose (parameter-passing overhead? MoonBit inliner not taking? field-access pattern?). Common fixes: batch state refs into one sub-struct to reduce param count; mark hot inner fns for inlining hints if MoonBit supports. If fix blocks on compiler behavior, document and land the sub-step as an opt-out (keep wrapper that inlines the body) while proceeding with other sub-steps.

**Docs update inline with this stage:** `docs/design/internals.md` File Map section — update "cells/" entries that now describe moved-to-kernel pieces.

### Stage 4 — Coordinator primitives

- [ ] Move to `kernel/propagate.mbt`: `propagate_changes`, `publish_cell_changes`, `fire_on_change`.
- [ ] Move to `kernel/batch.mbt`: `commit_batch`. It now calls `@kernel.propagate_changes` directly (no longer `self.propagate_changes`).
- [ ] **`dispose_cell` coordinator stays in `cells/runtime.mbt`.** `CellLifecycle::dispose_cell(self, rt : Runtime, cell_id)` is defined in `cells/cell_ops.mbt:52` and takes a full `Runtime`; impls in `cells/*_lifecycle.mbt` read runtime helpers and runtime-owned fields (`cells/pull_memo_lifecycle.mbt:8`, `cells/push_lifecycle.mbt:5`, `cells/datalog_lifecycle.mbt:8`). Retyping the trait to `dispose_cell(self, core, cell_lifecycle, ...)` would cascade through all 4 lifecycle files and is out of R1 scope.
  - Move the coordinator's pure-state bits into `kernel/dispose.mbt`: `validate_cell_for_dispose(core, cell_id)` (runtime-id + disposed-guard) + `drop_gc_root(core, cell_id)`. `Runtime::dispose_cell` remains in `cells/runtime.mbt` as a 4-line orchestration that calls the kernel validator, calls `self.guard_dispose(...)` (which moves to kernel per below), then dispatches `self.core.cell_lifecycle[cell_id.id].dispose_cell(self, cell_id)`.
  - `guard_dispose` body (pure coordinator over `phase` and `tracking.stack`, `cells/runtime.mbt:713`) moves to `kernel/dispose.mbt` as `check_dispose_guard(core)`.
  - Per-kind `CellLifecycle::dispose_cell` impls **stay in** `cells/*_lifecycle.mbt` unchanged. Trait retype is deferred — revisit in a future R-track if the CellLifecycle(Runtime, ...) coupling becomes a real driver.
- [ ] Move to `kernel/gc.mbt`: `gc`, `collect_gc_roots`, `mark_reachable`, `gc_sweep`, `add_gc_root`, `remove_gc_root`.
- [ ] Keep public Runtime wrappers (per D8): `Runtime::dispose_cell`, `Runtime::dispose_rule`, `Runtime::gc`, `Runtime::set_on_change`, `Runtime::clear_on_change`, `Runtime::batch` (the public batch entry).
- [ ] Move whitebox tests with their subjects: `cells/batch_wbtest.mbt` → `kernel/`, `cells/dispose_test.mbt` if whitebox; `cells/gc_test.mbt` → kernel/ only if whitebox (keep blackbox in cells/).

**Verification:** Full test suite. **Ordering-sensitive tests get explicit attention:** `cells/on_change_test.mbt`, `cells/callback_test.mbt`. Run manually; inspect for ordering regressions in per-cell-before-global callback invariant (I4). Codex review of Stage 4 PR before merge (callback invariant is the single most fragile piece in this refactor).

Benchmarks within I7 threshold.

### Stage 5 — Enforce boundary + wrapper cleanup

- [ ] Update `scripts/check-engine-isolation.sh`: kernel can import pull/push/datalog/shared; no cells/internal/* except kernel's own imports; only top-level cells/*.mbt may import @kernel.
- [ ] Run the script; any violation is a design bug (not a script-loosening opportunity). Investigate and fix at the violation.
- [ ] Sweep `cells/runtime.mbt` for leftover wrappers that aren't public API (per D8 policy). Drop them; migrate call-sites to `@kernel.*` directly.
- [ ] Run `moon ide outline` on `cells/runtime.mbt` and compare the public surface against pre-R1 baseline — must match exactly.

**Verification:** Full suite + script. `cells/runtime.mbt` line count ≤500 (target; ≤600 acceptable).

### Stage 6 — Documentation + archive

- [ ] Update `docs/design/internals.md` sections "File Map," "Architecture Analysis (2026-04-16)," and "Engine isolation (2026-04-18)" to describe kernel/ and the new boundary rules.
- [ ] Update `docs/README.md` index (package tree, this plan's entry moves to archive).
- [ ] Update `CLAUDE.md` (incr root) package map.
- [ ] Archive this plan: `git mv docs/plans/2026-04-21-r1-engine-package-split.md docs/archive/completed-phases/`.
- [ ] Update memory: rewrite `project_architecture_analysis.md` to reflect kernel split; note that Stage 6 engine-extraction was completed *because* the user overrode the driver-gate, not because a driver appeared.

## Testing Strategy

- **Existing tests remain canonical.** R1 is a pure structural refactor; no new behavior tests.
- **Whitebox tests migrate with their subjects.** Stage 2 moves `soa_wbtest.mbt`; Stage 3 moves `tracking_wbtest.mbt`, `subscriber_diff_wbtest.mbt`, `subscriber_link_wbtest.mbt`, `push_reachable_wbtest.mbt`, `verify_wbtest.mbt`; Stage 4 moves `batch_wbtest.mbt` (and whitebox portions of dispose/gc tests). Blackbox tests (those that only touch `@incr` public API) stay in cells/ as integration tests.
- **New kernel-direct whitebox tests added opportunistically.** Each moved algorithm gets (or retains) at least one whitebox test that calls the kernel fn directly with synthetic state. Purpose: isolate kernel regressions from handle regressions in future bisection.
- **Benchmarks:** baseline captured in Stage 0; every Stage 3 sub-step and Stage 4 re-runs `moon bench --release` and diffs vs baseline. Regression >2% on any tracked path blocks the sub-step.

## Risks and Mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Benchmark regression from extra parameter passing (multiple state refs per call) | Medium | High | Per-algorithm bench gate in Stage 3. If MoonBit inliner doesn't close the gap, batch state refs into small structs; as last resort, keep the wrapper with the body inlined for a hot path. |
| R2 | Callback-snapshot invariant (I4) broken during Stage 4 | Low | High | Codex review on Stage 4 PR. Explicit ordering tests in `callback_test.mbt` + `on_change_test.mbt`. |
| R3 | Kernel accidentally imports cells/ (creates cycle) | Low | Medium | `check-engine-isolation.sh` in CI. Stage 5 runs it explicitly. |
| R4 | `Runtime::slot_snapshots()` allocates a fresh `Array[&SlotSnapshot]` per call | Medium | Medium | Not the vtable cost — that's one indirection over HashMap+recursive verify, won't dominate. The real risk is per-call array materialization. Stage 2 verifies zero-copy construction; if forced, fall back to `Array[SlotMeta]` concretely via a narrow `cells/accumulator_bridge.mbt` re-export. |
| R5 | `next_runtime_id` / `current_computing_runtime_id` global relocation breaks memo's forgiving-repair path (I6) | Low | High | Memo reads via kernel-exposed getter; getter returns same value as direct Ref read. Regression would appear in `cycle_test.mbt` + panic-tests. Codex review Stage 2. |
| R6 | `pub(all)` state structs in kernel leak field access to pull/push/datalog siblings | Low | Low | Siblings can't import kernel per D6 (enforced by script). Language-level leakage is theoretical, not operational. |
| R7 | Whitebox test migration introduces visibility errors | Medium | Low | `moon check` catches at the stage where the move happens. Each stage that moves a wbtest verifies the test still compiles and runs. |
| R8 | 7-stage PR chain exceeds review bandwidth | High | Medium | Stages 1+2 could merge if Stage 2's test-file moves aren't too disruptive; keep them separate by default. Author cross-links stages in PR descriptions. |
| R9 | Stage 3 sub-step regression blocks other sub-steps | Medium | Medium | Sub-steps within Stage 3 are independently landable as commits; if 3e (verify) regresses, 3f and 3g can still proceed on the branch and the verify fix lands as a follow-up commit before Stage 3 merges. |

## Out of Scope

- **R2 — Runtime decomposition into services.** Separate plan. Must follow R1.
- **R3 — `MemoCommitPhase` trait.** Separate plan. Accumulator stays as Runtime fields + named helpers.
- **R4 — `RuntimeRegistry`.** Separate plan. The two file-scope `Ref[Int]`s move to kernel as-is in Stage 2.
- **R5 — Relocate Accumulator out of `cells/`.** Separate plan. Accumulator and SlotMeta stay in `cells/accumulator.mbt`.
- **R6 — Retire `pipeline/`.** Independent; can run in parallel with R1 (disjoint packages).
- **R7 — Algorithms as fully pure functions** (return change descriptions; lift mutation). R1 delivers the naturally-entailed version: kernel fns mutate through explicit state refs. Full purity is a further refactor.

## Done Criteria

- [ ] All 6 stages merged (Stages 1–6, not counting Stage 0 prerequisites).
- [ ] `cells/internal/kernel/` exists with the target file layout.
- [ ] `cells/runtime.mbt` ≤500 lines (target; ≤600 acceptable).
- [ ] `scripts/check-engine-isolation.sh` enforces kernel boundary.
- [ ] Benchmark regression across all tracked paths ≤ 2% cumulative vs Stage 0 baseline.
- [ ] `pkg.generated.mbti` diff shows only additions (new kernel `.mbti`) + removal of now-deleted-wrapper private symbols. No public API signature change.
- [ ] This plan archived; memory and internals.md refreshed.

## Cost Estimate

Honest range across all stages, focused-effort:

| Stage | Optimistic | Realistic |
|---|---|---|
| 0 (prerequisites) | 3 hours | 1 day (Codex review + audits) |
| 1 (skeleton) | 1 hour | 1 hour |
| 2 (state + SlotSnapshot) | 4 hours | 1 day (test migration adds friction) |
| 3 (algorithms + dispatch, 7 sub-steps) | 1.5 days | 3 days (bench regression diagnosis) |
| 4 (coordinator primitives) | 1 day | 1.5 days (callback-invariant scrutiny) |
| 5 (boundary + cleanup) | 4 hours | 1 day |
| 6 (docs + archive) | 2 hours | 3 hours |

**Total: 4–6 working days of focused effort across ~6 PRs.** Stage 3 is the single largest uncertainty; if MoonBit's inliner consistently closes parameter-passing overhead, Stage 3 runs short. If two or more algorithms need wrapper-with-inline-body workarounds, it runs long.

## Change Log

- **v3 (2026-04-24):** Stage 0 artifacts landed; Codex review folded in. (1) `SlotSnapshot::push_revised_at()` → `push_revised_at_for(CellId)` — the revision is per-memo, not slot-wide. (2) Stage 3c/3d swapped — subscriber_diff moves first because `finish_tracking` calls it. (3) Stage 3g keeps a `Runtime::fixpoint` wrapper until Stage 4 moves `publish_cell_changes` to kernel. (4) Stage 4 dispose coordinator stays in `cells/runtime.mbt` — `CellLifecycle::dispose_cell(Runtime, ...)` retype is out of R1 scope; only pure-state bits (`validate_cell_for_dispose`, `drop_gc_root`, `check_dispose_guard`) move to `kernel/dispose.mbt`. (5) Boundary statement narrowed: kernel may branch on `CellRef`; it just can't depend on `SlotMeta`/handles or import `cells/`. (6) D8 softened — semantic internal wrappers kept for high-fan-out protocol verbs (`pull_verify`, tracking begin/end/finish, `top_active_query`, `propagate_changes`, `publish_cell_changes`). (7) R4 risk re-scoped — `slot_snapshots()` allocation is the real risk, not vtable dispatch cost. (8) Stage 2 adds `enter_phase`/`leave_phase` to state move list explicitly. Stage 0 checklist marked complete; links to the three artifacts added.
- **v2 (2026-04-21):** Reordered Stage 3 leaf-first; moved batch from Stage 3 to Stage 4 (depends on propagate_changes); merged dispatch-helpers stage into Stage 3; added Stage 0 prerequisites (Codex review, benchmark baseline, dispose audit, ActiveQuery audit); added `SlotSnapshot` trait resolution for the verify/accumulator coupling (D4); explicitly scheduled whitebox test migration with subjects; named `next_runtime_id` + `current_computing_runtime_id` in Stage 2; added D8 wrapper economy; honest 4–6 day estimate; docs updates inline per stage.
- **v1 (2026-04-21):** Initial draft (superseded).
