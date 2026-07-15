# Retention Cost Attribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `moonbit-perf-investigation` before changing benchmarks and `moonbit-verification` before completion. Performance causality judgments stay in the main agent context; delegate only mechanical documentation or test edits.

**Goal:** Attribute the cumulative-created-cell update cost reported by #399 and record a measured go/no-go decision for future slot reclamation without changing engine behavior.

**Architecture:** Preserve the existing 7a, 7b, and 8a benchmark shapes as the shared cross-target baseline. Add white-box characterization that separates reusable SoA slots from cumulative `CellId` dispatch tables, then follow a target-dependent evidence branch: native reproduction triggers engine-path profiling; wasm-gc-only growth triggers target-specific profiling and a minimal collector-versus-codegen control.

**Tech Stack:** MoonBit 0.1.20260703 or the current pinned toolchain, `moon bench --release`, MoonBit white-box tests, wasm-gc and native targets, repository performance snapshot conventions.

## Global Constraints

- Scope is investigation, characterization tests, a dated performance note, and a go/no-go decision only.
- Do not change runtime behavior, public API, slot semantics, `CellId` allocation, or storage compaction.
- Do not infer collector causality from a wasm-gc/native difference alone.
- Preserve identical 7a, 7b, and 8a workload shapes across target comparisons.
- Record exact commit, toolchain, hardware, commands, and every retained measurement used in the decision.
- Run `moon check` after every MoonBit edit.
- Every new documentation file must be indexed in `docs/README.md` in the same commit.
- Never hand-edit generated `.mbti` files.

---

### Task 1: Reproduce the cross-target baseline

**Files:**
- Read: `incr/tests/retention_bench_test.mbt`
- Read: `docs/performance/2026-07-14-retention-baseline.md`
- No committed file changes

**Produces:** A retained measurement table for scenarios 7a, 7b, and 8a on wasm-gc and native, with multiple complete runs and no benchmark-shape changes.

- [ ] Confirm the branch still points at the commit being measured and the working tree is clean.
- [ ] Record `moon version`, `moonc -v`, OS, CPU, target, and commit SHA in the investigation notes.
- [ ] Run the existing wasm-gc release benchmark at least three complete times:

  `moon bench --release -p dowdiness/incr/tests -f retention_bench_test.mbt`

  Expected: all 28 benchmark cases pass; retain the 7a, 7b, and 8a values from every run rather than only the fastest run.
- [ ] Run the identical benchmark at least three complete times on native:

  `moon bench --release --target native -p dowdiness/incr/tests -f retention_bench_test.mbt`

  Expected: all 28 benchmark cases pass; retain the same scenario rows.
- [ ] Compare the N=1,000 and N=10,000 ratios within each target. Do not compare absolute wasm-gc and native times as though the backends have the same cost model.
- [ ] Apply the first stop gate:
  - if the original wasm-gc growth does not reproduce consistently, classify the old baseline as stale or unstable and skip optimization-oriented profiling;
  - otherwise continue to Task 2.

---

### Task 2: Pin post-cleanup storage facts

**Files:**
- Modify: `incr/cells/retention_bench_fixture_wbtest.mbt`
- Test: `incr/cells/retention_bench_fixture_wbtest.mbt`

**Produces:** Scenario-shaped white-box tests for explicit disposal and runtime GC that distinguish cumulative dispatch-table length from reusable pull memo slots.

- [ ] Add one helper that builds the 7a shape: root input, N primed pull derived cells retained in an array, one live eager derived cell, then explicit disposal of the pull derived cells.
- [ ] Add one helper that builds the 7b shape: root input, N primed pull derived cells without retained user handles, one watched live eager derived cell, then `Runtime::gc()`.
- [ ] Add a 7a characterization test using a small deterministic N. Assert root dependent identity/count, `cell_index`/`cell_ops`/`cell_lifecycle` cumulative lengths, pull memo slot length, `free_memos` count, and live push node count independently.
- [ ] Add the corresponding 7b characterization test with the same fact categories. Keep the watch alive through the assertions and dispose it at the end.
- [ ] Run the targeted test before changing any engine code:

  `moon test incr/cells/retention_bench_fixture_wbtest.mbt`

  Expected: the new assertions either confirm the current storage model or expose a mistaken expectation. If an expectation is wrong, inspect the relevant disposal/GC implementation and correct the characterization; do not change the engine to satisfy the test.
- [ ] Run `moon check` immediately after the MoonBit edit.
- [ ] Mutation-check one load-bearing assertion by temporarily contradicting the expected free-slot or dispatch-table count, confirm the targeted test fails for that assertion, then revert the contradiction and rerun the test.
- [ ] Commit the characterization tests separately with a test-only commit.

---

### Task 3: Attribute the reproduced target behavior

**Files:**
- Read: `incr/cells/input.mbt`
- Read: `incr/cells/runtime.mbt`
- Read: `incr/cells/internal/kernel/propagate.mbt`
- Read: `incr/cells/internal/kernel/push_propagate.mbt`
- Conditionally modify: `incr/tests/retention_bench_test.mbt`

**Produces:** A named mechanism or an explicit unresolved mixture, supported by profile/control evidence. No engine fix.

- [ ] If native also shows material N-dependent residual growth after 7a/7b cleanup, profile the native 7a/7b update path and identify whether any operation count or runtime work scales with cumulative retained storage. Trace from `Input::set` through `Runtime::propagate_changes` and kernel push propagation; do not infer a scan from array length alone.
- [ ] If native does not reproduce the growth but wasm-gc does, profile the wasm-gc case and design the smallest control that separates the live one-edge push traversal from retained runtime roots/storage. The control must preserve the timed allocation pattern or explicitly measure allocation as its independent variable.
- [ ] Before adding a control benchmark, write down its scenario matrix: retained objects, live graph edges, allocations per timed update, and expected distinguishing result for collector/root scanning versus backend/code generation.
- [ ] Add a control to `retention_bench_test.mbt` only if existing 7a/7b/8a data and available profiles cannot distinguish the candidates. Keep it adjacent to the retention scenarios and give it both N=1,000 and N=10,000 cases.
- [ ] After any benchmark edit, run `moon check`, then run the changed benchmark on both targets at least three complete times.
- [ ] Apply the attribution gate:
  - engine path: name the scaling operation and evidence;
  - target collector/root scanning: require target-specific profile/control evidence;
  - backend/code generation: require evidence inconsistent with retained-root scanning;
  - mixture: state exactly which candidates remain inseparable;
  - non-reproduction: state the observed variance and stop.
- [ ] Do not prototype or commit an engine optimization in this task.

---

### Task 4: Publish the attribution record

**Files:**
- Create: `docs/performance/2026-07-15-retention-cost-attribution.md`
- Modify: `docs/README.md`
- Modify if the roster requires it: `docs/performance/README.md`

**Produces:** A dated, reproducible performance record and explicit slot-reclamation decision.

- [ ] Write the environment section with commit, toolchain, hardware, OS, target, exact commands, run count, and successful exit evidence.
- [ ] Add per-run tables for wasm-gc and native 7a, 7b, and 8a results. Include N ratios and variance/range; do not report only a selected aggregate.
- [ ] Record the white-box storage facts from Task 2: cumulative dispatch-table length, SoA/free-slot state, and live graph state after dispose/gc.
- [ ] Record all profile/control evidence from Task 3, including negative findings.
- [ ] State one bounded attribution using the Task 3 categories. Mark any remaining causal claim as unresolved rather than converting correlation into mechanism.
- [ ] State the slot-reclamation decision:
  - `go` only when a named engine operation scales with retained storage and reclamation has a measurable path to reducing it;
  - otherwise `no-go` with the evidence required to reopen.
- [ ] Link the new note from `docs/README.md` and the dated snapshot roster in `docs/performance/README.md` when that roster covers the new record.
- [ ] Commit the performance note and both indexes together.

---

### Task 5: Verify and review the completed investigation

**Files:**
- Verify all changed files
- No new scope

**Produces:** Evidence that characterization, documentation, and measurements are internally consistent and the branch contains no engine behavior change.

- [ ] Run `moon fmt`.
- [ ] Run `moon info` and inspect generated interface changes. Expected: no `.mbti` semantic change from the test/docs-only work.
- [ ] Run `moon check`.
- [ ] Run `moon test incr/cells/retention_bench_fixture_wbtest.mbt`.
- [ ] Run the full `moon test` suite.
- [ ] Rerun the final benchmark command on both wasm-gc and native and verify the published tables correspond to retained command output.
- [ ] Inspect the branch diff and confirm it contains no runtime source or public API modification.
- [ ] Request an independent different-model review focused on attribution logic, target/backend confounding, white-box expectation accuracy, and documentation reproducibility.
- [ ] Address review findings without expanding into an engine fix.
- [ ] Update #399/PR text with literal `Closes #399` only after every acceptance criterion is evidenced.
