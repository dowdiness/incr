# Documentation Index

Documentation for the `incr` incremental computation library.

---

## Start Here

New to `incr`? Read these in order:

1. [Getting Started](getting-started.mbt.md) — step-by-step tutorial from your first signal to advanced patterns
2. [Core Concepts](concepts.mbt.md) — signals, memos, revisions, durability, backdating
3. [Checked Concepts Examples](concepts_examples.mbt.md) — literate tests for high-value concepts behavior
4. [Cookbook](cookbook.mbt.md) — practical patterns and anti-patterns
5. [Checked Cookbook Examples](cookbook_examples.mbt.md) — literate tests for high-value cookbook patterns, including target facades, long-lived authoring pipelines, scoped watches, accumulators, and memo events
6. [Checked Target API Examples](target_api_examples.mbt.md) — literate tests mirroring the README and getting-started target facade, callback, and batch examples
7. [Checked API Reference Examples](api_reference_examples.mbt.md) — literate tests covering target facades from the API reference (`Derived`, `DerivedMap`, `ReachableDerived`, `MapRelation`, `Scope` / `RuntimeContext`, `CycleError`) plus compatibility accumulator behavior

## API Reference

- [API Reference](api-reference.mbt.md) — common public types, methods, and helpers (not exhaustive; the `.mbti` files in each package are authoritative)
- [Typed Spreadsheet API](typed-spreadsheet.mbt.md) — typed spreadsheet boundary, installation APIs, post-change recompute traces, and the CLI demo entry point
- [Checked Concepts Examples](concepts_examples.mbt.md) — companion literate tests pinning high-value behavior from the concepts guide
- [Checked API Reference Examples](api_reference_examples.mbt.md) — companion literate tests pinning executable reference snippets and compatibility accumulator behavior
- [Checked Cookbook Examples](cookbook_examples.mbt.md) — companion literate tests pinning high-value cookbook patterns, including target facades, long-lived authoring pipelines, scoped watches, accumulators, and memo events
- [Architecture](architecture.md) — package responsibility map, four execution modes (pull / push / hybrid / Datalog), key types and invariants, extension points

## Performance

- [Benchmarks](performance/benchmarks.md) — microbenchmark results for core operations (signal, memo, hybrid, batch). Dated snapshots; newer numbers go in new files.
- [2026-04-21 Pre-R1 Baseline](performance/2026-04-21-pre-r1-baseline.md) — frozen reference for R1 Stage 3 regression gate (≤2% per tracked path).
- [2026-04-24 R1 Stage 3 bench](performance/2026-04-24-r1-stage3-bench.md) — Stage 3 comparison vs baseline; all tracked rows within or favorable to ±2% gate.
- [2026-04-26 `memo_restore_on_abort` validation](performance/2026-04-26-memo-restore-on-abort-bench.md) — open-TODO microbench: O(n²) confirmed but constants too small to be actionable at realistic N.
- [2026-05-16 Push-engine link-list port microbench](performance/2026-05-16-push-engine-linklist-microbench.md) — alien-signals-style port investigation closed: measured 1.2–1.5× speedup, deprioritized in favor of higher-leverage targets.
- [2026-05-16 Push-engine cost decomposition](performance/2026-05-16-push-engine-cost-decomposition.md) — strategic ranking of push-engine performance interventions. Chosen direction: per-recompute allocation elimination (tracking-buffer reuse).
- [2026-05-16 Tracking-buffer lazy-allocation result](performance/2026-05-16-tracking-buffer-lazy-alloc.md) — implements the chosen direction. Pool reuse rejected by probe; lazy-allocation alone delivered −15.9% on 1000-fanout (−46 ns/r).
- [2026-05-17 T1b commit-path bench snapshot](performance/2026-05-17-t1b-bench-snapshot.md) — pre-T1b → Phase 1 → Phase 2 pre-fix → Phase 2 + lazy-entry fast-path. Fast-path beats pre-T1b by −25% on no-accumulator recompute fanout by eliminating per-recompute HashSet allocations the old `memo_commit_accumulator_phase` carried unconditionally.
- [2026-05-18 UI-shape benches](performance/2026-05-18-ui-shape-benches.md) — push-engine throughput on UI-shaped workloads (flat / layered / sparse / tree) across wasm-gc + JS. Confirms 60 Hz headroom at 1000 nodes; baseline for any future UI-library work on incr.
- [2026-05-27 Static/applicative Derived fast-path probe](performance/2026-05-27-static-derived-fast-path-probe.md) — lower-bound, integrated, and UI-shape benches for fixed-dependency derived recomputation; records the package-private static path. Public exposure remains closed by the 2026-06-01 ADR.
- [2026-06-01 DSL-shaped authoring pipeline benches](performance/2026-06-01-dsl-authoring-benches.md) — coarse staged `Derived` authoring chain vs per-node `DerivedMap` and sparse `ReachableDerived` inspector variants across wasm-gc + JS.
- [2026-06-01 Graph-editor recompute path benches](performance/2026-06-01-graph-editor-recompute-benches.md) — durable graph/document recomputation vs ephemeral hover, drag preview, and viewport updates; records live-drag and commit-at-end behavior across wasm-gc + JS.

---

## Contributor / Deep Design

For contributors and advanced users who want to understand or modify `incr`.

**How it works:**

- [Internals](design/internals.md) — verification algorithm, backdating, type erasure, SoA storage, push propagation
- [API Design Guidelines](design/api-design-guidelines.md) — design philosophy and principles behind the public API
- [Comparison with alien-signals](design/comparison-with-alien-signals.md) — trade-offs versus alien-signals-style reactive frameworks
- [Implementation specs](design/specs/) — written-ahead design specs for individual subsystems (paired with [plans/](plans/) or already shipped)
- [2026-04-20 Architecture Assessment](design/specs/2026-04-20-architecture-assessment.md) — verified snapshot of current architecture; records why no structural redesign is warranted today and what would justify revisiting T1b (commit-phase trait) and T3 (runtime registry)
- [2026-05-21 Ideal API facades and read semantics](design/specs/2026-05-21-ideal-api-facade-read-semantics.md) — target facade shape and strict/permissive read contracts for the public API rename
- [2026-05-25 `Expr[T]` Formula API](design/specs/2026-05-25-expr-formula-api.md) — proposed lazy formula layer over target facades, with same-runtime validation, explicit constants, and one-cell materialization
- [2026-05-26 Build-oriented boundary design](design/specs/2026-05-26-build-trait-boundaries.md) — ideal Build systems à la carte-inspired application boundaries on top of `Input`, `Derived`, and `DerivedMap`; traits are one seam, not the default
- [2026-05-26 Internal evaluation boundaries](design/specs/2026-05-26-internal-rebuild-boundaries.md) — ideal runtime-evaluation state-machine design for pull verification, push propagation, lifetime, and observation seams without public scheduler traits
- [2026-05-28 Static Derived Public-Surface Options](design/specs/2026-05-28-static-derived-public-options.md) — compares public API options and hard requirements for the measured fixed-dependency `Derived` fast path; resolved by the 2026-06-01 ADR as keep-private-with-reopen-criteria
- [2026-05-28 Honest Read-Error Ownership](design/specs/2026-05-28-honest-read-error-ownership.md) — three-way split of read failures (graph→read channel, domain→value-as-`Result`, defects→abort/fail); `Derived::fallible`/`DerivedMap::fallible`; `ReadError` migration for target reads and accumulator verifying reads

**Project direction:**

- [Roadmap](roadmap.md) — phased future direction
- [Active plans](plans/) — concrete implementation plans for upcoming work
- [Typed Spreadsheet Responsibility Boundary](plans/2026-05-28-typed-spreadsheet-boundary.md) — app-vs-library responsibility split before adding any spreadsheet-specific sugar
- [Ideal API Rename Migration Plan](plans/2026-05-21-ideal-api-rename-migration.md) — staged compatibility plan for the accepted public API target names
- [Phase 3a Compatibility-to-Facade Migration Spec](plans/2026-05-23-ideal-api-rename-phase3-soak-window.md) — documentation and codemod plan for moving from `Memo`/`HybridMemo`/`MemoMap` to `Derived`/`ReachableDerived`/`DerivedMap` without adding same-receiver bridge methods
- [Evaluation Strategy Refactor Plan](plans/2026-05-26-evaluation-strategy-refactor.md) — staged refactor toward internal sealed scheduler/rebuilder strategies with fixed store/trace contracts and no first-step public pluggability
- [TODO](todo.md) — contributor task list organized by priority

**Research notes — exploratory, not implemented:**

- [Next-sessions Runtime Roadmap](research/next-sessions-runtime-roadmap.md) — shared onboarding + invariants + backlog template for continuing Loom + Canopy integration work across sessions.

- [Constructive Traces Feasibility](research/constructive-traces-feasibility.md) — evaluates Build Systems à la Carte constructive traces for `incr`; recommends keeping revision verifying traces as the default and investigating static/applicative derived APIs first
- [Multi-Mode App Ideas](research/multi-mode-app-ideas.md) — app concepts combining pull / push / hybrid / Datalog modes
- [Semantic Interning](research/semantic-interning.md) — design exploration for revision-aware `InternTable[T]`
- [Reactive Collections — Research Summary](research/reactive-collections.md) — survey of delta / per-item / nominal approaches across Differential Dataflow, Salsa, Adapton, SolidJS, etc.
- [`ReactiveMap[K, V]` — Design Sketch](research/reactive-map-design.md) — per-key memoized map with observable key set
- [`Relation::subscribe_delta` — Design Sketch](research/relation-delta-observer-design.md) — opt-in delta observation on Datalog relations

## Decisions (ADRs)

Architecture Decision Records — the *why* behind significant design choices. Kept short; link to implementation specs for details.

| Date | Decision |
|------|----------|
| [2026-04-20](decisions/2026-04-20-accumulator-api.md) | Accumulator API: side-channel collector with per-memo `push_revised_at` incremental invalidation (local-only scope; verifying reads now use `ReadError`) |
| [2026-04-26](decisions/2026-04-26-r2-runtime-decomposition-deferred.md) | R2 (Runtime → services decomposition): deferred indefinitely. Post-R1 Runtime is 427 LOC of thin delegators; service decomposition would be a wrapper-rename without a driver. |
| [2026-04-26](decisions/2026-04-26-modal-runtime-split-not-warranted.md) | Modal Runtime split (per-mode Runtime types): investigation closed. Runtime::new costs 0.11 µs and unused-mode "luggage" is sub-KB; no concrete X→Y per-mode design wish names a shared-CellId-compatible change. |
| [2026-05-17](decisions/2026-05-17-async-at-the-edges.md) | Async-at-the-edges with `moonbitlang/async`: no library changes required. Function coloring enforces the synchrony contract statically. Supported patterns documented; T3 + JS integration test gated on a real driver. |
| [2026-05-17](decisions/2026-05-17-t3-runtime-registry-gated.md) | T3 (`RuntimeRegistry`): design recorded, commissioning gated on multi-runtime async driver, MoonBit preemption, or observable test failure. Replaces two file-scope `Ref[Int]`s + heuristic forgiving-repair with principled liveness queries. |
| [2026-05-17](decisions/2026-05-17-t1b-memo-commit-phase.md) | T1b (`MemoCommitPhase`): accepted with two design-witness implementors (accumulator shipped, visualization event tap designed). Priv trait; accumulator refactor in T1b's PR; public `Runtime::on_memo_event` API ships with the visualization tap follow-up. Snapshot/restore + CRDT time-travel explicitly deferred. |
| [2026-05-17](decisions/2026-05-17-memo-event-observation.md) | `Runtime::on_memo_event` public API: driver-facing commit-phase event observation. `pub(all) enum MemoEvent` with `EnteringCompute` / `Completed(elapsed_ns, backdated)` / `Aborted(elapsed_ns, error)`. Single listener per runtime; sync callback (async bridged via aqueue). In-tree `EventBroadcastPhaseHook` bridges T1b's trait. Pull-memo only; push/fixpoint/batch events deferred. |
| [2026-05-21](decisions/2026-05-21-public-api-ideal-naming.md) | Ideal public API naming: `Input`, `Derived`, `ReachableDerived`, `EagerDerived`, `DerivedMap`, `InputField`, `Watch`, `RuntimeContext`; `get`/`read` return `Result` for fallible derived reads and aborting shortcuts use `_or_abort`. |
| [2026-05-30](decisions/2026-05-30-reachable-derived-differentiate-or-collapse.md) | ReachableDerived — differentiate or collapse. Spike (typed-spreadsheet driver) found `Derived` ≡ `ReachableDerived` today: identical read paths, identical `push_reachable_count` participation, vestigial `is_hybrid`. Proposes (b) differentiate into a genuine eager-when-reachable memo that recomputes during push propagation + emits unified eval events; fallback (a) collapse/deprecate. Status: **Deferred** (2026-05-31) — interim keep + docs corrected; re-open trigger = a projectional-editor viewport over `core/projection_memo.mbt` needing per-edit change-set observation; sunset to (a) collapse before external-user API stability. |
| [2026-06-01](decisions/2026-06-01-static-derived-public-surface.md) | Static Derived public surface: keep the measured static/applicative fast path package-private. No public `Derived::map*`, `Scope::derived_static*`, compatibility conveniences, or raw installer until an `Expr[T]` lowering need, a measured scope-owned attachment win, or downstream UI wrapper duplication supplies a concrete driver. |

---

## Historical & Archive

> **Do not read files in this section unless you need historical context.** These documents describe past design iterations, completed work, and point-in-time analyses. The code is the source of truth; where archive material and current docs disagree, trust the code and the current docs.

### Completed plans & retired designs

Large historical collection under [`archive/`](archive/) covering completed plans, rejected alternatives, past refactors, and earlier unified design specs. Selected entries:

| Document | Topic |
|----------|-------|
| [archive/plans/](archive/plans/) | Shipped implementation plans (dispose/GC layers, runtime modularization, stage-5 internal split) |
| [archive/plans/2026-05-17-t1b-implementation.md](archive/plans/2026-05-17-t1b-implementation.md) | T1b — `MemoCommitPhase` trait refactor. Three phases shipped; accumulator's three named commit-path calls moved into trait dispatch. See [T1b ADR](decisions/2026-05-17-t1b-memo-commit-phase.md) and [commit-path bench snapshot](performance/2026-05-17-t1b-bench-snapshot.md). |
| [archive/completed-phases/](archive/completed-phases/) | Older completed phases (datalog primitives, cells simplification, accumulator API spec, etc.) |
| [archive/incr-unified-design.md](archive/incr-unified-design.md) | Unified reactive runtime design (SoA + multi-mode) |
| [archive/2026-04-08-dispose-gc-design.md](archive/2026-04-08-dispose-gc-design.md) | Dispose/GC design — all 5 layers complete (PRs #28–#33) |
| [archive/completed-phases/2026-04-21-r1-engine-package-split.md](archive/completed-phases/2026-04-21-r1-engine-package-split.md) | R1 — Split Reactive Kernel from Cells (Stages 0–6 merged 2026-04-24 → 2026-04-25). Companion docs: [Stage 0 audits](archive/completed-phases/2026-04-21-r1-stage0-audits.md), [Stage 0 Codex review](archive/completed-phases/2026-04-21-r1-stage0-codex-review.md), [Stage 2 notes](archive/completed-phases/2026-04-24-r1-stage2-notes.md), [Stage 3 notes](archive/completed-phases/2026-04-24-r1-stage3-notes.md), [Stage 4 notes](archive/completed-phases/2026-04-24-r1-stage4-notes.md). |
| [archive/completed-phases/2026-04-19-accumulator-api-design.md](archive/completed-phases/2026-04-19-accumulator-api-design.md) | Accumulator API spec (shipped 2026-04-20; superseded by the ADR above) |
| [archive/completed-phases/2026-03-03-datalog-primitives.md](archive/completed-phases/2026-03-03-datalog-primitives.md) | Datalog primitives: Relation, Rule, Fixpoint |
| [archive/api-updates.md](archive/api-updates.md) | Summary of past API documentation changes |

---

## External Resources

- [Main README](../README.md) — project overview and quick start
- [CLAUDE.md](../CLAUDE.md) — contributor/AI-agent guidance on commands and architecture
- Source code: root directory `.mbt` files
- Tests: `*_test.mbt` and `*_wbtest.mbt` files
