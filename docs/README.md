# Documentation Index

Documentation for the `incr` incremental computation library.

---

## Start Here

New to `incr`? Read these in order:

1. [Getting Started](getting-started.md) — step-by-step tutorial from your first signal to advanced patterns
2. [Core Concepts](concepts.md) — signals, memos, revisions, durability, backdating
3. [Cookbook](cookbook.md) — practical patterns and anti-patterns

## API Reference

- [API Reference](api-reference.md) — every public type, method, and helper

## Performance

- [Benchmarks](performance/benchmarks.md) — microbenchmark results for core operations (signal, memo, hybrid, batch). Dated snapshots; newer numbers go in new files.
- [2026-04-21 Pre-R1 Baseline](performance/2026-04-21-pre-r1-baseline.md) — frozen reference for R1 Stage 3 regression gate (≤2% per tracked path).
- [2026-04-24 R1 Stage 3 bench](performance/2026-04-24-r1-stage3-bench.md) — Stage 3 comparison vs baseline; all tracked rows within or favorable to ±2% gate.

---

## Contributor / Deep Design

For contributors and advanced users who want to understand or modify `incr`.

**How it works:**

- [Internals](design/internals.md) — verification algorithm, backdating, type erasure, SoA storage, push propagation
- [API Design Guidelines](design/api-design-guidelines.md) — design philosophy and principles behind the public API
- [Comparison with alien-signals](design/comparison-with-alien-signals.md) — trade-offs versus alien-signals-style reactive frameworks
- [Implementation specs](design/specs/) — written-ahead design specs for individual subsystems (paired with [plans/](plans/) or already shipped)
- [2026-04-20 Architecture Assessment](design/specs/2026-04-20-architecture-assessment.md) — verified snapshot of current architecture; records why no structural redesign is warranted today and what would justify revisiting T1b (commit-phase trait) and T3 (runtime registry)

**Project direction:**

- [Roadmap](roadmap.md) — phased future direction
- [Active plans](plans/) — concrete implementation plans for upcoming work
  - [2026-04-21 R1 — Split Reactive Kernel from Cells](plans/2026-04-21-r1-engine-package-split.md) — extract graph-mechanics into `cells/internal/kernel/`; public Runtime methods become thin wrappers or drop entirely (D8 wrapper economy) over kernel free functions. 6 staged PRs, 4–6 days. **Plan v3; Stages 0–3 merged.**
    - [Stage 0 audits](plans/2026-04-21-r1-stage0-audits.md) — dispose_cell flow, ActiveQuery fields, check-engine-isolation.sh extension plan
    - [Stage 0 Codex review](plans/2026-04-21-r1-stage0-codex-review.md) — READY WITH CAVEATS verdict; findings folded into plan v3
    - [Stage 2 execution notes](plans/2026-04-24-r1-stage2-notes.md) — Codex pre-review corrections + updated Stage 2 checklist
    - [Stage 3 execution notes](plans/2026-04-24-r1-stage3-notes.md) — accumulator_snapshots resolution, Codex pre-review corrections, per-sub-step checklists
- [TODO](todo.md) — contributor task list organized by priority

**Research notes — exploratory, not implemented:**

- [Multi-Mode App Ideas](research/multi-mode-app-ideas.md) — app concepts combining pull / push / hybrid / Datalog modes
- [Semantic Interning](research/semantic-interning.md) — design exploration for revision-aware `InternTable[T]`
- [Reactive Collections — Research Summary](research/reactive-collections.md) — survey of delta / per-item / nominal approaches across Differential Dataflow, Salsa, Adapton, SolidJS, etc.
- [`ReactiveMap[K, V]` — Design Sketch](research/reactive-map-design.md) — per-key memoized map with observable key set
- [`Relation::subscribe_delta` — Design Sketch](research/relation-delta-observer-design.md) — opt-in delta observation on Datalog relations

## Decisions (ADRs)

Architecture Decision Records — the *why* behind significant design choices. Kept short; link to implementation specs for details.

| Date | Decision |
|------|----------|
| [2026-04-20](decisions/2026-04-20-accumulator-api.md) | Accumulator API: side-channel collector with per-memo `push_revised_at` incremental invalidation (local-only scope; `raise Failure` error model) |

---

## Historical & Archive

> **Do not read files in this section unless you need historical context.** These documents describe past design iterations, completed work, and point-in-time analyses. The code is the source of truth; where archive material and current docs disagree, trust the code and the current docs.

### Completed plans & retired designs

Large historical collection under [`archive/`](archive/) covering completed plans, rejected alternatives, past refactors, and earlier unified design specs. Selected entries:

| Document | Topic |
|----------|-------|
| [archive/plans/](archive/plans/) | Shipped implementation plans (dispose/GC layers, runtime modularization, stage-5 internal split) |
| [archive/completed-phases/](archive/completed-phases/) | Older completed phases (datalog primitives, cells simplification, accumulator API spec, etc.) |
| [archive/incr-unified-design.md](archive/incr-unified-design.md) | Unified reactive runtime design (SoA + multi-mode) |
| [archive/2026-04-08-dispose-gc-design.md](archive/2026-04-08-dispose-gc-design.md) | Dispose/GC design — all 5 layers complete (PRs #28–#33) |
| [archive/completed-phases/2026-04-19-accumulator-api-design.md](archive/completed-phases/2026-04-19-accumulator-api-design.md) | Accumulator API spec (shipped 2026-04-20; superseded by the ADR above) |
| [archive/completed-phases/2026-03-03-datalog-primitives.md](archive/completed-phases/2026-03-03-datalog-primitives.md) | Datalog primitives: Relation, Rule, Fixpoint |
| [archive/api-updates.md](archive/api-updates.md) | Summary of past API documentation changes |

---

## External Resources

- [Main README](../README.md) — project overview and quick start
- [CLAUDE.md](../CLAUDE.md) — contributor/AI-agent guidance on commands and architecture
- Source code: root directory `.mbt` files
- Tests: `*_test.mbt` and `*_wbtest.mbt` files
