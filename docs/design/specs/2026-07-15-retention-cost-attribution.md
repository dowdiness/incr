# Retention Cost Attribution

**Date:** 2026-07-15  
**Issue:** [#399](https://github.com/dowdiness/incr/issues/399)  
**Status:** Approved for implementation

## Problem

The 2026-07-14 retention baseline found that scenarios 7a and 7b become slower
as the number of previously created pull cells grows, even after explicit
disposal or `Runtime::gc()` restores the root subscriber set to one live eager
cell. Scenario 8a also changes with retained chain volume despite equal direct
root fanout.

The current evidence does not distinguish among:

- work in an engine path that scales with cumulative runtime storage;
- wasm-gc collector or root-scanning cost;
- backend/code-generation effects unrelated to collector work;
- a mixture of these costs.

A target comparison alone cannot identify the collector. It only determines
which attribution branch to investigate next.

## Scope

This work attributes the residual cost and records a go/no-go decision on a
future slot-reclamation or compaction change.

It does not change runtime behavior, add a public introspection API, compact
storage, reuse `CellId` values, or implement an optimization. Any engine change
requires a separate design and pull request after this investigation.

## Existing facts to preserve

- Pull and push SoA storage have free-slot arrays.
- `cell_index`, `cell_ops`, and `cell_lifecycle` remain indexed by monotonically
  allocated `CellId` and therefore retain cumulative length.
- The normal `Input::set` coordinator accesses changed cells by id and invokes
  push propagation only while live push cells exist; the current source does
  not itself establish a full dispatch-table scan.
- The existing 7a, 7b, and 8a benchmark bodies allocate no reactive cells during
  their timed steady state.

## Attribution ladder

### 1. Reproduce the baseline

Run the unchanged retention benchmark on wasm-gc and native release targets.
Use the same 7a, 7b, and 8a fixtures, the same N values, and multiple complete
runs. Preserve command lines, toolchain, commit, hardware, and raw per-run
values.

If the 2026-07-14 growth does not reproduce, stop. Record a stale or unstable
baseline and do not propose an optimization.

### 2. Pin storage state

Extend `incr/cells/retention_bench_fixture_wbtest.mbt` with scenario-shaped
fixtures for explicit dispose and `Runtime::gc()`.

After cleanup, assert independently:

- the root has exactly one dependent, the live eager cell;
- `cell_index`, `cell_ops`, and `cell_lifecycle` retain the expected cumulative
  `CellId` length;
- pull memo storage has the expected slot count;
- disposed pull memo slots are present in `free_memos`;
- the live eager cell remains active.

These assertions distinguish reusable SoA slots from cumulative dispatch-table
entries. They do not make cumulative dispatch-table retention a public
contract; they are white-box characterization evidence for this investigation.

### 3. Follow the target-dependent branch

If cumulative-volume scaling also reproduces on native, inspect and profile the
native update path for work proportional to retained runtime state. A native
reproduction is evidence to investigate engine work, not proof that the engine
is the sole cause.

If scaling is material only on wasm-gc, run a target-specific profile and a
minimal control benchmark that separates retained runtime roots/storage from
the real push traversal. Use that evidence to distinguish collector/root-set
cost from backend/code-generation effects. Do not label the result
"collector" from the target comparison alone.

If the available evidence cannot separate collector and code generation,
classify the result as a named target-specific mixture and leave slot
reclamation unapproved.

### 4. Record the decision

Create `docs/performance/2026-07-15-retention-cost-attribution.md` containing:

- environment and exact commands;
- per-run wasm-gc and native results for 7a, 7b, and 8a;
- white-box storage facts;
- any additional profile/control results;
- one attribution: engine path, target-specific collector/root scanning,
  backend/code generation, named mixture, or non-reproduction;
- an explicit go/no-go statement for a separate slot-reclamation design.

Add the note to `docs/README.md`.

## Decision rules

- **Engine-path go:** scaling reproduces outside wasm-gc and a named update-path
  operation grows with retained runtime state. Open a separate design issue;
  do not change the engine in #399.
- **Target-cost no-go:** scaling is target-specific and additional evidence
  attributes it to collector/root scanning or code generation. Document the
  deployment-target cost; do not change slot semantics without a measured
  target benefit.
- **Mixture no-go:** attribution remains mixed. Preserve the benchmark and
  gather stronger evidence before changing storage.
- **Non-reproduction no-go:** the prior cost is stale or unstable. Record the
  new baseline and stop.

## Verification

- The new white-box tests pass on the unchanged engine and fail if free-slot or
  cumulative dispatch-table expectations are deliberately contradicted.
- Existing retention fixture tests remain green.
- `moon check` passes after every MoonBit edit.
- `moon fmt`, `moon info`, targeted tests, the full test suite, and both release
  benchmark commands complete before the pull request is opened.
- No generated `.mbti` file is edited by hand.
