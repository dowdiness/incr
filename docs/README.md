# Documentation Index

Documentation for the `incr` incremental computation library. This page is an
index: one line per document, details in the documents themselves.

---

## Start Here

New to `incr`? Read these in order:

1. [Getting Started](getting-started.mbt.md) — step-by-step tutorial from your first `Input` to batches and watches
2. [Core Concepts](concepts.mbt.md) — inputs, derived values, revisions, durability, backdating
3. [Cookbook](cookbook.mbt.md) — practical patterns and anti-patterns
4. [API Reference](api-reference.mbt.md) — common public types, methods, and helpers (not exhaustive; the `.mbti` files in each package are authoritative)

Each guide has a checked literate-test companion that pins its behavior with
`moon test`: [concepts_examples](concepts_examples.mbt.md),
[cookbook_examples](cookbook_examples.mbt.md),
[api_reference_examples](api_reference_examples.mbt.md), and
[target_api_examples](target_api_examples.mbt.md), and [expr_examples](expr_examples.mbt.md) (README / getting-started / Expr formula
snippets).

## Architecture

- [Architecture](architecture.md) — package responsibility map, four execution modes (pull / push / hybrid / Datalog), key types and invariants, extension points

## Examples

- [Live Typed Spreadsheet](https://typed-spreadsheet.pages.dev) — editable browser demo; trace panels show recomputed, changed, and unchanged formula cells
- [Typed Spreadsheet package](../examples/typed_spreadsheet/README.mbt.md) — runtime-checked example worksheet boundary, formula evaluation, recompute traces
- [Typed Spreadsheet Rabbita demo](../examples/typed_spreadsheet_rabbita_demo/README.md) — local browser-demo build and deployment notes
- [incr_tea 7GUIs stress test](../examples/incr_tea_7guis/README.md) — browser stress-test package covering the seven 7GUIs tasks with the experimental `incr_tea` renderer
- Full example list: [`examples/README.md`](../examples/README.md)

## Performance

- [Benchmarks](performance/benchmarks.md) — microbenchmark results for core operations (input, derived, reachable-derived, batch)
- [Snapshot roster](performance/README.md) — all dated measurement records, one line each
- [2026-07-14 Retention baseline](performance/2026-07-14-retention-baseline.md) — forgotten pull/eager lifecycle costs, same-root push-gate activation, and disposal/GC controls

Performance docs are dated snapshots: new measurements go in new files, and
old files are never updated.

---

## Contributor / Deep Design

For contributors and advanced users who want to understand or modify `incr`.

**How it works:**

- [Internals](design/internals.md) — verification algorithm, backdating, type erasure, SoA storage, push propagation
- [API Design Guidelines](design/api-design-guidelines.md) — design philosophy and principles behind the public API
- [Comparison with alien-signals](design/comparison-with-alien-signals.md) — trade-offs versus alien-signals-style reactive frameworks
- [Comparison with salsa](design/comparison-with-salsa.md) — shared firewall core, three divergences, and a backdating deep-dive

**Implementation specs** ([design/specs/](design/specs/)) — written-ahead designs for individual subsystems:

- [2026-04-20 Architecture Assessment](design/specs/2026-04-20-architecture-assessment.md) — why no structural redesign is warranted; reopen criteria for T1b/T3
- [2026-05-21 Ideal API facades and read semantics](design/specs/2026-05-21-ideal-api-facade-read-semantics.md) — target facade shape and strict/permissive read contracts
- [2026-05-25 `Expr[T]` Formula API](design/specs/2026-05-25-expr-formula-api.md) — proposed lazy formula layer over target facades
- [2026-05-26 Build-oriented boundary design](design/specs/2026-05-26-build-trait-boundaries.md) — Build-systems-à-la-carte application boundaries on `Input`/`Derived`/`DerivedMap`
- [2026-05-26 Internal evaluation boundaries](design/specs/2026-05-26-internal-rebuild-boundaries.md) — runtime-evaluation state-machine seams without public scheduler traits
- [2026-05-28 Static Derived Public-Surface Options](design/specs/2026-05-28-static-derived-public-options.md) — fixed-dependency fast-path API options; resolved keep-private by the 2026-06-01 ADR
- [2026-05-28 Honest Read-Error Ownership](design/specs/2026-05-28-honest-read-error-ownership.md) — graph failures → read channel, domain failures → value, defects → abort
- [2026-06-05 `AcceptedDerived`](design/specs/2026-06-05-committed-derived.md) — success-gated authoring primitive retaining the last accepted value
- [2026-06-05 Typed Spreadsheet bounded trace contract](design/specs/2026-06-05-typed-spreadsheet-bounded-trace-contract.md) — caller-bounded formula traces (#179)
- [2026-06-25 `Program::stateful` / `stateful_cmd`](design/specs/2026-06-25-program-stateful-design.md) — boilerplate-hiding constructors for mutable-model TEA apps
- [2026-07-03 Workspace Boundary Assessment](design/specs/2026-07-03-workspace-boundary-assessment.md) — core layering re-verified healthy; pressure moved to the examples/facade seams; staged boundary plan

**Project direction:**

- [Roadmap](roadmap.md) — phased future direction
- [TODO](todo.md) — contributor task list organized by priority
- [incr_tea backlog](../incr_tea/docs/backlog.md) — task list for the `dowdiness/incr_tea` module (retargeted TEA issues + agenda)
- [Active plans](plans/) — concrete implementation plans for upcoming work:
  - [2026-05-26 Evaluation strategy refactor](plans/2026-05-26-evaluation-strategy-refactor.md) — internal sealed scheduler/rebuilder strategies
  - [2026-05-28 Typed Spreadsheet responsibility boundary](plans/2026-05-28-typed-spreadsheet-boundary.md) — app-vs-library split before spreadsheet-specific sugar
  - [2026-06-08 AcceptedDerived BackdateEq tier](plans/2026-06-08-accepted-derived-backdate-eq-tier.md) — revision-gated acceptance for non-`Eq` candidates; downstream validation pending
  - [2026-06-09 Composable runtime hooks](plans/2026-06-09-composable-runtime-hooks.md) — multi-listener registries (#210); see the [ADR](decisions/2026-06-09-composable-runtime-hooks.md)
  - [2026-06-24 Typed Spreadsheet cross-root locality](plans/2026-06-24-typed-spreadsheet-cross-root-locality.md) — multi-root spreadsheet with per-root recompute instrumentation
  - [2026-06-25 `Program::stateful` implementation plan](plans/2026-06-25-program-stateful.md) — 3-task SDD plan (#287)
  - [2026-07-05 Public API boundary cleanup + `Expr[T]` track](plans/2026-07-05-public-api-boundary-cleanup.md) — deprecations + `Scope::watch`, types-package cleanup, error-channel consistency (0.14.0), then the `Expr[T]` formula layer
  - [2026-07-14 Duplix-informed retention benchmarks](plans/2026-07-14-duplix-retention-benchmarks.md) — measure forgot-to-dispose costs (8-scenario matrix); gated follow-ups: detachable per-key scopes, `KeyedInput` Map-diff facade
  - [2026-07-14 Machine composition evidence driver](plans/2026-07-14-machine-composition-evidence-driver.md) — test pure parent/child composition and aggregate `Program::stateful_cmd` first; measure before proposing a `Machine` type or per-key reactive ownership

**Research notes — exploratory, not implemented:**

- [2026-07-14 Bonsai-informed `incr` core direction](research/2026-07-14-bonsai-informed-incr-core-direction.md) — prioritize historical-volume attribution and live-graph lifetime guarantees; keep dynamic ownership, graph snapshots, safe commits, and static lowering behind explicit evidence gates
- [2026-07-14 Machine semantics start gates](research/2026-07-14-machine-layer-start-gates.md) — treat pure functions and aggregate Program composition as the baseline; gate new abstraction types, per-key graphs, and generative UI on concrete evidence
- [Next-sessions Runtime Roadmap](research/next-sessions-runtime-roadmap.md) — onboarding + invariants + backlog template for Loom + Canopy integration sessions
- [Incremental TEA direction](research/incr-tea-ui-direction.md) — positions `incr_tea` (now module `dowdiness/incr_tea`) as a semantic incremental rendering substrate, with follow-up issue map
- [Constructive Traces Feasibility](research/constructive-traces-feasibility.md) — keep revision verifying traces as the default; investigate static/applicative APIs first
- [Multi-Mode App Ideas](research/multi-mode-app-ideas.md) — app concepts combining pull / push / hybrid / Datalog modes
- [Semantic Interning](research/semantic-interning.md) — design exploration for revision-aware `InternTable[T]`
- [Reactive Collections — Research Summary](research/reactive-collections.md) — survey of delta / per-item / nominal approaches
- [`ReactiveMap[K, V]` — Design Sketch](research/reactive-map-design.md) — per-key memoized map with observable key set
- [`Relation::subscribe_delta` — Design Sketch](research/relation-delta-observer-design.md) — opt-in delta observation on Datalog relations

## Decisions (ADRs)

Architecture Decision Records — the *why* behind significant design choices.
The one-line summaries below are hooks; the decision, rationale, and status
live in each ADR.

| Date | Decision |
|------|----------|
| [2026-04-20](decisions/2026-04-20-accumulator-api.md) | Accumulator API: side-channel collector with push-set incremental invalidation |
| [2026-04-26](decisions/2026-04-26-r2-runtime-decomposition-deferred.md) | R2 runtime-services decomposition: deferred indefinitely (no driver) |
| [2026-04-26](decisions/2026-04-26-modal-runtime-split-not-warranted.md) | Per-mode Runtime split: investigation closed, not warranted |
| [2026-05-17](decisions/2026-05-17-async-at-the-edges.md) | Async-at-the-edges with `moonbitlang/async`: no library changes required |
| [2026-05-17](decisions/2026-05-17-t3-runtime-registry-gated.md) | T3 `RuntimeRegistry`: design recorded, commissioning gated on a real driver |
| [2026-05-17](decisions/2026-05-17-t1b-memo-commit-phase.md) | T1b `MemoCommitPhase`: priv commit-path extension trait, accepted |
| [2026-05-17](decisions/2026-05-17-memo-event-observation.md) | `Runtime::on_derived_event`: driver-facing recompute event observation (pull-mode only) |
| [2026-05-21](decisions/2026-05-21-public-api-ideal-naming.md) | Ideal public API naming: `Input`/`Derived`/… facades; `Result` reads + `_or_abort` shortcuts |
| [2026-05-30](decisions/2026-05-30-reachable-derived-differentiate-or-collapse.md) | ReachableDerived — differentiate or collapse: **Deferred**; re-open trigger recorded |
| [2026-06-01](decisions/2026-06-01-static-derived-public-surface.md) | Static Derived fast path stays package-private until a concrete driver appears |
| [2026-06-01](decisions/2026-06-01-workspace-layout.md) | Workspace layout: `moon.work` root, publishable module under `incr/`, checked docs member |
| [2026-06-02](decisions/2026-06-02-typed-spreadsheet-runtime-checking.md) | Typed Spreadsheet formula checking stays runtime-checked at the example boundary |
| [2026-06-02](decisions/2026-06-02-typed-spreadsheet-tombstone-lifecycle.md) | Typed Spreadsheet deleted-cell tombstones: stable presence anchors + explicit compaction |
| [2026-06-09](decisions/2026-06-09-composable-runtime-hooks.md) | Composable runtime hooks: multi-listener registries behind source-compatible singleton APIs |
| [2026-06-17](decisions/2026-06-17-incr-tea-inactive-root-activation-policy.md) | Incremental TEA inactive-root activation: manual-first hybrid (#280) |
| [2026-07-03](decisions/2026-07-03-incr-tea-module-identity.md) | `incr_tea` module identity: core-feedback framework, facade-only imports, own backlog |
| [2026-07-08](decisions/2026-07-08-evaluation-strategy-composition-contract.md) | Evaluation-strategy composition contract: purity axis, cross-engine legality table, two-chokepoint enforcement (phase guard + #368), fold reserved |
| [2026-07-14](decisions/2026-07-14-retention-followup-tracks-gated.md) | Retention follow-up tracks (per-key Scope ownership, `KeyedInput` facade) stay gated — no consumer; investigate retained-volume cost (#399) first |

---

## Historical & Archive

> **Do not read files in this section unless you need historical context.** These documents describe past design iterations, completed work, and point-in-time analyses. The code is the source of truth; where archive material and current docs disagree, trust the code and the current docs.

### Completed plans & retired designs

Large historical collection under [`archive/`](archive/) covering completed plans, rejected alternatives, past refactors, and earlier unified design specs. Selected entries:

| Document | Topic |
|----------|-------|
| [archive/plans/](archive/plans/) | Shipped implementation plans (dispose/GC layers, runtime modularization, stage-5 internal split, T1b commit-phase refactor) |
| [archive/completed-phases/](archive/completed-phases/) | Older completed phases (datalog primitives, cells simplification, accumulator API spec, R1 engine package split with stage notes, 2026-05-21 ideal API rename migration plan + 2026-05-23 Phase 3a migration-guide/codemod plan — both superseded by the #345 direct removal in 0.13.0) |
| [archive/incr-unified-design.md](archive/incr-unified-design.md) | Unified reactive runtime design (SoA + multi-mode) |
| [archive/2026-04-08-dispose-gc-design.md](archive/2026-04-08-dispose-gc-design.md) | Dispose/GC design — all 5 layers complete (PRs #28–#33) |
| [archive/api-updates.md](archive/api-updates.md) | Summary of past API documentation changes |

---

## External Resources

- [Library README](../incr/README.mbt.md) — project overview and quick start
- [CLAUDE.md](../CLAUDE.md) — contributor/AI-agent guidance on commands and architecture
- Source code: [`../incr/`](../incr/) module packages
- Tests: `*_test.mbt` and `*_wbtest.mbt` files under `../incr/` and example modules
