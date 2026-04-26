# R1 Stage 4 — Execution Notes

**Date:** 2026-04-24
**Basis:** [R1 plan v3 § Stage 4](2026-04-21-r1-engine-package-split.md) + [Stage 3 execution notes](2026-04-24-r1-stage3-notes.md)
**Purpose:** Concrete spec for Stage 4 (coordinator primitives). Parallels the Stage 3 notes structure. This doc supersedes plan v3 § Stage 4 for **mechanics** where they differ; any substantive mechanics change requires Codex pre-review sign-off (tracked in §0).

## 0. Codex pre-implementation review verdict (2026-04-24)

**IMPLEMENT WITH CHANGES.** Ten corrections folded in below; sections 1–12 are then authoritative.

### Corrections folded in

**C1. `check_dispose_guard` keeps the `cell_id` parameter.** The notes' §2.C shape was wrong. Current `guard_dispose(self, cell_id)` (`cells/runtime.mbt:388-397`) aborts on fixpoint OR when any `ActiveQuery.cell_id == cell_id`, not on arbitrary active computation. Kernel signature must be `check_dispose_guard(core : RuntimeCore, cell_id : CellId) -> Unit`. Abort messages must match byte-for-byte: `"dispose: cannot dispose cells during fixpoint()"` and `"dispose: cannot dispose a cell during its own computation"`.

**C2. `propagate_changes` and `commit_batch` DO need `datalog`.** The notes' §2.A waffled about dropping it. Code shows the merged Stage 3 `push_propagate_from` signature is `(core, pull, push, datalog, changed_sources)` and it threads `datalog` into `diff_and_update_subscribers` in both reactive and effect paths (`cells/internal/kernel/push_propagate.mbt:113-120`, `:199-208`, `:239-247`). **Final signatures (no hedging):**
- `propagate_changes(core, pull, push, datalog, changed_ids, durability)`
- `publish_cell_changes(core, pull, push, datalog, changed_ids, durability)`
- `commit_batch(core, pull, push, datalog)`

**C3. `advance_revision` trait delegation overhead is a non-issue.** `bump_revision` short-circuits on `batch.depth > 0` (`cells/runtime.mbt:375-383`); `advance_revision` is called only at commit time, and the trait impl is statically resolved (`cells/cell_ops.mbt:31-37`). S4-4 risk removed.

**C4. `gc` must preserve active-computation cleanup before abort.** Before aborting on `!tracking.stack.is_empty()`, current `Runtime::gc` (`cells/runtime.mbt:459-464`) clears `core.tracking.stack` and resets `current_computing_runtime_id` to `-1` so panic-tests don't contaminate subsequent tests. Kernel `gc(core, dispose_fn)` must keep this exact cleanup path; the notes' §2.D was silent about it.

**C5. `commit_batch` preservation checklist expanded.** I4 is necessary but not sufficient. The kernel body must preserve:
- **Snapshot-before-propagate** — callbacks array built BEFORE `propagate_changes` (line 143-150 of `cells/batch.mbt`). [I4]
- **Callback-wave `while` loop** — outer `while pending.length() > 0` lets callback-queued signals process in later waves (line 127).
- **Temporary `batch.depth` raise around callback invocation** — line 158 prevents re-entrant `fire_on_change` from inside a callback; must raise and decrement in kernel too.
- **`any_changed` accumulator gate** — final global `fire_on_change` fires **once** at end if any wave produced changes (line 169-171).
- **`max_durability = Low` reset on BOTH paths** — both the `if changed.length() > 0` branch (line 153) and the else branch (line 164), plus a final reset at line 167. All three must persist.
- **Test coverage reminder** — `cells/callback_test.mbt:163-175` (single global fire across multi-wave), `cells/on_change_test.mbt:24-35,74-85` (no global during batch), `cells/committable_wbtest.mbt:29-48` (per-cell snapshot).

**C6. `get_pull_signal` inline must call `validate_cell` first.** Current `cells/runtime.mbt:229-237` calls `self.validate_cell(id, "get_pull_signal")` before the match. Kernel inline must use `@kernel.validate_cell(core, cell_id, "get_pull_signal")` (already present at `kernel/dispatch.mbt:12-19`) to preserve the cross-runtime abort semantics.

**C7. `Runtime::fixpoint` does NOT collapse to a one-line kernel call.** Notes §2.B claimed this. Reality: `@kernel.run_fixpoint` returns `Array[CellId]` and does not publish (`cells/internal/kernel/fixpoint.mbt:15-18,93-109`). Stage 4 scope is just rewriting `self.publish_cell_changes(...)` → `@kernel.publish_cell_changes(self.core, self.pull, self.push, self.datalog, changed_ids, Low)` inside the wrapper. The wrapper stays multi-line unless a future stage changes `run_fixpoint` itself.

**C8. `Runtime::fire_on_change` CANNOT be dropped in 4b.** Notes §3 / §2.A considered dropping it. Reality: `cells/signal.mbt:225-233` (the non-batch signal path) calls `self.rt.fire_on_change()` directly after per-cell callback dispatch. Options: (a) keep the Runtime wrapper through Stage 4 (recommended — D8 trivial delegator); (b) rewrite `signal.mbt:225-233` to `@kernel.fire_on_change(self.rt.core)` in 4a. Choose (a) for minimal churn.

**C9. `cells/batch_wbtest.mbt` stays in cells/ with a retained 1-line `Runtime::commit_batch` wrapper.** Codex's initial recommendation was "move to kernel"; follow-up verification (2026-04-24) shows the move is unnecessary: `rt.core.batch.*`, `rt.core.revision.*` etc. are accessible from cells/ because `RuntimeCore`/`BatchState`/`RevisionState` are `pub(all)` in kernel, and `rt.commit_batch()` / `rt.get_pull_signal(...)` are already Runtime methods that survive as thin wrappers after Stage 4. Disposition: keep `fn Runtime::commit_batch(self) { @kernel.commit_batch(self.core, self.pull, self.push, self.datalog) }` as a private 1-line wrapper (treat as D8 reserved for test readability), leave the wbtest file where it is. Same rule for `rt.get_pull_signal`: keep the existing Runtime method; no need to expose kernel's.

**C10. Both `cells/dispose_test.mbt` AND `cells/dispose_wbtest.mbt` exist.** Notes §5 hedged "(if exists)." Both stay in cells/ (blackbox / test through public API) and must run green after 4c + 4d. Name them explicitly.

**C11. Follow-up verifications (2026-04-24, post-Codex).**
- `fire_on_change` cells-side callers (non-test, non-doc): `cells/batch.mbt:170` (moves in 4b), `cells/signal.mbt:233` (stays), `cells/runtime.mbt:358` (moves in 4a with publish_cell_changes). Confirmed C8's single non-batch caller.
- `propagate_changes` callers: `cells/batch.mbt:152` (moves), `cells/signal.mbt:228` (stays). Runtime wrapper stays (D8 reserved).
- `publish_cell_changes` caller: `cells/datalog_fixpoint.mbt:6`. Runtime wrapper stays.
- `advance_revision` self-reference: `Runtime::bump_revision` calls `self.advance_revision(durability)` via trait self-dispatch (`cells/runtime.mbt:383`). Clean post-Stage-4 shape: kernel free fn `advance_revision(core, durability)` lives in `kernel/propagate.mbt`; Runtime's `impl RevisionManager for Runtime with advance_revision` body becomes `@kernel.advance_revision(self.core, durability)`. `bump_revision` impl stays local (still reads batch state and delegates). No Runtime trait impl removal needed.
- Callback ordering inside commit_batch snapshot: `for c in changed { push cb }` uses insertion-order iteration. Kernel must use the same for-loop shape (not iterator/map transforms) to preserve ordering.
- `get_pull_signal` kernel-side: with C9, `commit_batch` becomes the only kernel caller. Inline match in `kernel/batch.mbt` using `core.cell_index[id.id]` destructuring is cleanest (no dispatch helper promotion).

### C-set impact on body sections

- §1.2 (gc_sweep callback) — stands; C4 adds active-computation cleanup requirement.
- §1.3 (advance_revision) — simplified; C3 removes the "leaning inline" hedge.
- §2.A (propagate) — C2 locks datalog in; C8 defers fire_on_change wrapper drop.
- §2.B (batch) — C5 replaces the bullet list with the full preservation checklist; C6 notes validate_cell prefix; C7 corrects the fixpoint-wrapper claim.
- §2.C (dispose pure-state) — C1 fixes the helper signatures and abort messages.
- §2.D (gc) — C4 adds the active-computation cleanup step.
- §2.E (test migration) — C9 upgrades batch_wbtest move from optional to required; C10 names dispose tests.
- §5 (test migration summary) — updated per C9, C10.
- §10 (risks) — S4-4 removed per C3; S4-1 wording strengthened per C5 (the four-point checklist is the mitigation, not just "byte-for-byte preservation").
- §11 (open questions) — Q3, Q4 answered (C3, C6); Q1, Q2, Q5, Q6 remain for post-implementation review attention.

## 1. Resolved design questions

### 1.1 `on_change` field stays on `RuntimeCore` — no accessor trait

Stage 2 placed `on_change : (() -> Unit)?` on `RuntimeCore` (`cells/internal/kernel/state.mbt:203`). Once `propagate_changes` + `fire_on_change` move to kernel, they read `core.on_change` directly. **No `SlotSnapshot`-style accessor is needed.**

Why this differs from the accumulator case: accumulator state (`SlotMeta`) is a cells/-owned struct that kernel must not name; the `SlotSnapshot` trait is the minimal boundary. `on_change` is a plain closure with no cells/-only types — it's already state, not handle surface. Moving it would be churn for no boundary benefit.

### 1.2 `gc_sweep` dispose injection pattern

Plan v3 § Stage 4 lists `gc_sweep` as a kernel move. But `gc_sweep` currently calls `self.dispose_cell(id)` (`cells/runtime.mbt:535`), which dispatches through `CellLifecycle::dispose_cell(self, rt : Runtime, cell_id)` (`cells/cell_ops.mbt:52`). The trait takes `Runtime`, not `RuntimeCore` — retyping is explicitly out of R1 scope (plan v3 D1 + Stage 4 body).

**Resolution:** kernel `gc_sweep` takes a `dispose_fn : (CellId) -> Unit` callback parameter; `Runtime::gc` wrapper closes over `self.dispose_cell`:

```moonbit
pub fn Runtime::gc(self : Runtime) -> Unit {
  @kernel.gc(self.core, fn(id) { self.dispose_cell(id) })
}
```

Kernel `gc` / `gc_sweep` never mention `Runtime`. This mirrors the plan's Stage 4 treatment of `dispose_cell` itself (orchestration stays on Runtime; pure-state bits move) and keeps kernel/cells boundary clean.

Alternative considered + rejected: have `gc_sweep` return `Array[CellId]` and let `Runtime::gc` do the dispose loop. Rejected because gc phase management (`enter_phase(GarbageCollecting)` / `leave_phase()`) wraps the sweep — splitting would force phase management to live outside the algorithm that depends on it.

### 1.3 `RevisionManager` trait stays on Runtime; `advance_revision` body moves to kernel

`advance_revision` / `bump_revision` live as a private `RevisionManager` trait impl on Runtime (`cells/cell_ops.mbt:35`, `cells/runtime.mbt:363,375`). Bodies read only `RuntimeCore` state. Callers: `cells/signal.mbt:268,293` (bump_revision), `cells/runtime.mbt:338,383` (internal), and `bump_revision` self-calls `self.advance_revision` via trait dispatch.

**Resolution (finalized per C3/C11):**
- Kernel free fn `advance_revision(core : RuntimeCore, durability : Durability) -> Unit` in `kernel/propagate.mbt`.
- Runtime's `impl RevisionManager for Runtime with advance_revision` body becomes a one-line `@kernel.advance_revision(self.core, durability)`.
- `bump_revision` impl stays local; it continues to short-circuit on `batch.depth > 0` and self-dispatch to `self.advance_revision(durability)`. No overhead concern (C3): static trait dispatch + only called at batch commit. S4-4 risk removed.

## 2. Ordering (strict leaf-first)

Stage 4 ships as **one PR, multiple commits**. Callees before callers.

| Commit | Target file(s) | LOC (est.) | Depends on |
|---|---|---|---|
| 4a | `kernel/propagate.mbt` (new) + `runtime.mbt` rewire | ~85 | Stage 3 kernel fns (push_propagate_from, enter/leave_phase) |
| 4b | `kernel/batch.mbt` (new) + `batch.mbt` rewire | ~65 | 4a (propagate_changes, fire_on_change) |
| 4c | `kernel/dispose.mbt` (new) + `runtime.mbt` rewire | ~30 | none |
| 4d | `kernel/gc.mbt` (new) + `runtime.mbt` rewire | ~120 | 4c (dispose callback path) |
| 4e | Docs + internals.md + CLAUDE.md updates | — | 4a–4d |

Test-file moves: none required this stage (per C9 and C10).

### 2.A Commit 4a — `kernel/propagate.mbt`

**Functions (kernel, all `pub`):**

```moonbit
fn advance_revision(core : RuntimeCore, durability : Durability) -> Unit
fn fire_on_change(core : RuntimeCore) -> Unit
fn propagate_changes(
  core : RuntimeCore, pull : PullState, push : PushState, datalog : DatalogState,
  changed_ids : Array[CellId], durability : Durability,
) -> Unit
fn publish_cell_changes(
  core : RuntimeCore, pull : PullState, push : PushState, datalog : DatalogState,
  changed_ids : Array[CellId], durability : Durability,
) -> Unit
```

**Signatures locked (C2):** `datalog` is required on `propagate_changes` and `publish_cell_changes` because they call `push_propagate_from(core, pull, push, datalog, changed_ids)` (merged Stage 3 signature, `kernel/push_propagate.mbt`). No hedging.

**Body rewrites from `cells/runtime.mbt`:**

- `advance_revision` — body from `cells/runtime.mbt:363-370` verbatim with `self.core` → `core`.
- `fire_on_change` — body from `cells/runtime.mbt:323-327` verbatim.
- `propagate_changes` — body from `cells/runtime.mbt:333-347`:
  - `self.advance_revision(durability)` → `advance_revision(core, durability)` (same file).
  - `self.core.cell_ops[id.id].set_changed_at(self.core.revision.current_revision)` → `core.cell_ops[id.id].set_changed_at(core.revision.current_revision)`.
  - `self.push.node_count > 0` → `push.node_count > 0`.
  - `self.push_propagate_from(changed_ids)` → `push_propagate_from(core, pull, push, datalog, changed_ids)`.
- `publish_cell_changes` — body from `cells/runtime.mbt:352-359`: calls `propagate_changes(...)` then `fire_on_change(core)`.

**Runtime wrappers (all kept, per C8 + C11):**

- `impl RevisionManager for Runtime with advance_revision(self, durability) { @kernel.advance_revision(self.core, durability) }` — keeps the trait; bump_revision self-dispatches as before.
- `fn Runtime::fire_on_change(self) { @kernel.fire_on_change(self.core) }` — priv; kept for `cells/signal.mbt:233`.
- `fn Runtime::propagate_changes(self, changed_ids, durability) { @kernel.propagate_changes(self.core, self.pull, self.push, self.datalog, changed_ids, durability) }` — priv; kept for `cells/signal.mbt:228`. D8 reserved.
- `fn Runtime::publish_cell_changes(self, changed_ids, durability) { @kernel.publish_cell_changes(self.core, self.pull, self.push, self.datalog, changed_ids, durability) }` — priv; kept for `cells/datalog_fixpoint.mbt:6`. D8 reserved.
- `Runtime::set_on_change` / `Runtime::clear_on_change` — public, unchanged.

**Fixpoint wrapper update (C7):** `cells/datalog_fixpoint.mbt:6` changes from `self.publish_cell_changes(...)` to remain `self.publish_cell_changes(...)` — the Runtime wrapper still exists and now delegates to kernel. **No change to fixpoint wrapper source.** The wrapper does NOT collapse to a single line this stage; `@kernel.run_fixpoint` still returns `Array[CellId]` and the "if length > 0 then publish" dance stays in the wrapper body.

**Commit 4a verification:**
- `moon check && moon test` green.
- `moon info && moon fmt` — `.mbti` diff: additions only (kernel fns become visible). No Runtime method signature change.
- `moon bench --release` on wasm-gc: tight-σ rows within ±2% of [pre-R1 baseline](../performance/2026-04-21-pre-r1-baseline.md). Focus rows: `propagate changes`, `push propagate`.

### 2.B Commit 4b — `kernel/batch.mbt` (commit_batch body)

**Function (kernel, pub):**

```moonbit
fn commit_batch(
  core : RuntimeCore, pull : PullState, push : PushState, datalog : DatalogState,
) -> Unit
```

Body from `cells/batch.mbt:125-172`. Rewrites:

- `self.core.batch.*` → `core.batch.*` throughout.
- `self.get_pull_signal(c.cell_id())` → inline match:
  ```moonbit
  @kernel.validate_cell(core, c.cell_id(), "get_pull_signal")
  let sig = match core.cell_index[c.cell_id().id] {
    PullSignal(idx) => pull.signals[idx]
    _ => abort("Expected signal cell but found different kind: " + c.cell_id().id.to_string())
  }
  ```
  (C6 + C11: validate_cell prefix required; inline stays — no dispatch helper promotion since this is the only kernel caller.)
- `self.propagate_changes(changed_ids, self.core.batch.max_durability)` → `propagate_changes(core, pull, push, datalog, changed_ids, core.batch.max_durability)`.
- `self.fire_on_change()` → `fire_on_change(core)`.

**Preservation checklist — I4 AND supporting invariants (C5, all must hold byte-for-byte):**

1. **Snapshot-before-propagate** [I4]: callbacks array built from `changed` via `for c in changed { match sig.on_change { Some(f) => callbacks.push(f); None => () } }` BEFORE `propagate_changes(...)` executes. Loop shape must be `for c in changed` (insertion-order iteration), not `map`/`filter`/`iter` transforms.
2. **Outer `while pending.length() > 0` wave loop**: callback-queued signals process in later waves. Preserved verbatim.
3. **Temporary `batch.depth = batch.depth + 1` raise around `for cb in callbacks { cb() }`**: prevents re-entrant `fire_on_change` when a callback calls `Signal::set`. Both raise (`core.batch.depth = core.batch.depth + 1`) and decrement (`core.batch.depth = core.batch.depth - 1`) must bracket the callback loop.
4. **`any_changed` accumulator**: local `mut any_changed = false` is set to `true` iff any wave had `changed.length() > 0`; the final global `fire_on_change(core)` fires once at end if `any_changed`.
5. **`max_durability = Low` reset on all three sites**:
   - End of the `if changed.length() > 0` branch (after propagate + callbacks).
   - End of the `else` branch (no changes in this wave).
   - Final reset after the while loop exits.
   All three must persist; dropping any creates a cross-wave durability leak.

**Test coverage (run after 4b):**
- `cells/callback_test.mbt` — single global fire across multi-wave (`cells/callback_test.mbt:163-175`).
- `cells/on_change_test.mbt` — no global during batch (`cells/on_change_test.mbt:24-35`, `:74-85`).
- `cells/committable_wbtest.mbt:29-48` — per-cell callback snapshot ordering.
- `cells/batch_wbtest.mbt` — wbtest stays in place (C9); exercises `rt.commit_batch()` via the retained Runtime wrapper.

**Runtime wrappers:**

- `Runtime::batch` (public, `cells/batch.mbt`): inside it, `self.commit_batch()` call (line 64) is unchanged textually — `Runtime::commit_batch` wrapper is kept per C9.
- `fn Runtime::commit_batch(self) { @kernel.commit_batch(self.core, self.pull, self.push, self.datalog) }` — priv, 1-line. D8-kept for `batch()` caller + `batch_wbtest.mbt` direct calls.

**Commit 4b verification:** Full `moon test`. Wasm-gc bench: `batch commit wave`, `propagate changes` within ±2%. Manual inspection of `callback_test.mbt` + `on_change_test.mbt` output for any ordering diff vs pre-4b run.

### 2.C Commit 4c — `kernel/dispose.mbt` (pure-state helpers)

**Functions (kernel, all `pub`, per C1 shape):**

```moonbit
fn validate_cell_for_dispose(core : RuntimeCore, cell_id : CellId) -> Bool
fn drop_gc_root(core : RuntimeCore, cell_id : CellId) -> Unit
fn check_dispose_guard(core : RuntimeCore, cell_id : CellId) -> Unit
```

- `validate_cell_for_dispose` — body from `cells/runtime.mbt:411-415`:
  ```moonbit
  guard cell_id.runtime_id == core.runtime_id else {
    abort("dispose_cell: CellId belongs to a different Runtime")
  }
  !is_cell_disposed(core, cell_id)  // true ⇒ proceed, false ⇒ already-disposed short-circuit
  ```
  Cross-runtime aborts with the current message; already-disposed returns `false`.
- `drop_gc_root` — `core.gc_root_counts.remove(cell_id)` (from `cells/runtime.mbt:419`).
- `check_dispose_guard(core, cell_id)` — body from `cells/runtime.mbt:388-397`:
  ```moonbit
  guard !(core.phase is InFixpoint) else {
    abort("dispose: cannot dispose cells during fixpoint()")
  }
  for aq in core.tracking.stack {
    guard aq.cell_id != cell_id else {
      abort("dispose: cannot dispose a cell during its own computation")
    }
  }
  ```
  Abort messages byte-identical to current (C1).

**Runtime wrapper (public, stays):**

```moonbit
pub fn Runtime::dispose_cell(self : Runtime, cell_id : CellId) -> Unit {
  guard @kernel.validate_cell_for_dispose(self.core, cell_id) else { return }
  @kernel.check_dispose_guard(self.core, cell_id)
  @kernel.drop_gc_root(self.core, cell_id)
  self.cell_lifecycle[cell_id.id].dispose_cell(self, cell_id)
}
```

- `Runtime::dispose_rule` — unchanged.
- `Runtime::guard_dispose` — **deleted**; sole caller migrates.

`CellLifecycle::dispose_cell` impls untouched (out of R1).

**Commit 4c verification:** `moon test` green. Panic tests for dispose messages (cross-runtime, fixpoint, self-computation) must show identical `abort(...)` strings.

### 2.D Commit 4d — `kernel/gc.mbt`

**Functions (kernel):**

```moonbit
pub fn add_gc_root(core : RuntimeCore, id : CellId) -> Int
pub fn remove_gc_root(core : RuntimeCore, id : CellId) -> Int
pub fn collect_gc_roots(core : RuntimeCore) -> Array[CellId]
pub fn mark_reachable(core : RuntimeCore, roots : Array[CellId]) -> @hashset.HashSet[CellId]
pub fn gc_sweep(core : RuntimeCore, dispose_fn : (CellId) -> Unit) -> Unit
pub fn gc(core : RuntimeCore, dispose_fn : (CellId) -> Unit) -> Unit
```

Bodies from `cells/runtime.mbt:426,442,477,497,524,458`.

**C4 — active-computation cleanup path in `gc` must be preserved:**

```moonbit
pub fn gc(core : RuntimeCore, dispose_fn : (CellId) -> Unit) -> Unit {
  guard core.tracking.stack.is_empty() else {
    // Clean up global state before aborting so panic tests don't
    // contaminate subsequent tests via current_computing_runtime_id.
    core.tracking.stack.clear()
    set_current_computing_runtime_id(-1)
    abort("gc: cannot run during active computation")
  }
  guard core.batch.depth == 0 else { abort("gc: cannot run during batch") }
  guard core.phase is Idle else {
    abort("gc: cannot run during " + core.phase.to_string())
  }
  enter_phase(core, GarbageCollecting)
  gc_sweep(core, dispose_fn)
  leave_phase(core)
}
```

The `core.tracking.stack.clear()` + `set_current_computing_runtime_id(-1)` sequence before the first abort is load-bearing for test isolation — must be byte-identical.

`gc_sweep` body rewrite: `self.dispose_cell(id)` → `dispose_fn(id)`.

**Runtime wrappers:**

- `pub fn Runtime::gc(self) { @kernel.gc(self.core, fn(id) { self.dispose_cell(id) }) }` — public API stays; closure capture is the dispose injection per §1.2.
- `Runtime::add_gc_root` / `Runtime::remove_gc_root` — `priv`. At 4d, grep `cells/` for callers:
  ```
  grep -rn 'add_gc_root\|remove_gc_root' cells/*.mbt | grep -v 'runtime.mbt'
  ```
  If ≥3 call-sites, keep 1-line Runtime wrappers (D8 readability). Otherwise drop and migrate call-sites to `@kernel.add_gc_root(self.rt.core, id)`.
- `Runtime::collect_gc_roots` / `Runtime::mark_reachable` / `Runtime::gc_sweep` — deleted; sole caller was `Runtime::gc`.

**Commit 4d verification:**
- Full `moon test` green.
- `cells/gc_test.mbt`, `cells/dispose_test.mbt`, `cells/dispose_wbtest.mbt` — all run green; phase/runtime-state abort messages byte-identical.
- Wasm-gc bench: no baseline-tracked gc row, so just `moon test` + no regressions on tracked rows.
- Closure-allocation measurement: if follow-up bench shows `Runtime::gc` allocates per-call, consider S4-2 mitigation.

### 2.E Commit 4e — Docs

- Update `docs/design/internals.md` File Map: cells/ entries for propagate/batch-commit/dispose-helpers/gc trimmed; kernel section adds `kernel/propagate.mbt`, `kernel/batch.mbt`, `kernel/dispose.mbt`, `kernel/gc.mbt` with one-line descriptions each.
- Update incr root `CLAUDE.md` package map to list the four new kernel files.
- No test-file moves this stage (per C9, C10).

## 3. Wrappers dropped / kept in Stage 4 (D8)

**Drop:**
- `Runtime::guard_dispose` (4c) — sole caller migrates to `@kernel.check_dispose_guard`.
- `Runtime::collect_gc_roots`, `Runtime::mark_reachable`, `Runtime::gc_sweep` (4d) — all were internal to `Runtime::gc`.
- `Runtime::add_gc_root` / `Runtime::remove_gc_root` — evaluate at 4d by grep; drop if <3 call-sites.

**Keep:**
- `Runtime::dispose_cell`, `Runtime::dispose_rule`, `Runtime::gc`, `Runtime::set_on_change`, `Runtime::clear_on_change`, `Runtime::batch`, `Runtime::batch_result`, `Runtime::fixpoint` — public API.
- `Runtime::propagate_changes`, `Runtime::publish_cell_changes` — D8 reserved (high fan-out; stays for signal/fixpoint callers).
- `Runtime::fire_on_change` — priv, kept for `signal.mbt:233` (C8).
- `Runtime::commit_batch` — priv 1-liner, kept for `batch()` caller + `batch_wbtest.mbt` direct calls (C9).
- `impl RevisionManager for Runtime` — both methods kept; bodies delegate to kernel.

## 4. Per-sub-step verification gates

After **each** commit:

- `moon check`: green, zero warnings.
- `moon test`: 559+ pass. Explicit attention to `callback_test.mbt`, `on_change_test.mbt`, `batch_wbtest.mbt` after 4a + 4b; to `dispose_test.mbt`, `dispose_wbtest.mbt`, `gc_test.mbt` after 4c + 4d.
- `moon info && moon fmt`: `.mbti` diff additive kernel surface + D8-dropped wrapper signatures only.
- `moon bench --release` on wasm-gc: tight-σ rows within ±2% of baseline.

**If regression >2%:** diagnostic checklist per Stage 3 notes §4 (parameter overhead, field-access clustering, closure-field name collision).

## 5. Test migration summary (post C9 + C10)

| Test file | Disposition | Post-stage verification |
|---|---|---|
| `cells/batch_wbtest.mbt` | **Stays in cells/** (C9). Uses retained `rt.commit_batch()` wrapper + `rt.get_pull_signal()`. | Run after 4b; ordering regressions inspected. |
| `cells/callback_test.mbt` | Stays (blackbox). | Run after 4a + 4b. |
| `cells/on_change_test.mbt` | Stays (blackbox). | Run after 4a + 4b. |
| `cells/committable_wbtest.mbt` | Stays (whitebox, but only reads cells-side state). | Run after 4b. |
| `cells/gc_test.mbt` | Stays (blackbox). | Run after 4d. |
| `cells/dispose_test.mbt` | Stays (blackbox, C10). | Run after 4c + 4d. |
| `cells/dispose_wbtest.mbt` | Stays (whitebox via `rt.core.*` pub(all) access, C10). | Run after 4c + 4d. |

No new kernel-direct wbtests required; each moved body is covered by existing blackbox/whitebox tests via Runtime wrappers.

## 6. Cells/ file dispositions

| File | Disposition |
|---|---|
| `cells/batch.mbt` | Shrinks slightly: `commit_batch` body moves to kernel but a 1-line `Runtime::commit_batch` wrapper stays (C9). Other helpers unchanged. |
| `cells/runtime.mbt` | Largest shrink: `propagate_changes`, `publish_cell_changes`, `fire_on_change` bodies moved (wrappers kept); `advance_revision` body moved (trait impl kept as delegator); `guard_dispose` deleted; `gc`/`collect_gc_roots`/`mark_reachable`/`gc_sweep` moved (only `Runtime::gc` wrapper remains); `add_gc_root`/`remove_gc_root` bodies moved (wrapper fate TBD per grep). Target ≤500 LOC (from 539); acceptable ≤600. |
| `cells/datalog_fixpoint.mbt` | Unchanged — `Runtime::fixpoint` stays multi-line (C7). `self.publish_cell_changes(...)` call still goes through the kept Runtime wrapper. |

## 7. Doc updates (inline with this stage)

- `docs/design/internals.md` File Map — update cells/ entries and add kernel/propagate, kernel/batch, kernel/dispose, kernel/gc.
- `CLAUDE.md` (incr root) package map — add same four kernel files.
- Archive this notes doc + Stage 3 notes at Stage 6, not Stage 4.

## 8. Out of scope (explicit)

- `CellLifecycle` trait retype to take `RuntimeCore` — out of R1 entirely.
- Subscriber-list or push-reachable micro-optimization surfaced by any bench — file as follow-up, do not fix in this PR.
- Any public API signature change.
- `scripts/check-engine-isolation.sh` extension — Stage 5.
- Archiving plan v3 — Stage 6.
- Moving `Runtime::fixpoint` wrapper to a single-line form — requires changing `run_fixpoint` return shape, out of Stage 4 scope (C7).

## 9. Verification gate (Stage-level, before PR merge)

- All 5 sub-commits green per §4.
- Full `moon test` (559+ pass).
- `scripts/check-engine-isolation.sh` green (kernel direction still unenforced — Stage 5).
- Wasm-gc bench delta vs baseline: every tight-σ row within ±2%.
- `pkg.generated.mbti` diff: additive kernel surface + D8-dropped wrapper signatures only. No public API signature change.
- **Codex post-implementation review mandatory** (plan v3 § Stage 4). Review prompt must explicitly cite I4 + the five-point commit_batch preservation checklist (§2.B) as the primary correctness risk.
- `cells/runtime.mbt` LOC ≤500 (target) or ≤600 (acceptable). Document actual in PR description.

## 10. Risks specific to Stage 4

| # | Risk | Mitigation |
|---|---|---|
| S4-1 | I4 + the four supporting commit_batch invariants (C5) broken by reordering/transforming the kernel body. | §2.B five-point preservation checklist verified line-by-line against `cells/batch.mbt:125-172`; post-4b run of callback/on_change/committable/batch_wbtest suites; Codex post-review cites the checklist. |
| S4-2 | `gc_sweep` dispose callback allocates per-`Runtime::gc` call. | Measure at 4d. Gc is user-initiated and rare; allocation likely not hot. If >2% gc bench (should one exist), file as follow-up — don't retype `CellLifecycle` inside Stage 4. |
| S4-3 | `propagate_changes` param list diverges from `push_propagate_from`. | C2 locks the signature: both take `(core, pull, push, datalog, ...)`. `moon check` catches any mismatch. |
| S4-4 | `cells/runtime.mbt` still >500 LOC after Stage 4. | Acceptable ≤600 per plan v3 Done Criteria. Document actual LOC; carry to Stage 5 sweep. |
| S4-5 | `validate_cell_for_dispose` returning `Bool` changes abort semantics vs current pattern. | Wrapper shape (§2.C) preserves cross-runtime abort inside the kernel fn + already-disposed short-circuit at wrapper. Panic-test strings byte-identical. |
| S4-6 | Closure capture in `Runtime::gc` wrapper forces heap allocation. | Verified by looking at `moon bench` gc row. If allocation shows, mitigations: named top-level fn (doesn't help — still captures self), or accept (gc is rare). Not a blocker. |
| S4-7 | `get_pull_signal` kernel-inline drift from `Runtime::get_pull_signal` error messages. | Both must abort with the same strings: `"Cell belongs to a different Runtime"` (from validate_cell) and `"Expected signal cell but found different kind: <id>"`. Check at 4b via panic tests. |

## 11. Open questions remaining (for post-implementation Codex review)

*Q3, Q4 resolved in §0 corrections (C3, C6, C11). Remaining:*

1. `Runtime::gc` closure `fn(id) { self.dispose_cell(id) }` — zero-cost via inlining, or does MoonBit keep the closure on the heap? Measurement at 4d decides whether S4-6 mitigation is needed.
2. `get_pull_signal` inline in `kernel/batch.mbt` vs promotion to `kernel/dispatch.mbt` — with C9's wbtest-stays decision, inline is the minimal change. If Stage 5 finds a second kernel caller, promote then.
3. I4 mechanism: beyond the five-point checklist, is there a deeper invariant (e.g. thread-safety of `core.on_change` reads) to stress-test? Current codebase is single-threaded so moot, but flag for Codex post-review if they see one.
4. Post-4b, is there value in a kernel-direct `commit_batch_wbtest.mbt` that constructs state without going through `Runtime::new`? Leaning no — `batch_wbtest.mbt` via retained wrapper gives adequate coverage.

## 12. Cost estimate

| Commit | Optimistic | Realistic |
|---|---|---|
| 4a (propagate + fire_on_change + advance_revision + publish_cell_changes) | 2 hours | 3 hours |
| 4b (commit_batch — I4 scrutiny) | 2 hours | 4 hours |
| 4c (dispose helpers) | 1 hour | 1.5 hours |
| 4d (gc family + dispose callback measurement) | 2 hours | 3 hours |
| 4e (docs) | 30 min | 1 hour |
| Bench diagnosis buffer | — | 3 hours |
| Codex post-review + fixes | 2 hours | 3 hours |

**Total: 1 day optimistic / 1.5–2 days realistic.**

