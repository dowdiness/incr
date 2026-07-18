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
- [2026-07-15 Retention cost attribution](performance/2026-07-15-retention-cost-attribution.md) — cross-target 7a/7b reproduction, post-cleanup storage facts, push-free controls, and slot-reclamation no-go for #399
- [2026-07-15 Machine composition follow-up](performance/2026-07-15-machine-composition-follow-up.md) — single-source sequencing and observer-disabled browser timing after PR hardening
- [2026-07-15 Incremental TEA controlled-property reconciliation](performance/2026-07-15-incr-tea-controlled-reconciliation.md) — issue #394 Chromium benchmark of equal-view traversal/getter and mismatch-repair cost; no optimization justified.
- [2026-07-14 Machine composition aggregate evidence](performance/2026-07-14-machine-composition-evidence.md) — aggregate Program semantic-editor structural gates and 64/256-child synchronous JS timing result

Performance docs are dated snapshots: new measurements go in new files, and
old files are never updated.

---

## Contributor / Deep Design

For contributors and advanced users who want to understand or modify `incr`.

**How it works:**

- [Internals](design/internals.md) — verification algorithm, backdating, type erasure, SoA storage, push propagation
- [API Design Guidelines](design/api-design-guidelines.md) — design philosophy and principles behind the public API
- [Comparison with salsa](design/comparison-with-salsa.md) — shared firewall core, three divergences, and a backdating deep-dive

**Implementation specs** ([design/specs/](design/specs/)) — written-ahead design records for individual subsystems. Completed or superseded time-bounded specs are retired under the [documentation retention policy](decisions/2026-06-02-documentation-retention-policy.md) when a durable ADR or performance evidence replaces them; these are not the current backlog; the [roadmap](roadmap.md) decides what is current.

**Current roadmap:**

- [Roadmap](roadmap.md) — canonical current core backlog
- [incr_tea backlog](../incr_tea/docs/backlog.md) — task list for the `dowdiness/incr_tea` module (retargeted TEA issues + agenda)
- [Implementation plans](plans/) — active, time-bounded implementation records; completed plans are deleted under the documentation retention policy.

**Research notes** ([research/](research/)) — exploratory, not implemented. Open these only when a current roadmap item, plan, or ADR calls for them.

- [Bonsai-informed core direction](research/2026-07-14-bonsai-informed-incr-core-direction.md) — gated source of truth for Runtime
  lifetime/ownership/resource-model hypotheses, including the cross-engine
  lifecycle model, retention attribution resolution (#399), and Datalog
  lifecycle evidence

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
| [2026-06-02](decisions/2026-06-02-documentation-retention-policy.md) | Documentation retention: retire archive after triage, keep ADRs durable, require READMEs at entry points |
| [2026-06-09](decisions/2026-06-09-composable-runtime-hooks.md) | Composable runtime hooks: multi-listener registries behind source-compatible singleton APIs |
| [2026-06-17](decisions/2026-06-17-incr-tea-inactive-root-activation-policy.md) | Incremental TEA inactive-root activation: manual-first hybrid (#280) |
| [2026-07-03](decisions/2026-07-03-incr-tea-module-identity.md) | `incr_tea` module identity: core-feedback framework, facade-only imports, own backlog |
| [2026-07-08](decisions/2026-07-08-evaluation-strategy-composition-contract.md) | Evaluation-strategy composition contract: purity axis, cross-engine legality table, two-chokepoint enforcement (phase guard + #368), fold reserved |
| [2026-07-14](decisions/2026-07-14-retention-followup-tracks-gated.md) | Retention follow-up tracks (per-key Scope ownership, `KeyedInput` facade) stay gated — no consumer; #399 attribution completed with slot-reclamation/compaction no-go |
| [2026-07-14](decisions/2026-07-14-machine-composition-domain-functions.md) | Machine composition remains domain-level pure functions; no shared `Machine`/core API without repeated driver evidence |
| [2026-07-15](decisions/2026-07-15-incr-tea-controlled-form-properties.md) | Incremental TEA controlled form properties: closure-free values, post-order select repair, and explicit boolean control |
| [2026-07-18](decisions/2026-07-18-datalog-relation-rule-lifecycle.md) | Datalog relation-rule lifecycle: live rules pin declared relations; relation disposal rejects rather than cascading; authority is declaration metadata only |

---

## External Resources

- [Library README](../incr/README.mbt.md) — project overview and quick start
- [AGENTS.md](../AGENTS.md) — contributor/AI-agent guidance on commands and architecture
- Source code: [`../incr/`](../incr/) module packages
- Tests: `*_test.mbt` and `*_wbtest.mbt` files under `../incr/` and example modules
