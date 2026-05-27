# Future Sessions: Loom + Canopy Runtime-Safety Roadmap

Use this document as the shared starting point before you implement changes.

## Current Situation Snapshot (2026-05-27)

- **`loom/incr` core**: incremental graph model, dynamic dependencies, batch semantics, push/pull/fixpoint engines, and durability-aware revisioning are in place.
- **`loom` parser pipeline**: snapshot-driven parser updates and derived views are wired to the same reactive substrate (`Parser`, `Parser::set_source`, `apply_edit`, and derived signals).
- **Canopy orchestration layer**: shared-runtime direction is present, but integration is not fully hardened (notably lifecycle and cross-runtime wiring).

## Non-Negotiable Invariants Across Sessions

1. Preserve single logical runtime per workspace/editor session unless a specific migration requires temporary separation.
2. Any shared-runtime entry point must explicitly pass and validate runtime ownership.
3. Destroy/dispose order must keep dependent graphs and watchers consistent.
4. Observer roots are explicit; no implicit root leaks.
5. Identity must be stable across replica/context boundaries before it is used to key cache/state.
6. Changes to behavior without tests are not accepted.

## High-Priority Backlog

- [ ] **Unify runtime constructor paths**
  - Objective: every public editor/workspace entry point accepts/uses a shared runtime consistently.
  - Acceptance: one integration test proves a two-editor scenario has one runtime and shared recomputation graph state.

- [ ] **Replace single-slot `on_change` model at app boundary**
  - Objective: add a multiplexed notification path that can fan out safely without changing existing per-cell event behavior.
  - Acceptance: regression test confirms all relevant event sinks are invoked exactly once under shared edits.

- [ ] **Finalize lifecycle/dispose contract**
  - Objective: define and enforce observer/watch teardown before root GC changes.
  - Acceptance: session test fails if destroy is attempted while dependents are alive, then succeeds after teardown in deterministic order.

- [ ] **Harden identity strategy**
  - Objective: adopt a stable document/anchor identity model for cross-context nodes.
  - Acceptance: regression test catches previously-known mixed/nested divergence and validates stable IDs across re-renders.

- [ ] **Document + test cross-layer assumptions**
  - Objective: keep docs aligned with code around runtime sharing, `set_on_change`, and protected reads.
  - Acceptance: every architectural claim in related docs has a corresponding test pointer.

## Session Start Template

For each new session, copy this block to the session notes before editing code:

### 1) What this session is trying to change
- Target area:
- Success metric:
- Why now:

### 2) What is already proven
- Invariant proved (file/test):
- New risk introduced if any:
- Required follow-up tests:

### 3) Work plan for this session
- [ ] task:
  - owner:
  - files:
  - validation:
- [ ] task:
  - owner:
  - files:
  - validation:

### 4) Verification gate before stopping
- `moon check`
- `moon test <scope>` for touched package(s)
- Gate tests for runtime safety (or equivalent): `gate1_runtime_safety_wbtest`
- docs check: any API/contract behavior change references are updated and linked

### 5) Regression lock-in
- What changed this session:
- Evidence files (`commit diff` paths and test names):
- Open risk for next session:

## Use Rule

If a past claim is used as assumption, re-validate it with a direct test reference before proceeding with the next change.

## Session Command Checklist (Default)

Use this sequence unless the current task is documentation-only.

1. `git status --short` — confirm worktree scope and avoid drifting into unrelated edits.
2. `moon fmt` — keep style/format stable before checks.
3. `moon check` — required for any source change.
4. `moon test cells` — engine-level validation for `loom/incr` core.
5. `moon test tests` — integration-level public API checks.
6. If runtime-orchestration assumptions changed, add the canopy probe package you touched in the parent workspace suite.
7. If this session edits both `incr` and parent `canopy` files, run the owning module/parent workspace tests from the `canopy` checkout as a final integration gate.
