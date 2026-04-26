# ADR: R2 (Runtime → Services Decomposition) — Deferred

**Date:** 2026-04-26
**Status:** Accepted — deferred indefinitely; revisit only with concrete driver
**Supersedes (in part):** the "R2 — Runtime → services decomposition" framing in `~/.claude/projects/.../memory/project_next_priorities.md` (entries 1 and 27, dated 2026-04-25)
**Anchors:** [2026-04-20 architecture assessment](../design/specs/2026-04-20-architecture-assessment.md), [PR #48](https://github.com/dowdiness/incr/pull/48) (R1 closer)

## Context

R1 (kernel split, PRs #45–48) closed on 2026-04-26. The post-R1 architecture leaves `cells/runtime.mbt` at **427 LOC across 22 methods**, of which the majority are 1–13-line delegators to `cells/internal/kernel/`. A persistent backlog item carried in memory under the label "R2" proposed the next structural move: decomposing `Runtime` into typed service objects (e.g. `BatchService`, `GcService`, `PropagationService`) so each kernel-facing concern would own its own struct.

This ADR records the decision not to pursue that decomposition without a concrete driver, and retires the R2-as-imminent-track framing from rolling memory.

## Empirical state of `cells/runtime.mbt` (2026-04-26)

Measurements taken against `main @ be86ed5` immediately after the R1 closer merged.

| Metric | Pre-R1 (2026-04-21) | Post-R1 (2026-04-26) |
|---|---|---|
| `cells/runtime.mbt` LOC | 877 | **427** |
| Runtime method count | ~30 | **22** |
| Largest Runtime method body | n/a | **13 lines** (`check_table_invariant`) |
| Coordinator-primitive methods (≥10 lines) | several with full algorithm bodies | **5**: `propagate_changes`, `publish_cell_changes`, `add_subscriber`, `remove_subscriber`, `check_accumulator_cache_invariant` — all 11–13 lines, all 1-line delegators wrapped in argument-shuffling |
| Algorithm bodies | inline | **0** — all in `cells/internal/kernel/*.mbt` |

`Runtime` is no longer a god-object. It is a Salsa-style facade holding handles to `RuntimeCore` + per-engine state, plus a thin dispatch layer. The "R2" framing was inherited from when `runtime.mbt` was 877 LOC and held algorithm bodies. That premise is gone.

## What R2-as-decomposition would actually do today

Concretely, splitting the current 427 LOC file into typed services would mean:

1. Create `BatchService { core, pull, push, datalog }`, `GcService { ... }`, `PropagationService { ... }`, etc.
2. Replace `rt.commit_batch()` callsites with `rt.batch_service.commit_batch()` (or move the helper onto the service struct).
3. Each service method body remains a 1-line `@kernel.X(self.core, self.pull, ...)` delegation.
4. `Runtime` becomes a struct of 4–6 service references.

**This is a rename of the wrappers, not a structural change.** The kernel boundary already exists. The engine isolation script already enforces one-way dependency. Service objects with no internal state and no logic of their own are pure overhead — they multiply the import surface, force consumers to learn N service handles instead of one Runtime, and add a layer of indirection without removing any.

## Why "no" — three independent reasons

**1. The premise is gone.** The 877 → 427 LOC drop and the kernel split addressed the actual underlying pressure (god-object + missing module boundary). What remained on `Runtime` after R1 is what *should* live on the facade: cell allocation, dispatch-table install, debug invariants, and trait-bound delegators.

**2. No driver.** This codebase's structural-change track record — see `feedback_incr_driver_gate_overridden.md` and the 2026-04-19 ReactiveMap/DeltaObserver experience — is that driverless structural proposals fall apart under Codex review. R1 was the explicit exception ("user lifted driver-gate"); that lift was scoped to R1 and has not been re-extended.

**3. The 2026-04-20 architecture assessment already answered this category of question.** That document enumerated two structural tracks (`T1b` MemoCommitPhase, `T3` RuntimeRegistry), both gated on concrete drivers (second cross-cutting concern, parallelism roadmap respectively). It did **not** propose Runtime decomposition. The "R2" label is not a documented track — it appears to be informal session shorthand for "what comes after R1," not a planned refactor with a written spec.

## What would change this

R2 (or any service decomposition) becomes worth designing if and when one of these appears:

- **A second consumer of the kernel boundary.** If a non-Runtime caller wants to invoke kernel primitives (e.g. a snapshot/replay test harness, or a multi-runtime orchestration layer), service objects with explicit dependency-injection might pay for themselves.
- **`Runtime` regrows past ~600 LOC for a non-cosmetic reason** — e.g. a new feature genuinely adds coordinator logic, not just more delegators.
- **A dependency-injection driver in tests.** If swapping out the kernel for a fake (for testing rare phase transitions, or for property-based testing of the dispatch layer) becomes painful, services with constructor-passed state would help. Today, `RuntimeCore` already serves this role.

None of these exist today. Until one does, R2 stays shelved.

## What this means for adjacent labels (R3 / R5 / R6 / R7)

Memory carried a notional R3/R5/R6/R7 catalog parallel to R2. After cross-checking against `docs/design/specs/2026-04-20-architecture-assessment.md`, only two structural tracks have written specs (T1b, T3), both gated. The numbered R-track framing post-R1 is therefore retired; future structural work should reference the assessment's gates directly, or open a fresh ADR with its own driver.

## Decision

1. **Do not implement R2 / Runtime → services decomposition.** No PR, no plan, no spike.
2. **Retire the R-numbered post-R1 catalog from rolling memory.** Update `project_next_priorities.md` to point at this ADR and at the 2026-04-20 assessment instead of the R2-R7 listing.
3. **Default next track is the canopy step-back** (item 9 in the prior backlog) — wire `TypecheckAttachment` from `loom/examples/lambda/src/typed_parser.mbt` into a canopy UI surface. This re-engages the driver-gate that R1 had lifted and exercises the post-R1 architecture under real downstream pressure.

## Trade-offs accepted

- **Accept Runtime as a 22-method facade.** Reading 22 short methods in one file is cheaper than chasing 4–6 service types. If this becomes false, this ADR is wrong and worth revisiting.
- **Accept that "what comes next structurally" is no longer pre-planned.** The trade is real: pre-planned roadmaps create momentum; ad-hoc gating creates correctness. R1's success and the 2026-04-19 driverless-proposal failure both point the same way — gate-on-driver wins.

## Verification

- `cells/runtime.mbt` line count and method profile: confirmed against `main @ be86ed5` on 2026-04-26.
- Architecture-assessment doc (2026-04-20) read in full; T1b and T3 are the only structural tracks with written specs.
- No outstanding R2 plan or notes file in `docs/plans/` or `docs/design/specs/`.
