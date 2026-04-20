# Architecture Assessment — 2026-04-20

**Status:** Point-in-time analysis. Two proposals (T1b, T3) shelved pending concrete drivers; everything else verified as already done, already queued, or explicitly rejected by recent author decisions. No action taken as a direct result of this document.

---

## Why this document exists

The first draft of this assessment cited architectural pressures that, on verification, had already been addressed by recent commits not yet reflected in the memory/docs record. That gap — docs and memory lagging the code by ~2 days — became its own finding (P5 below). This revised version records only what is verifiable against the current tree and flags explicitly where prior writeups (memory snapshots, `internals.md`) had drifted.

**Read-before-trust rule for future revisions:** if a file:line or commit is cited, verify it against the current tree before quoting it.

## Relevant commits (baseline for this assessment)

| SHA | Title | Why it matters |
|---|---|---|
| `6c7b5c1` | refactor+docs: complete pull-engine split; CycleError becomes pure-value | Moved `MemoData` to `cells/internal/pull/`; made `CycleError::format_path` runtime-free. Invalidated the "partial pull split" framing. |
| `082f2a6` | refactor(incr): extract accumulator concerns from memo.mbt and runtime.mbt | Consolidated accumulator machinery in `accumulator.mbt` but **deliberately left** the three accumulator fields flat on `Runtime`. Invalidates any proposal to now extract a sub-struct without new justification. |
| `a2b3354` | refactor+docs: dedup cross-runtime guard into shared helper | Target #1 of the 2026-04-19 audit. Forgiving-repair path in `Memo::get_result_inner` remains uniquely unmerged, documented as load-bearing. |
| `ef1fae7` | refactor+docs: extract install_cell helper for free-list SoA kinds | Target #2 of the 2026-04-19 audit. Memo and HybridMemo intentionally left outside (closure cycle). |

## 1. Change pressures (verified)

| # | Pressure | Evidence | Status |
|---|---|---|---|
| **P1** | Accumulator landed as cross-cutting surgery in the memo commit path + raw fields on `Runtime`. A second such feature will repeat the pattern. | `cells/memo.mbt` still calls three accumulator helpers by name (not via trait). `cells/runtime.mbt:155–165` has three accumulator fields flat on `Runtime`. `082f2a6` deliberately kept this shape. | Partial cleanup done; no declared extension point. |
| **P2** | `runtime.mbt` growth | 789 → 877 lines. Composed of `install_cell` (+24), accumulator fields + init (+~50), offset partially by `082f2a6` extraction. Not pathological. | Active, bounded. |
| **P3** | Cross-runtime identity relies on a single `let current_computing_runtime_id : Ref[Int]` (`runtime.mbt:22`) + forgiving-repair in `Memo::get_result_inner`. | 2026-04-19 audit explicitly records that the "stale-from-abort vs legitimate-cross-runtime" distinction needs a global runtime registry. Currently masked by panic-test hygiene. | Unresolved; benign under single-threaded assumption. |
| **~~P4~~** | `pipeline/` orphan package | `docs/todo.md:314,324` queues "move to `loom/src/pipeline/` then delete." Two test-file consumers inside `incr/`, zero external. | **Already decided, not a new proposal.** |
| **P5** | **Process meta-issue: memory and docs trailed code by one refactor cycle.** | `project_architecture_analysis.md` (memory) claimed `MemoData` still lived in `cells/`; `docs/design/internals.md:504` said "one pull-engine SoA type remains in `cells/`." Both were authored before `6c7b5c1` landed. | Fixed in this session; preventive practice flagged below. |

## 2. Current architecture (verified)

- `types/` (pure value types, zero deps) → `cells/internal/shared/` → `cells/internal/{pull,push,datalog}/` → `cells/` (coordinator, typed handles, algorithms, services) → root (`incr.mbt` facade + `traits.mbt`).
- Engine isolation enforced by `scripts/check-engine-isolation.sh`.
- Pull-engine split is **complete**: `PullSignalData` and `MemoData` both in `cells/internal/pull/`.
- `CycleError` is pure-value; labels snapshotted at raise time in `cells/cycle.mbt:13` (`CycleError::from_path`).
- Accumulator state: three direct fields on `Runtime` (`accumulator_slots`, `next_accumulator_id`, `accumulator_contributions`) + helpers named-dispatched from `memo.mbt`.
- Runtime identity: two file-scope `Ref[Int]`s (`next_runtime_id`, `current_computing_runtime_id`); safe under MoonBit's single-threaded target.

Shape is correct for today's problem set. Stage 6 engine extraction remains intentionally deferred; the accumulator feature shipped without needing it.

## 3. Architectural problems (narrowed)

- **AP1 — No declared extension point for cross-cutting memo-commit concerns.** Accumulator's three hooks are called by name in `memo.mbt`. One implementor today; N+1 copy-edit cost when the next cross-cutting concern arrives.
- **AP4 — Cross-runtime identification via single global `Ref[Int]`.** Fragile for future reentrancy or parallelism; currently load-bearing for panic-test hygiene.

Other problems from prior drafts (AP2 "runtime god-object regrowth", AP3 "handle/SoA closure cycle", AP5 "pipeline orphan", AP6 "CycleError → Runtime coupling") are dropped as resolved, structural-limit-accepted, or already-queued.

## 4. Target architecture — two discrete additions, both gated

### T1b — `MemoCommitPhase` trait (gated on a second cross-cutting driver)

```text
priv trait MemoCommitPhase {
  fn before_recompute(self, rt : Runtime, cell : CellId) -> Snapshot
  fn after_success(self, rt : Runtime, cell : CellId, snap : Snapshot)
  fn after_abort(self, rt : Runtime, cell : CellId, snap : Snapshot)
}
```

`memo.mbt` holds `Array[&MemoCommitPhase]`. Accumulator registers one implementor at runtime init. Three current hooks become method bodies.

**Gate:** build only when a second concern is specified (persistent caching in roadmap Phase 5 is the leading candidate; delta observers secondary). For one implementor, the trait is pure overhead.

### T3 — `RuntimeRegistry` (gated on parallelism design)

Replace the two file-scope `Ref[Int]`s with a registry that can answer "is runtime N still alive?" — giving `Memo::get_result_inner`'s forgiving-repair path a principled test instead of the current locally-scoped heuristic.

**Gate:** hold until Phase 5 parallelism or a reentrancy requirement is actually on the roadmap. Touching the heuristic today is a correctness risk without benefit.

### Dropped tracks (explicit non-goals)

- **Stage 6 engine extraction.** Void since accumulators shipped without requiring it.
- **Flat-`cells/` reorg, `memo.mbt` split, `runtime.mbt` topic split.** 2026-04-19 audit explicitly rejected.
- **`AccumulatorState` sub-struct.** `082f2a6` deliberately kept fields flat two weeks ago. Not re-litigated.
- **Move `format_path` out of `types/`.** Shipped in `6c7b5c1`.
- **Retire `pipeline/`.** Already backlog-ed in `docs/todo.md:314,324`.

## 5. Dependency and boundary rules

No changes. Existing rules sufficient:

1. Engines must not import other engines (enforced by `scripts/check-engine-isolation.sh`).
2. Engines must not read `RuntimePhase`; only the coordinator transitions phases.
3. DispatchTable is coordinator-writes-only.
4. `types/` is dependency-free.

**If T1b lands, add:** `MemoCommitPhase` implementors must not fire callbacks, trigger propagation, or mutate `RuntimePhase`. The memo commit is a transactional boundary; reentry forbidden.

## 6. Migration (conditional)

- **T1b (if commissioned):** single PR. Codex pre-implementation review. Zero-implementor fast-path test. Microbenchmark to verify commit-path overhead is negligible.
- **T3 (if commissioned):** single PR, only after a parallelism design doc exists. Add runtime-interleaving test suite *before* touching the heuristic. Existing panic-path tests must remain green.

Neither should be commissioned opportunistically.

## 7. Verification and observability

- Always: full test suite, `scripts/check-engine-isolation.sh`, no public API break, benchmarks within ±5%.
- T1b-specific: zero-implementor commit path bit-identical to pre-T1b; ordering test for before / after-success / after-abort.
- T3-specific: two-runtime interleaving tests (new coverage); all panic-isolation tests remain green.

## 8. Risks

- **T1b:** Array-dispatch overhead on commit. Zero-length fast-path if measured as non-negligible.
- **T3:** The highest-judgment change in the codebase. The forgiving-repair path is documented as load-bearing in multiple memory and audit records. Requires Codex validation before implementation.

## 9. Trade-offs

- **Accept speculative trait abstraction later** (T1b) over baking it in now. Rejected: build the trait with one implementor. Rationale: insufficient justification today; wait for a second driver to confirm hook shape.
- **Accept continued reliance on single-threaded assumption** (T3 deferred) over preemptive redesign. Rationale: premature given current target platforms (WASM + single-threaded native); change risk exceeds benefit.
- **Not revisiting:** Stage 6, `cells/` reorg, `memo.mbt`/`runtime.mbt` splits, `AccumulatorState` sub-struct. All have explicit prior decisions in memory or commits.

## 10. Scope

- **In:** T1b (conditional), T3 (conditional). And the process-level P5 finding below.
- **Out:** everything else from the original four-track proposal. In particular, anything resembling Stage 6 or a top-level reorganization.

## 11. Constraints and unknowns

- No second cross-cutting driver is specified today → T1b stays shelved.
- No parallelism roadmap beyond "Phase 5" → T3 stays shelved.
- `pipeline/` relocation target state in `loom/src/pipeline/` not verified in this pass. If someone picks up the queued move, check loom first.

## 12. Operational finding (P5)

This assessment exists because its first draft cited a pressure (`CycleError::format_path` blocking `MemoData` split) that `6c7b5c1` had already resolved. The memory record and `docs/design/internals.md:504` both said otherwise because they predated the commit by ~2 days.

**Preventive practice for future refactors:** any commit that changes cross-cutting structure (engine boundaries, SoA layout, cross-runtime mechanics) should update in the same chain:

1. The relevant prose in `docs/design/internals.md`
2. Any memory entry that names the structure or its constraints
3. `docs/todo.md` entries that describe the structure as a blocker or remaining work

The accumulator refactor (`082f2a6`) partially followed this — the commit message is explicit about the flat-field decision — but did not update `docs/design/internals.md` to retire the "runtime god-object" framing in that file. The pull-split refactor (`6c7b5c1`) updated the "Superseded" section of `internals.md` but left line 504 in the "Engine isolation" paragraph stale. Both contributed to the need for this revision.

## 13. Recommended next steps

1. **Nothing structural.** The codebase just absorbed a cleanup cycle. Further restructuring without a driver is churn.
2. **When a second cross-cutting concern appears** (persistent caching, delta observers): revisit T1b as its pre-implementation step.
3. **When Phase 5 parallelism is actually designed:** revisit T3.
4. **Adopt the P5 preventive practice** on the next cross-cutting refactor. One commit chain, three-artifact update (code + internals.md + memory/todo).
