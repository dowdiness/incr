# R1 Stage 3 — Execution Notes

**Date:** 2026-04-24
**Basis:** [R1 plan v3 § Stage 3](2026-04-21-r1-engine-package-split.md) + [Stage 2 execution notes](2026-04-24-r1-stage2-notes.md)
**Purpose:** Concrete spec for Stage 3 (algorithm moves). Parallels the Stage 2 notes structure. This doc supersedes plan v3 § Stage 3 for **mechanics** where they differ.

## Verdict from Codex pre-review (2026-04-24)

**IMPLEMENT WITH CHANGES.** Option-4 accumulator decision endorsed. Five substantive corrections folded in below; then the original checklist is the authoritative spec.

## Corrections folded in

### 1. Cells/ helpers still called by `memo.mbt` — cannot fully retire in Stage 3

Codex found three cells-side callers the draft missed in `cells/memo.mbt::memo_force_recompute`:

- `CycleError::from_path(self, self.collect_tracking_path(), ...)` at `memo.mbt:410,412`
- `self.push_tracking(cell_id)` at `memo.mbt:422`, `self.pop_tracking_full()` at `memo.mbt:427,434`
- `self.diff_and_update_subscribers(...)` at `memo.mbt:447`

**Resolution:** migrate these call-sites inside the same commit that moves each body:

- Commit 3b migrates `memo.mbt:410` from `CycleError::from_path(self, path, id)` to `@kernel.construct_cycle_error(self.core, path, id)`.
- Commit 3c migrates `memo.mbt:447` to `@kernel.diff_and_update_subscribers(self.core, self.pull, self.push, self.datalog, cell_id, old_deps, new_deps, new_seen~)`.
- Commit 3d migrates `memo.mbt:412,422,427,434` to `@kernel.collect_tracking_path(self.core)`, `@kernel.push_tracking(self.core, cell_id)`, `@kernel.pop_tracking_full(self.core)`.

Do not rely on "forwarder shims" in cells/cycle.mbt or cells/tracking.mbt — the sweep is small enough to do in the same commit and keeps the cells/ footprint shrinking monotonically.

### 2. Keep `begin_tracking`/`end_tracking` thin wrappers (D8 reserved)

Codex confirmed §12 Q4 conservatively: `begin_tracking`/`end_tracking` are called from `push_reactive.mbt:63`, `push_effect.mbt:39`, `push_lifecycle.mbt:58,60`, plus `push_propagate.mbt:210,212,244,246` (the last set moves into kernel with push_propagate in 3f). Remaining 4 cells/ call-sites all take `rt.begin_tracking(cell_id)` as a single-arg readable verb. Per D8 "high-fan-out protocol verb," **keep both wrappers**. Drop the draft's suggestion in §3 to drop them.

### 3. `propagate_level_change` / `push_propagate_from` signatures corrected

Draft §2 3f over-listed parameters. Per Codex code trace:

- `propagate_level_change(core : RuntimeCore, push : PushState, changed_cell : CellId, update_queue : PriorityQueue[PushEntry]) -> Unit` — BFS only reads `core.cell_index` + subscribers and mutates `push.reactives[i].level` / `push.effects[i].level`. No `pull` / no `datalog`.
- `push_propagate_from(core : RuntimeCore, pull : PullState, push : PushState, changed_sources : Array[CellId]) -> Unit` — body reads `pull.memos` (line 172 / 149-178 BFS) for hybrid/pull memo dispatch but never touches `datalog.*`. Drop `datalog : DatalogState` from the param list.

Runtime wrapper (3f) becomes: `fn Runtime::push_propagate_from(self, ids) { @kernel.push_propagate_from(self.core, self.pull, self.push, ids) }`.

### 4. `adjust_push_reachable` DOES need `datalog` — clarified

Draft §2 3a listed `adjust_push_reachable(core, pull, push, datalog, ...)`. Codex confirmed this is correct: `adjust_push_reachable` at `runtime.mbt:396` match-arms into `Relation(i)` / `FunctionalRelation(i)` / `Rule(i)` to touch `datalog.relations[i].meta` / etc. The other subscriber helpers (`add_subscriber`, `remove_subscriber`) call `adjust_push_reachable` transitively, so they also need `datalog`. **Unchanged from draft — this is correct.**

### 5. Bench-target doc inconsistency

Master plan v3 Stage 0 text says "baseline captured on native target." Stage 2 notes + the `docs/performance/2026-04-21-pre-r1-baseline.md` doc use **wasm-gc** (switched in commit `837a289`). Stage 3's bench gate (§4 / §10) must say **wasm-gc** and the master plan wording is stale. When Stage 3 lands, add a one-line note to plan v3's Stage 0 text pointing at `837a289` as the authoritative baseline-target switch. Do not re-introduce native as an option.

### 6. `pull_verify_wbtest.mbt` is NOT redundant with `verify_wbtest.mbt`

Draft §5 said "check if redundant; if so, merge." Codex verified: `pull_verify_wbtest.mbt` covers the explicit `Runtime::pull_verify` contract; `verify_wbtest.mbt` covers leaked-state / cycle characterization. Both move in 3e as-is. No merge.

### 7. New risk surfaced: partial-migration state

Added to §11 as S3-7: if any cells/ call-site to cycle/tracking/subscriber helpers is missed during the same-commit sweep, Stage 3 lands in a half-kernelized state where `moon check` passes but the `cells/` footprint carries phantom dependencies. Mitigation: each sub-step includes a `grep -rn` verification that no cells/*.mbt still references the old symbol name at commit time.

### 8. §3 wrapper-drop list pruned

With corrections 1 + 2 applied:

- **Keep** (added to reserved list): `begin_tracking`, `end_tracking`, `diff_and_update_subscribers`, `collect_tracking_path`, `push_tracking`, `pop_tracking_full` — all called from `memo.mbt` or multiple push-side files.
- **Drop** stays for: `get_level`, `recompute_level`, `propagate_level_change` (push-propagate-internal), `push_contribution`, `collect_reachable_cells`, `cell_id_at`, `get_subscribers` (keep — too many call-sites), `collect_in_progress_path` (kernel-internal after 3e).

---

Sections 0–13 below are the original draft, subsuming these corrections.



## 0. Resolved design question — `accumulator_snapshots` location

The Stage 3 open question in `project_r1_kernel_split_plan.md` framed three options. There is a fourth option already implicit in plan v3 D5, and it is the chosen path:

**Decision:** `accumulator_snapshots : Array[&@shared.SlotSnapshot]` **stays on `Runtime`** (where Stage 2 placed it). Kernel `pull_verify` takes the snapshot array as an **explicit parameter** from its caller. Runtime wrappers pass `self.accumulator_snapshots` in.

**Kernel signature:**
```moonbit
pub fn pull_verify(
  core : RuntimeCore,
  pull : PullState,
  slot_snapshots : Array[&SlotSnapshot],
  cell_id : CellId,
) -> Result[Unit, CycleError] raise Failure
```

**Rationale:**

1. **Plan v3 D5 already designed this signature.** The four-arg form is verbatim in the plan's example; no re-scope.
2. **Only one algorithm reads slot_snapshots.** `pull_verify` (plus its sub-helper `synthetic_accumulator_changed`, which is internal to the same kernel file). `push_propagate`, `fixpoint`, `commit_batch`, `dispose`, `gc` don't touch accumulator slots at all. The parameter-passing cost is a single read per top-level verify call.
3. **Symmetric with `cell_lifecycle`.** Stage 2 explicitly moved `cell_lifecycle` OUT of `RuntimeCore` onto `Runtime` to avoid creating a cycle through the `CellLifecycle(Runtime, ...)` trait. Moving `accumulator_snapshots` INTO `RuntimeCore` would undo the clean separation Stage 2 just established — `RuntimeCore` acquires accumulator-adjacent state while `accumulator_slots`, `accumulator_contributions`, `next_accumulator_id` all still live on `Runtime` per D4. That split is worse than the current homogeneous grouping.
4. **No Stage 2 re-open.** Changing `RuntimeCore`'s layout now invalidates the pkg.generated.mbti diff Stage 2 paid for.
5. **Recursion passes the ref along.** Inside kernel, `synthetic_accumulator_changed` already has `slot_snapshots` in scope; its recursive `pull_verify` call threads the same reference.

**What the Opus ultrathink concern was really flagging:** the review warned against future "Stage-3 design lock-in." That lock-in only materialises under option 3 (verify stays in cells/). Under the option-4 path, verify is fully in kernel, takes an explicit `slot_snapshots` parameter, and doesn't depend on which struct owns the field. The flexibility is preserved.

## 1. Stage 3 context from Stage 2

Stage 2 delivered the state types + phase machine + SlotSnapshot trait + cell_lifecycle lift (PR #46, `454e3b4`). Relevant for Stage 3:

- `@kernel.{RuntimeCore, PullState, PushState, DatalogState, TrackingState, BatchState, BatchFrame, BatchUndo, RevisionState, ActiveQuery, PropagationPhase, enter_phase, leave_phase, alloc_runtime_id, get_current_computing_runtime_id, set_current_computing_runtime_id}` all in place.
- `pub trait @shared.SlotSnapshot { disposed; push_revised_at_for }` in place; `SlotMeta` implements it; `accumulator_snapshots : Array[&SlotSnapshot]` cached on `Runtime`.
- Stage 2 pinned SlotSnapshot trait dispatch + cache alignment with three wbtests that stay in `kernel/` and do not move again in Stage 3.

## 2. Ordering (strict leaf-first — per plan v3)

Stage 3 ships as **one PR, multiple commits**. Each commit is one functional group. A callee must be in kernel before its caller moves.

| Commit | Target file in `kernel/` | Size | Notes |
|---|---|---|---|
| 3a | `dispatch.mbt` | ~180 LOC | Structural guards, subscriber + reachable helpers |
| 3b | `cycle.mbt` | ~30 LOC | `construct_cycle_error` + label slice |
| 3c | `subscriber_diff.mbt` | ~50 LOC | Called by `finish_tracking` — must land before 3d |
| 3d | `tracking.mbt` | ~120 LOC | `push_tracking`/`pop_tracking`/`finish_tracking` + path collectors |
| 3e | `verify.mbt` | ~290 LOC | Pull-verify iterative + synthetic_accumulator_changed |
| 3f | `push_propagate.mbt` | ~250 LOC | Depends on 3a + 3c + 3d |
| 3g | `fixpoint.mbt` (body) | ~100 LOC | Keeps `Runtime::fixpoint` wrapper (plan v3 item 3g) |

Batch `commit_batch` body is **Stage 4**, not Stage 3 (plan v3). Stage 3 does not touch `cells/batch.mbt`.

### Callee inventory per sub-step

**3a (`kernel/dispatch.mbt`)** — free functions taking `(core, pull, push, datalog, …)` as needed:
- `validate_cell_soft(core, id) -> Bool`
- `validate_cell(core, id, caller) -> Unit` (the aborting variant currently in `runtime.mbt:198`)
- `cell_id_for(core, pull, push, datalog, cell_ref) -> CellId`
- `is_cell_disposed(core, cell_id) -> Bool`
- `get_changed_at(core, id) -> Revision`
- `get_durability(core, id) -> Durability`
- `get_subscribers(core, cell_id) -> Iter[CellId]`
- `add_subscriber(core, pull, push, datalog, dep, sub) -> Unit`
- `remove_subscriber(core, pull, push, datalog, dep, sub) -> Unit`
- `push_contribution(core, pull, sub_id) -> Int`
- `collect_reachable_cells(core, pull, sources) -> HashSet[CellId]`
- `adjust_push_reachable(core, pull, push, datalog, sources, delta) -> Unit`
- `cell_id_at(core, i) -> CellId`

Per D8, Runtime wrappers **drop** for internal-only callers; **keep** for public API callers + the semantic-internal reserved list (`pull_verify`, tracking verbs, `propagate_changes`, `publish_cell_changes`).

**3b (`kernel/cycle.mbt`)**:
- `construct_cycle_error(core : RuntimeCore, path : Array[CellId], closing_id : CellId) -> CycleError` — iterates `core.cell_ops[i].label()` for the first `MAX_CYCLE_DISPLAY_STEPS`. Replaces `CycleError::from_path` in `cells/cycle.mbt`. The cells/ file is **deleted** once all callers migrate (verify inside kernel uses kernel's version directly; no remaining cells/ caller after 3e lands).

**3c (`kernel/subscriber_diff.mbt`)**:
- `diff_and_update_subscribers(core, pull, push, datalog, cell_id, old_deps, new_deps, new_seen?) -> Bool` — calls `add_subscriber`/`remove_subscriber` (already in kernel from 3a).

**3d (`kernel/tracking.mbt`)**:
- Impl trait `Tracker for Runtime` stays in **cells/tracking.mbt** as thin delegators. The bodies move to kernel free functions that take `core : RuntimeCore` directly.
- Free functions: `push_tracking(core, cell_id)`, `pop_tracking(core) -> (deps, seen)`, `pop_tracking_full(core) -> ActiveQuery`, `top_active_query(core) -> ActiveQuery?`, `record_dep(core, dep)`, `check_cross_runtime(runtime_id, kind)` (the runtime_id arg pattern already matches — it only reads the static `current_computing_runtime_id`).
- `finish_tracking(core, pull, push, datalog, cell_id, old_deps, new_deps, new_seen) -> Unit` — calls `diff_and_update_subscribers` from 3c.
- `collect_tracking_path(core) -> Array[CellId]` — moves.
- `collect_in_progress_path(pull) -> Array[CellId]` — moves; reads `pull.memos` for the `in_progress` flag. (Currently at `cells/introspection.mbt:154` — not in `cells/tracking.mbt`. Still a kernel-side concern because the only caller is `pull_verify`.)

**3e (`kernel/verify.mbt`)**:
- `PullVerifyFrame` (priv struct) moves with body.
- `clear_verify_stack(pull, stack)` helper moves.
- `synthetic_accumulator_changed(core, pull, slot_snapshots, memo) -> Result[Bool, CycleError] raise Failure` — replaces direct `rt.accumulator_slots[].disposed` reads with `slot_snapshots[].disposed()` and `slot_snapshots[].push_revised_at_for(target_id)` trait calls. Calls kernel `pull_verify` recursively (pass `slot_snapshots` through).
- `pull_verify(core, pull, slot_snapshots, cell_id) -> Result[Unit, CycleError] raise Failure` — body moves verbatim with field-access rewrites:
  - `self.core.X` → `core.X`
  - `self.pull.memos` → `pull.memos`
  - `self.accumulator_slots` → `slot_snapshots` (trait-mediated)
  - `self.is_cell_disposed(id)` → `is_cell_disposed(core, id)` (kernel fn from 3a)
  - `rt.pull_verify(target_id)` (recursive) → `pull_verify(core, pull, slot_snapshots, target_id)`
  - `CycleError::from_path(self, path, id)` → `construct_cycle_error(core, path, id)` (from 3b)
  - `self.collect_in_progress_path()` → `collect_in_progress_path(pull)` (from 3d)

- **Runtime wrapper stays** (D8 reserved list): `fn Runtime::pull_verify(self, cell_id) -> Result[Unit, CycleError] raise Failure { @kernel.pull_verify(self.core, self.pull, self.accumulator_snapshots, cell_id) }`.

**3f (`kernel/push_propagate.mbt`)**:
- `PushEntry` priv struct + Eq/Compare impls move.
- `get_level(core, cell_id) -> Int`
- `recompute_level(core, _cell_id, sources) -> Int`
- `propagate_level_change(core, push, changed_cell, update_queue) -> Unit`
- `push_propagate_from(core, pull, push, datalog, changed_sources) -> Unit` — calls `enter_phase` / `leave_phase` (already kernel), `get_subscribers` (3a), tracking verbs (3d), `recompute_level` (same file).
- `moon.pkg` adds `moonbitlang/core/priority_queue` import.
- **Runtime wrapper stays** (D8 reserved list): `fn Runtime::push_propagate_from(self, changed_sources) -> Unit { @kernel.push_propagate_from(self.core, self.pull, self.push, self.datalog, changed_sources) }`.

**3g (`kernel/fixpoint.mbt`)**:
- `run_fixpoint(core, datalog) -> Array[CellId]` — returns the collected `changed_ids` array. Body matches `cells/datalog_fixpoint.mbt:12-106` verbatim except:
  - `self.core.phase` → `core.phase`
  - `self.datalog.*` → `datalog.*`
  - `self.is_cell_disposed(...)` → `is_cell_disposed(core, ...)` (3a)
  - `self.enter_phase` / `self.leave_phase` → `enter_phase(core, ...)` / `leave_phase(core)` (already kernel)
  - `self.publish_cell_changes(...)` — **stays on Runtime**, called from the wrapper (plan v3 item 3g).
- **Runtime wrapper kept as public API:**
  ```moonbit
  pub fn Runtime::fixpoint(self : Runtime) -> Unit {
    let changed_ids = @kernel.run_fixpoint(self.core, self.datalog)
    if changed_ids.length() > 0 {
      self.publish_cell_changes(changed_ids, Low)
    }
  }
  ```
  This wrapper collapses to a one-liner call after Stage 4 moves `publish_cell_changes` to kernel.

## 3. Wrappers dropped in Stage 3 (D8 policy)

Per D8, Runtime methods called only from internal cells/ code drop their wrappers; call-sites migrate to `@kernel.*` directly.

**Drop** (sweep cells/*.mbt call-sites during relevant sub-step):
- `get_level`, `recompute_level`, `propagate_level_change` (3f — internal to push_propagate)
- `push_contribution`, `collect_reachable_cells`, `adjust_push_reachable` (3a — mostly internal; used by subscriber helpers)
- `cell_id_at`, `cell_id_for`, `get_subscribers` (3a — widely used; **keep** simple wrappers given call-site count, but evaluate during sweep)
- `add_subscriber`, `remove_subscriber` (3a — called from 3-4 handle files; **keep** wrappers for readability)
- `diff_and_update_subscribers` (3c — only finish_tracking calls it; drop)
- `collect_tracking_path`, `collect_in_progress_path` (3d — drop; only verify + cycle ctor use them, both kernel-side after 3e)
- `begin_tracking`, `end_tracking` (3d — these are already thin wrappers; consider dropping in favour of direct `@kernel.push_tracking` / `@kernel.pop_tracking` at the 6-or-so handle call-sites, keeping only `finish_tracking`)

**Keep** (D8 reserved — public API or high-fan-out protocol verbs):
- `pull_verify`, `push_propagate_from`, `propagate_changes`, `publish_cell_changes`, `finish_tracking`, `top_active_query` — widely called; wrappers collapse to one-line delegations.
- `dispose_cell`, `dispose_rule`, `gc`, `batch`, `set_on_change`, `clear_on_change`, `fixpoint` — public API.
- `validate_cell`, `validate_cell_soft`, `is_cell_disposed`, `get_changed_at`, `get_durability` — used across many internal files; lean wrapper keeps grep-ability.

## 4. Per-sub-step verification gates

After **each** commit:

- `moon check`: green, zero warnings.
- `moon test`: 559/559 (Stage 2 baseline) — no test file moves in Stage 3 except under 3c/3d/3e/3f (see §6).
- `moon info && moon fmt`: `.mbti` diff shows only additive kernel surface + expected removals of wrappers we dropped.
- `moon bench --release` on wasm-gc: `tests/bench_test.mbt` + `cells/push_efficiency_bench_test.mbt`. Every tight-σ row within ±2% of [pre-R1 baseline](../performance/2026-04-21-pre-r1-baseline.md). Any row outside noise blocks the sub-step.

**If a sub-step regresses >2%:** stop. Diagnose:
1. Parameter-count overhead? MoonBit inliner may not close a 4-or-5-arg gap through a Runtime wrapper + kernel fn. Batch refs into a transient struct (anti-pattern — only if diagnosed).
2. Field-access pattern? `core.X` through `priv core : RuntimeCore` is a heap indirection per read; cluster reads into locals.
3. Closure-field semantics? Stage 2 §1 flagged name-collision; verify this didn't recur.

Commit-local fixes land as additional commits on the branch; don't merge the PR until all sub-steps are clean.

## 5. Test migration

Whitebox tests move with subjects:

- `cells/tracking_wbtest.mbt` → `cells/internal/kernel/tracking_wbtest.mbt` (moves in 3d)
- `cells/subscriber_diff_wbtest.mbt` → `kernel/subscriber_diff_wbtest.mbt` (3c)
- `cells/subscriber_link_wbtest.mbt` → `kernel/subscriber_link_wbtest.mbt` (3c)
- `cells/push_reachable_wbtest.mbt` → `kernel/push_reachable_wbtest.mbt` (3c — reachable helpers moved in 3a, but the wbtest asserts the combined behaviour; park in 3c alongside subscriber ones)
- `cells/verify_wbtest.mbt` → `kernel/verify_wbtest.mbt` (3e)
- `cells/pull_verify_wbtest.mbt` → `kernel/pull_verify_wbtest.mbt` (3e — check if this differs from verify_wbtest; if redundant, merge)

**Blackbox tests stay put** — they touch only `@incr` public API, which is unchanged:
- `cells/verify_path_test.mbt` (uses Runtime + Signal/Memo; blackbox)
- `cells/callback_test.mbt`, `cells/on_change_test.mbt` (run in Stage 4 ordering check)
- `cells/cycle_test.mbt`, `cells/cycle_path_test.mbt`

## 6. Cells/ file dispositions

| File | Disposition |
|---|---|
| `cells/verify.mbt` | Delete after 3e (body moves; Runtime wrapper lives in `runtime.mbt` per D8 reserved list). |
| `cells/push_propagate.mbt` | Delete after 3f (same pattern). |
| `cells/datalog_fixpoint.mbt` | Shrinks to just the `Runtime::fixpoint` wrapper (~10 LOC). Keep file for now; Stage 4 removes the wrapper entirely. |
| `cells/cycle.mbt` | Delete after 3b. Sole export was `CycleError::from_path(rt, ...)`. |
| `cells/subscriber_diff.mbt` | Delete after 3c. |
| `cells/tracking.mbt` | Shrinks to Tracker trait impls + `Runtime::finish_tracking`/`top_active_query` wrappers. Keep file; further trimming in Stage 5 per D8 sweep. |
| `cells/batch.mbt` | **Unchanged** in Stage 3. `commit_batch` moves in Stage 4. |

## 7. Cells-side adjustments per commit

Commit 3a (dispatch helpers):
- Sweep all cells/*.mbt for `self.core.cell_ops[...]`, `self.core.cell_index[...]`, `self.get_subscribers(...)`, `self.is_cell_disposed(...)`, `self.validate_cell*(...)` — leave non-dropped wrappers; rewrite call-sites for dropped ones.
- `kernel_using.mbt` may need additions (currently unknown content — sub-agent check).

Commit 3e (verify):
- Delete `cells/verify.mbt` (except Runtime wrapper relocates to `runtime.mbt`).
- Wrapper: `fn Runtime::pull_verify(self, id) -> Result[Unit, CycleError] raise Failure { @kernel.pull_verify(self.core, self.pull, self.accumulator_snapshots, id) }`. Place it near the other `priv` dispatch helpers in `runtime.mbt` to keep Stage 5 line-count target in sight.

Commit 3f (push_propagate):
- Delete `cells/push_propagate.mbt`. Wrapper moves to `runtime.mbt`.

Commit 3g (fixpoint):
- `cells/datalog_fixpoint.mbt` keeps only the `pub fn Runtime::fixpoint` wrapper described in §2 3g. Delete the internal helper bodies.

## 8. Doc updates (inline with this stage)

- `docs/design/internals.md` — File Map section: update cells/ entries for verify/push_propagate/cycle/subscriber_diff/tracking to reflect kernel-relocation; extend kernel section with Stage 3 contents.
- `CLAUDE.md` (incr root) package map: add kernel/dispatch, verify, push_propagate, tracking, subscriber_diff, cycle, fixpoint to the kernel file list.

## 9. Out of scope (explicit)

- `commit_batch` move → Stage 4.
- `propagate_changes`, `publish_cell_changes`, `fire_on_change` moves → Stage 4.
- `dispose` coordinator, `gc` → Stage 4.
- `CellLifecycle` trait retype to take `RuntimeCore` — out of R1 scope entirely.
- Any public API signature change.
- Any `.mbti` churn beyond additive kernel surface + D8-sweep removals.

## 10. Verification gate (Stage-level)

Before PR merges:

- All 7 sub-commits green per §4.
- `scripts/check-engine-isolation.sh` green (kernel direction still unenforced — Stage 5).
- Full `moon test`: 559/559 (or higher if any new kernel-direct wbtests added opportunistically per plan § Testing Strategy).
- wasm-gc bench delta vs baseline: every tight-σ row within ±2%.
- `pkg.generated.mbti` diff: shows only additive kernel surface + removal of D8-dropped wrapper signatures.
- Codex post-implementation review before merge (Stage 2 pattern — pre-review here; post-review on PR).

## 11. Risks specific to Stage 3

| # | Risk | Mitigation |
|---|---|---|
| S3-1 | Verify body (~290 LOC) is the largest single move; boundary rewriting misses a `self.*` → `core.*` substitution. | Sub-agent translation pass restricted to verify.mbt; `moon check` catches immediately. |
| S3-2 | Recursive `pull_verify` call inside `synthetic_accumulator_changed` drops `slot_snapshots` parameter → compile error but silent semantic equivalent from borrowing parent frame's binding. | Explicit review: grep for `pull_verify(` inside kernel/verify.mbt after move; must be exactly 4 args. |
| S3-3 | `propagate_level_change` uses `push : PushState` — but the BFS walks through `core.cell_ops[sub_id.id]`-driven subscriber sets which return CellIds spanning all engine types. Dispatch via `core.cell_index` may need `pull`/`datalog` passed too (pull/hybrid memo case already wants `pull.memos`). | Plan lists `(core, push)` — verify the actual match-arms at move time; extend signature if BFS touches pull/hybrid. |
| S3-4 | D8 wrapper drops trigger noisy diffs across 5-10 cells/*.mbt files; reviewer bandwidth. | Each sub-step's wrapper sweep lands in its own commit. PR description lists the swept call-sites explicitly. |
| S3-5 | `collect_in_progress_path` lives in `cells/introspection.mbt` (not tracking.mbt as plan says). If moved in 3d, `introspection.mbt` loses a helper it doesn't actually call itself — verify only verify.mbt uses it. | grep confirms — verify.mbt is the sole caller. Move is clean. |
| S3-6 | Bench regression on `push propagate` or `memo: wide fanout` rows from the two-arg/four-arg wrapper-through-kernel indirection. | Per-sub-step bench gate. If >2%, try sub-struct batching as last resort; otherwise keep the wrapper inlined. |

## 12. Open questions for Codex pre-review

1. Is the option-4 (`accumulator_snapshots` stays on Runtime, passed explicitly) the right call, or is there a subtle reason the Stage-2 post-review pushed for moving it to RuntimeCore?
2. Does the `propagate_level_change` signature need `(core, push)` or `(core, pull, push)`? BFS walks `core.cell_index` branches into PushReactive/PushEffect (push) and pull/hybrid memo (pull) — inspect current code to confirm.
3. Is `collect_in_progress_path` being moved in 3d rather than 3e (with its sole caller) the right choice? 3e is arguably more cohesive since the helper is verify-specific.
4. Should `begin_tracking`/`end_tracking` thin wrappers actually drop or stay? They're called from ~4 files; tradeoff between call-site readability and D8 policy. Leaning drop — verify this matches Codex's D8 reading.
5. The `validate_cell(core, id, caller)` signature in 3a — currently it reads `self.core.runtime_id` + `self.core.cell_ops.length()`. Under kernel it's `(core, id, caller)` — uses `core.runtime_id` + `core.cell_ops.length()`. Clean. Confirm no hidden dependency on Runtime-level state.
6. Is there a risk that splitting `validate_cell` (hard-abort) vs `validate_cell_soft` (Bool) across the kernel boundary causes an inconsistency in error-reporting semantics (e.g. a `validate_cell_soft`-using path in cells/ vs a `validate_cell`-using path in kernel giving different messages)? Both exist today on Runtime side-by-side, so shouldn't change — but worth a sanity check.

## 13. Cost estimate

Plan v3 § "Cost Estimate" gave Stage 3 as 1.5–3 days focused effort. Sub-step breakdown:

| Commit | Optimistic | Realistic |
|---|---|---|
| 3a (dispatch) | 2 hours | 4 hours (sweep is wide) |
| 3b (cycle) | 1 hour | 1.5 hours |
| 3c (subscriber_diff) | 1 hour | 2 hours |
| 3d (tracking) | 2 hours | 3 hours |
| 3e (verify) | 3 hours | 5 hours (largest body; sub-agent translation sensible) |
| 3f (push_propagate) | 2 hours | 4 hours (bench risk highest) |
| 3g (fixpoint) | 1.5 hours | 2 hours |
| Bench diagnosis buffer | — | 4 hours |
| Codex post-review + fixes | 2 hours | 3 hours |

**Total: 1.5 days optimistic / 3 days realistic.** Largest variance sits in 3f (push_propagate bench).
