# Runtime Modularization Stage 5 (narrow) — Implementation Plan

> **Status:** Complete. Implemented on branch `refactor/incr-structure` (PR #39 against `dowdiness/incr`). All six tasks delivered as seven commits (`82f1eb4..b20e21c` on top of `b214d6f`). 506 tests pass, public API (`pkg.generated.mbti`) unchanged, isolation checker exits 0. The pull-engine split is partial by design — `MemoData` stays in `cells/` pending a `CycleError` redesign tracked in `docs/todo.md`. Document kept in `plans/` until the PR merges, then move to `plans/archive/` per the project archival convention.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `cells/` into a thinner coordinator plus `cells/internal/{shared,pull,push,datalog}/` engine sub-packages, without changing public API, algorithms, or handles.

**Architecture:** Option A (narrow). Shared traits + `CellMeta` + `CellRef` move to `cells/internal/shared/`. Only `PullSignalData` moves from the pull engine (memos stay because `MemoData.compute` references `CycleError`, which cannot leave `cells/`). Push and datalog SoA types move fully; their public handle types stay in `cells/`. A shell script enforces engine isolation and the no-back-edge invariant.

**Tech Stack:** MoonBit 0.1.20260409+, `moon` build system, `moon.pkg` import manifests, MoonBit `internal` package visibility. No new external dependencies.

**Authoritative spec:** [`docs/superpowers/specs/2026-04-18-incr-stage5-internal-split-design.md`](../../specs/2026-04-18-incr-stage5-internal-split-design.md). If this plan and the spec ever disagree, **the spec wins** — file a follow-up to update the plan.

**Worktree:** Branch `refactor/incr-structure` in `.worktrees/refactor-incr-structure`. All commands assume this is the current directory.

**Safety net:** The existing 506-test suite. No new behavioral tests are added; the only new test artifact is `scripts/check-engine-isolation.sh` added in Task 5.

**Per-step verification contract** (repeated because every task follows the same pattern):

```bash
moon check                          # must pass with zero errors
moon test                           # must report "passed: 506, failed: 0"
moon info && moon fmt               # regenerates .mbti, formats
git diff --exit-code pkg.generated.mbti tests/pkg.generated.mbti
                                    # must exit 0 (no public API drift)
```

If `moon check` fails, fix the import or visibility error before proceeding — do not commit in a red state.

---

## File map

Files created:
- `cells/internal/shared/moon.pkg`
- `cells/internal/shared/cell_meta.mbt`
- `cells/internal/shared/cell_ref.mbt`
- `cells/internal/shared/cell_ops.mbt`
- `cells/internal/pull/moon.pkg`
- `cells/internal/pull/pull_signal.mbt`
- `cells/pull_lifecycle.mbt`
- `cells/internal/push/moon.pkg`
- `cells/internal/push/push_reactive_data.mbt`
- `cells/internal/push/push_effect_data.mbt`
- `cells/push_lifecycle.mbt`
- `cells/internal/datalog/moon.pkg`
- `cells/internal/datalog/relation_data.mbt`
- `cells/internal/datalog/functional_relation_data.mbt`
- `cells/internal/datalog/rule_data.mbt`
- `cells/datalog_lifecycle.mbt`
- `scripts/check-engine-isolation.sh`

Files modified:
- `cells/cell.mbt` — add `using @shared { type CellRef }`
- `cells/cell_ops.mbt` — strip to `CellLifecycle` + defaults; import traits from shared
- `cells/cycle.mbt` — unchanged code, but keep the file (CycleError stays here)
- `cells/pull_memo.mbt` — unchanged (including `CellLifecycle for MemoData`)
- `cells/pull_signal.mbt` — delete after Task 2
- `cells/push_reactive.mbt` — file split (remove SoA + trait impls + `clear_slot`)
- `cells/push_effect.mbt` — file split (remove SoA + trait impls + `clear_slot`)
- `cells/datalog_relation.mbt` — file split (remove `RelationData` + impls)
- `cells/datalog_functional_relation.mbt` — file split (remove `FunctionalRelationData` + impls)
- `cells/datalog_rule.mbt` — file split (remove `RuleData` + impls; keep `Runtime::new_rule` + helpers)
- `cells/runtime.mbt`, `cells/verify.mbt`, `cells/batch.mbt`, `cells/signal.mbt`, `cells/memo.mbt`, `cells/hybrid_memo.mbt`, `cells/introspection.mbt`, `cells/scope.mbt`, `cells/datalog_fixpoint.mbt` — update imports as packages appear
- `cells/moon.pkg` — add `@shared`, `@pull`, `@push`, `@datalog` imports
- `cells/*_wbtest.mbt` — update imports for tests that touch moved SoA fields
- `CLAUDE.md` — refresh package map
- `docs/todo.md` — check off Stage 5 items (with a note about the partial pull split)
- `docs/design.md` — architecture section update
- `docs/README.md` — link to the spec

Files deleted:
- `cells/cell_ref.mbt` — content moved to `cells/internal/shared/cell_ref.mbt`
- `cells/pull_signal.mbt` — content moved to `cells/internal/pull/pull_signal.mbt`

---

## Task 1: Create `cells/internal/shared/` with trait + type definitions

**Files:**
- Create: `cells/internal/shared/moon.pkg`
- Create: `cells/internal/shared/cell_meta.mbt`
- Create: `cells/internal/shared/cell_ref.mbt`
- Create: `cells/internal/shared/cell_ops.mbt`
- Modify: `cells/cell_ops.mbt` (strip traits, keep `CellLifecycle`)
- Modify: `cells/cell.mbt` (add `using @shared { type CellRef }`)
- Modify: `cells/moon.pkg` (add `@shared` import)
- Delete: `cells/cell_ref.mbt`

- [x] **Step 1.1: Create `cells/internal/shared/moon.pkg`**

Write:

```text
import {
  "dowdiness/incr/types" @incr_types,
  "moonbitlang/core/hashset",
}
```

- [x] **Step 1.2: Create `cells/internal/shared/cell_meta.mbt`**

Copy the current `CellMeta` struct out of `cells/cell_ops.mbt` (lines ~17-30 in the pre-refactor source). Change visibility from `priv` to `pub(all)`. Add a `using @incr_types` chain so the field types resolve.

```moonbit
///|
using @incr_types {
  type CellId,
  type Revision,
  type Durability,
}

///|
/// Shared metadata fields carried by every cell kind.
///
/// Extracted from the per-type SoA data structs so that `CellOps` default
/// methods can delegate through `HasCellMeta::meta()` instead of requiring
/// identical one-liner impls on every cell type.
pub(all) struct CellMeta {
  cell_id : CellId
  mut label : String?
  mut changed_at : Revision
  mut durability : Durability
  subscribers : @hashset.HashSet[CellId]
  mut push_reachable_count : Int
}
```

- [x] **Step 1.3: Create `cells/internal/shared/cell_ref.mbt`**

Copy the current `CellRef` enum out of `cells/cell_ref.mbt`. Flip visibility to `pub(all)`.

```moonbit
///|
using @incr_types { type CellId }

///|
/// Tagged dispatch index for a cell. Stored in `RuntimeCore.cell_index`
/// and indexed by `CellId.id`.
pub(all) enum CellRef {
  PullSignal(Int)
  PullMemo(Int)
  PushReactive(Int)
  PushEffect(Int)
  HybridMemo(Int)
  Relation(Int)
  FunctionalRelation(Int)
  Rule(Int)
  Disposed
} derive(Eq, Show)
```

(Preserve any `derive` clauses that exist in the source today. Verify by reading the current `cells/cell_ref.mbt` before writing this file.)

- [x] **Step 1.4: Create `cells/internal/shared/cell_ops.mbt`**

Move `CellOps`, `HasCellMeta`, `Committable` traits and their default impls out of `cells/cell_ops.mbt`. Change visibility on trait declarations from `priv` to `pub(open)`. The default impls must be explicitly written out because MoonBit requires `impl Trait for Type` to be explicit even when defaults exist (verified in Phase 2 spec).

```moonbit
///|
using @incr_types {
  type CellId,
  type Revision,
  type Durability,
  type GcRole,
}

///|
/// Interface for signal cells that have pending values during a batch.
pub(open) trait Committable {
  do_commit(Self) -> Bool
  cell_id(Self) -> CellId
  durability(Self) -> Durability
}

///|
/// Returns a cell's shared metadata. Implemented by every SoA data struct.
pub(open) trait HasCellMeta {
  meta(Self) -> CellMeta
}

///|
/// Uniform interface for all cell kinds in the dependency graph.
pub(open) trait CellOps: HasCellMeta {
  cell_id(Self) -> CellId = _
  changed_at(Self) -> Revision = _
  set_changed_at(Self, Revision) -> Unit = _
  subscribers(Self) -> @hashset.HashSet[CellId] = _
  label(Self) -> String? = _
  durability(Self) -> Durability = _
  level(Self) -> Int = _
  dep_changed_since(Self, Revision) -> Bool? = _
  push_reachable_count(Self) -> Int = _
  gc_role(Self) -> GcRole = _
  gc_dependencies(Self) -> Array[CellId] = _
}

///|
impl CellOps with cell_id(self) -> CellId {
  HasCellMeta::meta(self).cell_id
}

///|
impl CellOps with changed_at(self) -> Revision {
  HasCellMeta::meta(self).changed_at
}

///|
impl CellOps with set_changed_at(self, rev) -> Unit {
  HasCellMeta::meta(self).changed_at = rev
}

///|
impl CellOps with subscribers(self) -> @hashset.HashSet[CellId] {
  HasCellMeta::meta(self).subscribers
}

///|
impl CellOps with label(self) -> String? {
  HasCellMeta::meta(self).label
}

///|
impl CellOps with durability(self) -> Durability {
  HasCellMeta::meta(self).durability
}
```

(Continue with the remaining default impls from the source file: `level`, `dep_changed_since`, `push_reachable_count`, `gc_role`, `gc_dependencies`. Copy their bodies verbatim from the current `cells/cell_ops.mbt`.)

- [x] **Step 1.5: Strip `cells/cell_ops.mbt` to only `CellLifecycle`**

Edit `cells/cell_ops.mbt` so that it keeps **only** the `CellLifecycle` trait and its two default impls (`on_observe`, `on_unobserve` both no-op). Remove `CellMeta`, `Committable`, `HasCellMeta`, `CellOps`, and all their default impls (those now live in `@shared`). Add a `using @shared { ... }` at the top so the rest of `cells/` still sees the trait names unqualified.

The file should look like:

```moonbit
///|
using @shared {
  type CellMeta,
  trait CellOps,
  trait HasCellMeta,
  trait Committable,
}

///|
using @incr_types { type CellId, type GcRole }

///|
/// Lifecycle operations for cells: disposal, observer notifications.
/// Stays in cells/ because method signatures take Runtime.
priv trait CellLifecycle {
  dispose_cell(Self, Runtime, CellId) -> Unit
  on_observe(Self, Runtime, CellId) -> Unit = _
  on_unobserve(Self, Runtime, CellId) -> Unit = _
}

///|
impl CellLifecycle with on_observe(_self, _rt, _cell_id) -> Unit {
  ()
}

///|
impl CellLifecycle with on_unobserve(_self, _rt, _cell_id) -> Unit {
  ()
}
```

- [x] **Step 1.6: Update `cells/cell.mbt` to re-export `CellRef`**

The current `cells/cell.mbt` is a `using @incr_types { ... }` alias file. Add a new `using @shared { type CellRef }` so that files in `cells/` can still refer to `CellRef` unqualified.

Show current content then add. The file becomes:

```moonbit
///|
using @incr_types {
  type CellId,
  type Durability,
  type GcRole,
  type Revision,
  trait BackdateEq,
}

///|
using @shared {
  type CellRef,
}
```

- [x] **Step 1.7: Delete `cells/cell_ref.mbt`**

```bash
rm cells/cell_ref.mbt
```

- [x] **Step 1.8: Update `cells/moon.pkg` to import `@shared`**

Current `cells/moon.pkg` is:

```text
import {
  "dowdiness/incr/types" @incr_types,
  "moonbitlang/core/debug",
  "moonbitlang/core/hashmap",
  "moonbitlang/core/hashset",
  "moonbitlang/core/priority_queue",
}

import {
  "moonbitlang/core/bench",
} for "test"

warnings = "-1-7-15"
```

Add `"dowdiness/incr/cells/internal/shared" @shared` to the first import block.

```text
import {
  "dowdiness/incr/types" @incr_types,
  "dowdiness/incr/cells/internal/shared" @shared,
  "moonbitlang/core/debug",
  "moonbitlang/core/hashmap",
  "moonbitlang/core/hashset",
  "moonbitlang/core/priority_queue",
}

import {
  "moonbitlang/core/bench",
} for "test"

warnings = "-1-7-15"
```

- [x] **Step 1.9: Run `moon check`**

Run: `moon check`
Expected: Pass with zero errors.

If there are errors about `CellMeta`, `CellRef`, `CellOps`, `Committable`, or `HasCellMeta` being unresolved in some `cells/*.mbt` file, fix by adding `using @shared { ... }` at the top of that file as needed. Do not flip the trait from `pub(open)` back — the resolution problem is on the consumer side, not the definition.

- [x] **Step 1.10: Run `moon test`**

Run: `moon test`
Expected: `Total tests: 506, passed: 506, failed: 0.`

If a wbtest fails because it accesses a field on a moved struct, that would indicate Step 1.2/1.3 missed a `pub(all)`. Verify every moved struct is `pub(all)`, not `pub`.

- [x] **Step 1.11: Regenerate `.mbti` and diff**

Run: `moon info && moon fmt`
Run: `git diff --exit-code pkg.generated.mbti tests/pkg.generated.mbti`
Expected: exit 0 (no diff).

If the root `.mbti` changed, the likely cause is that a trait or type moved through the `pub using` chain and its canonical name shifted. Investigate: run `git diff pkg.generated.mbti` and check whether a line like `pub trait CellOps` appears with a changed module path. If so, add the missing `pub using @shared { trait CellOps }` re-export in `cells/cell_ops.mbt` so the root facade still resolves to the same canonical path.

- [x] **Step 1.12: Commit**

```bash
git add cells/internal/shared/ cells/cell_ops.mbt cells/cell.mbt cells/moon.pkg pkg.generated.mbti tests/pkg.generated.mbti
git rm cells/cell_ref.mbt
git commit -m "refactor: extract cells/internal/shared trait+type package

Move CellOps, HasCellMeta, Committable, CellMeta, CellRef into
cells/internal/shared/. Trait visibility flipped to pub(open);
struct/enum visibility to pub(all) so cells/ can continue to
construct and mutate instances. Bounded by MoonBit \`internal\` —
no external visibility change.

CycleError, MemoData, and CellLifecycle all stay in cells/ because
their method signatures or payloads reference Runtime.
"
```

---

## Task 2: Move `PullSignalData` to `cells/internal/pull/`

**Files:**
- Create: `cells/internal/pull/moon.pkg`
- Create: `cells/internal/pull/pull_signal.mbt`
- Create: `cells/pull_lifecycle.mbt`
- Delete: `cells/pull_signal.mbt`
- Modify: `cells/runtime.mbt`, `cells/verify.mbt`, `cells/batch.mbt`, `cells/signal.mbt`, `cells/memo.mbt`, `cells/hybrid_memo.mbt`, `cells/introspection.mbt` (add `@pull` where needed)
- Modify: `cells/moon.pkg` (add `@pull` import)
- Modify: `cells/*_wbtest.mbt` that touch `PullSignalData`

- [x] **Step 2.1: Create `cells/internal/pull/moon.pkg`**

```text
import {
  "dowdiness/incr/types" @incr_types,
  "dowdiness/incr/cells/internal/shared" @shared,
  "moonbitlang/core/hashset",
}
```

(`hashmap` is not required per the Codex round-3 findings — `PullSignalData` itself uses neither. Re-add only if `moon check` later demands it.)

- [x] **Step 2.2: Move `PullSignalData` source from `cells/pull_signal.mbt` into `cells/internal/pull/pull_signal.mbt`**

Open `cells/pull_signal.mbt`. Find the `priv struct PullSignalData { ... }` declaration and all of its `impl` blocks for `CellOps`, `HasCellMeta`, `Committable`. Do not take the `impl CellLifecycle for PullSignalData` block — that moves to `cells/pull_lifecycle.mbt` in Step 2.3.

Write `cells/internal/pull/pull_signal.mbt` with:
- A `using @incr_types { ... }` block for `CellId`, `Revision`, `Durability`, `GcRole` as needed.
- A `using @shared { type CellMeta, trait CellOps, trait HasCellMeta, trait Committable }`.
- `pub(all) struct PullSignalData { ... }` — same fields as the source (change `priv` to `pub(all)`; fields keep whatever `mut` qualifier they had).
- `pub impl HasCellMeta for PullSignalData with meta(self) { self.meta }`
- `pub impl CellOps for PullSignalData` (empty override body — inherits defaults from the trait)
- `pub impl CellOps for PullSignalData with dep_changed_since(...)` — copy from source if present.
- `pub impl CellOps for PullSignalData with gc_role(...)` — copy.
- Any other `impl CellOps for PullSignalData with ...` method — copy, prefix with `pub`.
- `pub impl Committable for PullSignalData with do_commit(self) { ... }` — copy.
- `pub impl Committable for PullSignalData with cell_id(self) { self.meta.cell_id }` — copy.
- `pub impl Committable for PullSignalData with durability(self) { self.meta.durability }` — copy.

If `cells/pull_signal.mbt` declares any inherent methods on `PullSignalData` (grep: `rg 'fn PullSignalData::' cells/pull_signal.mbt`), move them over too and mark them `pub fn PullSignalData::<name>(...)`. An "inherent method" is a `fn Type::method(...)` declaration that is **not** inside an `impl Trait for Type` block.

Every moved impl must be prefixed with `pub` (e.g., `pub impl Trait for Type with method(...)`) so that `cells/` can dispatch via `&CellOps` / `&Committable`. Omitting `pub` on an impl causes a silent no-op — `moon check` passes but `&CellOps` dispatch fails at runtime. Be explicit on every impl line.

- [x] **Step 2.3: Create `cells/pull_lifecycle.mbt` holding the `PullSignalData` lifecycle impl**

This is a new file in `cells/`. It holds only:

```moonbit
///|
using @pull { type PullSignalData }
using @incr_types { type CellId }

///|
/// CellLifecycle impl for PullSignalData (signals).
/// Lives here rather than in internal/pull/ because it references
/// Runtime-only helpers that cannot leak into an internal package.
impl CellLifecycle for PullSignalData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  // Paste the body from the current cells/pull_signal.mbt's
  // `impl CellLifecycle for PullSignalData with dispose_cell(...)` block.
  ...
}
```

Fill in the body by copying from `cells/pull_signal.mbt`. Include any `with on_observe` or `with on_unobserve` impls if they exist (signals currently default them; skip if not overridden).

**Important:** do not use `...` in the final code. Replace with the actual copied body.

- [x] **Step 2.4: Delete `cells/pull_signal.mbt`**

```bash
rm cells/pull_signal.mbt
```

- [x] **Step 2.5: Update `cells/moon.pkg` to import `@pull`**

Append `"dowdiness/incr/cells/internal/pull" @pull,` to the first import block (in alphabetical order among the incr paths).

- [x] **Step 2.6: Update consumer imports in `cells/`**

For each of `cells/runtime.mbt`, `cells/verify.mbt`, `cells/batch.mbt`, `cells/signal.mbt`, `cells/memo.mbt`, `cells/hybrid_memo.mbt`, `cells/introspection.mbt`: add a top-of-file `using @pull { type PullSignalData }` if the file references `PullSignalData` unqualified.

Quick find: `rg -l 'PullSignalData' cells/*.mbt` — every file listed needs a `using @pull` (except the lifecycle file you just wrote, which already has one).

For whitebox tests that access `PullSignalData` fields: `rg -l 'PullSignalData' cells/*_wbtest.mbt` — each needs `using @pull { type PullSignalData }`. Because those files are in `cells/`, the `pub(all)` fields of `PullSignalData` are visible.

- [x] **Step 2.7: Run `moon check`**

Expected: pass with zero errors.

Likely issues: missing `using @pull` on some `cells/*.mbt` file; a field missed `pub(all)` and now cannot be set by `cells/runtime.mbt:291` or `cells/batch_wbtest.mbt:352`. Fix one error at a time.

- [x] **Step 2.8: Run `moon test`**

Expected: `passed: 506, failed: 0`.

- [x] **Step 2.9: Regenerate `.mbti` and diff**

Run: `moon info && moon fmt`
Run: `git diff --exit-code pkg.generated.mbti tests/pkg.generated.mbti`
Expected: exit 0.

- [x] **Step 2.10: Commit**

```bash
git add cells/internal/pull/ cells/pull_lifecycle.mbt cells/moon.pkg cells/runtime.mbt cells/verify.mbt cells/batch.mbt cells/signal.mbt cells/memo.mbt cells/hybrid_memo.mbt cells/introspection.mbt cells/*_wbtest.mbt pkg.generated.mbti tests/pkg.generated.mbti
git rm cells/pull_signal.mbt
git commit -m "refactor: move PullSignalData to cells/internal/pull

PullSignalData + its CellOps, HasCellMeta, and Committable impls
move to cells/internal/pull with pub(all) visibility. The trait
impls are marked pub impl so cells/ can dispatch through &CellOps
and &Committable across the package boundary.

MemoData stays in cells/ because its compute closure references
CycleError (which cannot leave cells/ without breaking the
format_path public method). Its CellLifecycle impl stays inside
cells/pull_memo.mbt alongside the struct. The PullSignalData
CellLifecycle impl moves to cells/pull_lifecycle.mbt.
"
```

---

## Task 3: Move push-engine SoA to `cells/internal/push/`, keep handles in `cells/`

**Files:**
- Create: `cells/internal/push/moon.pkg`
- Create: `cells/internal/push/push_reactive_data.mbt`
- Create: `cells/internal/push/push_effect_data.mbt`
- Create: `cells/push_lifecycle.mbt`
- Modify (file split): `cells/push_reactive.mbt`
- Modify (file split): `cells/push_effect.mbt`
- Modify: `cells/push_propagate.mbt`, `cells/runtime.mbt`, `cells/introspection.mbt`, `cells/scope.mbt`, `cells/moon.pkg`, `cells/*_wbtest.mbt`

- [x] **Step 3.1: Create `cells/internal/push/moon.pkg`**

```text
import {
  "dowdiness/incr/types" @incr_types,
  "dowdiness/incr/cells/internal/shared" @shared,
  "moonbitlang/core/hashset",
}
```

- [x] **Step 3.2: Create `cells/internal/push/push_reactive_data.mbt`**

Open `cells/push_reactive.mbt`. The file has two logical halves: (a) `PushReactiveData` struct + trait impls + `clear_slot` method — roughly lines 1-114 in the current source — and (b) `Reactive[T]` handle + constructor + user methods — roughly lines 116-257.

Write `cells/internal/push/push_reactive_data.mbt` with the SoA half:

1. `using @incr_types { ... }` and `using @shared { ... }` at the top.
2. `pub(all) struct PushReactiveData { ... }` — change from `priv` to `pub(all)`, preserve all fields.
3. `pub impl HasCellMeta for PushReactiveData with meta(self) { self.meta }`.
4. `pub impl CellOps for PushReactiveData` (empty — inherits defaults).
5. `pub impl CellOps for PushReactiveData with level(self) { ... }` — if the source has a custom level impl, copy it; mark `pub`.
6. Any other `impl CellOps for PushReactiveData with ...` — copy with `pub impl`.
7. `pub fn PushReactiveData::clear_slot(self : PushReactiveData) -> Unit { ... }` — copy the body.

Do **not** include `impl CellLifecycle for PushReactiveData` — that goes to `cells/push_lifecycle.mbt` in Step 3.4.

- [x] **Step 3.3: Create `cells/internal/push/push_effect_data.mbt`**

Same pattern as Step 3.2 but for `PushEffectData` (source: `cells/push_effect.mbt` lines ~1-89). Include `clear_slot` if present.

- [x] **Step 3.4: Create `cells/push_lifecycle.mbt`**

```moonbit
///|
using @push { type PushReactiveData, type PushEffectData }
using @incr_types { type CellId }

///|
impl CellLifecycle for PushReactiveData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  // Paste body from cells/push_reactive.mbt's dispose_cell impl.
}

// Include any on_observe / on_unobserve overrides:
impl CellLifecycle for PushReactiveData with on_observe(
  self,
  rt,
  cell_id,
) -> Unit {
  // Paste body from cells/push_reactive.mbt.
}

impl CellLifecycle for PushReactiveData with on_unobserve(
  self,
  rt,
  cell_id,
) -> Unit {
  // Paste body from cells/push_reactive.mbt.
}

///|
impl CellLifecycle for PushEffectData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  // Paste body from cells/push_effect.mbt.
}
```

Grep the source first: `rg 'impl CellLifecycle for PushReactiveData' cells/push_reactive.mbt -A 30` and `rg 'impl CellLifecycle for PushEffectData' cells/push_effect.mbt -A 30` to know exactly which lifecycle methods have bodies worth copying.

- [x] **Step 3.5: Trim `cells/push_reactive.mbt` to the handle half**

Delete lines 1-114 (the SoA half that moved in Step 3.2) and the `impl CellLifecycle for PushReactiveData` blocks (which moved in Step 3.4). Add at the top:

```moonbit
///|
using @push { type PushReactiveData }
```

Everything remaining — `Reactive[T]` struct, `Reactive::new`, `get`, and any other handle-side methods — stays untouched.

- [x] **Step 3.6: Trim `cells/push_effect.mbt` to the handle half**

Same pattern: remove lines 1-89 plus lifecycle impls, add `using @push { type PushEffectData }` at the top. Remaining `Effect` handle + constructor stays.

- [x] **Step 3.7: Update `cells/push_propagate.mbt`**

Add `using @push { type PushReactiveData }` if the file references the struct by name. `PushEntry` stays here untouched.

- [x] **Step 3.8: Update other consumer imports**

Apply the pattern from Step 2.6: for each of `cells/runtime.mbt`, `cells/introspection.mbt`, `cells/scope.mbt`, and any wbtest, add `using @push { type PushReactiveData, type PushEffectData }` as needed.

Quick find: `rg -l 'PushReactiveData|PushEffectData' cells/*.mbt`.

- [x] **Step 3.9: Update `cells/moon.pkg`**

Append `"dowdiness/incr/cells/internal/push" @push,` to the first import block.

- [x] **Step 3.10: Run `moon check`, `moon test`, `moon info && moon fmt`, diff `.mbti`**

Same verification contract as previous tasks.

- [x] **Step 3.11: Commit**

```bash
git add cells/internal/push/ cells/push_lifecycle.mbt cells/push_reactive.mbt cells/push_effect.mbt cells/push_propagate.mbt cells/runtime.mbt cells/introspection.mbt cells/scope.mbt cells/moon.pkg cells/*_wbtest.mbt pkg.generated.mbti tests/pkg.generated.mbti
git commit -m "refactor: move push engine SoA to cells/internal/push

PushReactiveData and PushEffectData move to cells/internal/push with
pub(all) visibility and pub impl for CellOps/HasCellMeta. Handle
types (Reactive[T], Effect) and their constructors remain in cells/
as the user-facing API. PushEntry stays with push_propagate.mbt;
CellLifecycle impls move to cells/push_lifecycle.mbt.
"
```

---

## Task 4: Move datalog-engine SoA to `cells/internal/datalog/`, keep handles in `cells/`

**Files:**
- Create: `cells/internal/datalog/moon.pkg`
- Create: `cells/internal/datalog/relation_data.mbt`
- Create: `cells/internal/datalog/functional_relation_data.mbt`
- Create: `cells/internal/datalog/rule_data.mbt`
- Create: `cells/datalog_lifecycle.mbt`
- Modify (file split): `cells/datalog_relation.mbt`, `cells/datalog_functional_relation.mbt`, `cells/datalog_rule.mbt`
- Modify: `cells/datalog_fixpoint.mbt`, `cells/runtime.mbt`, `cells/introspection.mbt`, `cells/moon.pkg`, `cells/*_wbtest.mbt`

- [x] **Step 4.1: Create `cells/internal/datalog/moon.pkg`**

```text
import {
  "dowdiness/incr/types" @incr_types,
  "dowdiness/incr/cells/internal/shared" @shared,
  "moonbitlang/core/hashset",
}
```

- [x] **Step 4.2: Create `cells/internal/datalog/relation_data.mbt`**

Open `cells/datalog_relation.mbt`. Source lines ~1-24 are the `RelationData` struct + `CellOps` / `HasCellMeta` impls. Lines ~26-187 are the `Relation[T]` handle plus methods.

Write `cells/internal/datalog/relation_data.mbt` containing:
- `using @incr_types { ... }`, `using @shared { ... }` at the top.
- `pub(all) struct RelationData { ... }` (preserve fields; change `priv` → `pub(all)`).
- `pub impl HasCellMeta for RelationData with meta(self) { self.meta }`.
- `pub impl CellOps for RelationData` (empty).
- Any other `pub impl CellOps for RelationData with ...` — copy from source, add `pub`.

Do not include the `impl CellLifecycle for RelationData` block — that moves to Step 4.5.

- [x] **Step 4.3: Create `cells/internal/datalog/functional_relation_data.mbt`**

Same pattern for `FunctionalRelationData` (source: `cells/datalog_functional_relation.mbt` lines ~1-28).

- [x] **Step 4.4: Create `cells/internal/datalog/rule_data.mbt`**

Same pattern for `RuleData` (source: `cells/datalog_rule.mbt` lines ~1-28).

Per the spec: there is no `Rule` handle struct in this codebase — only `RuleData` + `Runtime::new_rule`. Do not invent a handle. Move only the struct + its `CellOps`/`HasCellMeta` impls.

- [x] **Step 4.5: Create `cells/datalog_lifecycle.mbt`**

```moonbit
///|
using @datalog { type RelationData, type FunctionalRelationData, type RuleData }
using @incr_types { type CellId }

///|
impl CellLifecycle for RelationData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  // Paste body from cells/datalog_relation.mbt.
}

///|
impl CellLifecycle for FunctionalRelationData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  // Paste body from cells/datalog_functional_relation.mbt.
}

///|
impl CellLifecycle for RuleData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  // Paste body from cells/datalog_rule.mbt.
}
```

Grep sources to confirm whether any of the three have non-default `on_observe` or `on_unobserve`: `rg 'impl CellLifecycle for (RelationData|FunctionalRelationData|RuleData) with (on_observe|on_unobserve)' cells/`. If any match, copy those impls too.

- [x] **Step 4.6: Trim `cells/datalog_relation.mbt` to the handle half**

Remove lines ~1-24 and the `impl CellLifecycle for RelationData` block. Add at the top:

```moonbit
///|
using @datalog { type RelationData }
```

Remaining `Relation[T]` handle + `Relation::new` + user-facing methods stay.

- [x] **Step 4.7: Trim `cells/datalog_functional_relation.mbt`**

Same pattern: remove lines ~1-28 plus the lifecycle impl, add `using @datalog { type FunctionalRelationData }`.

- [x] **Step 4.8: Trim `cells/datalog_rule.mbt` to `Runtime::new_rule` + helpers**

Remove lines ~1-28 (struct + `CellOps`/`HasCellMeta` impls) and the `impl CellLifecycle for RuleData` block. Keep `pub fn Runtime::new_rule(...)` (currently at ~lines 31-65) and `fn Runtime::assert_rule_relation_id(...)` (~lines 67-98). Add `using @datalog { type RuleData }` at the top.

- [x] **Step 4.9: Update `cells/datalog_fixpoint.mbt`**

Add `using @datalog { type RelationData, type FunctionalRelationData, type RuleData }` as needed. Grep shows it currently reads all three SoA types.

- [x] **Step 4.10: Update other consumer imports**

Apply the pattern from Step 2.6 for `cells/runtime.mbt`, `cells/introspection.mbt`, and any wbtest. Grep: `rg -l 'RelationData|FunctionalRelationData|RuleData' cells/*.mbt`.

- [x] **Step 4.11: Update `cells/moon.pkg`**

Append `"dowdiness/incr/cells/internal/datalog" @datalog,` to the first import block.

- [x] **Step 4.12: Run `moon check`, `moon test`, `moon info && moon fmt`, diff `.mbti`**

Same verification contract.

- [x] **Step 4.13: Commit**

```bash
git add cells/internal/datalog/ cells/datalog_lifecycle.mbt cells/datalog_relation.mbt cells/datalog_functional_relation.mbt cells/datalog_rule.mbt cells/datalog_fixpoint.mbt cells/runtime.mbt cells/introspection.mbt cells/moon.pkg cells/*_wbtest.mbt pkg.generated.mbti tests/pkg.generated.mbti
git commit -m "refactor: move datalog engine SoA to cells/internal/datalog

RelationData, FunctionalRelationData, RuleData move to
cells/internal/datalog with pub(all) visibility and pub impl for
CellOps/HasCellMeta. Handle types (Relation[T], FunctionalRelation
[T, U]) and the public Runtime::new_rule function remain in cells/.
CellLifecycle impls in cells/datalog_lifecycle.mbt. Fixpoint
algorithm unchanged.
"
```

---

## Task 5: Add engine-isolation boundary check

**Files:**
- Create: `scripts/check-engine-isolation.sh` (executable)

- [x] **Step 5.1: Create `scripts/check-engine-isolation.sh`**

Write the file with exactly this content:

```bash
#!/usr/bin/env bash
# scripts/check-engine-isolation.sh
# Asserts internal-package isolation rules for the incr library.
set -euo pipefail

fail=0
engines=(pull push datalog)

# Extract imports as exact quoted strings from a moon.pkg file.
# Returns each imported package path, one per line, without quotes.
# Handles both `#` and `//` line comments (this repo uses `//`), and
# excludes the `"test"` discriminator from `} for "test"` import blocks.
# The `{ ... } || true` grouping treats "no matches" from any grep stage
# as an empty import list — without it, `set -o pipefail` would propagate
# grep's exit 1 out through the `imports=$(...)` callers and silently
# abort the script for packages with no quoted imports.
extract_imports() {
  local file="$1"
  {
    sed 's|//.*$||; s|#.*$||' "$file" \
      | grep -oE '"[^"]+"' \
      | tr -d '"' \
      | grep -vFx 'test'
  } || true
}

# Invariant 1: no cross-engine sibling imports.
for engine in "${engines[@]}"; do
  pkg="cells/internal/$engine/moon.pkg"
  if [ ! -f "$pkg" ]; then
    echo "MISSING: $pkg"
    fail=1
    continue
  fi
  imports=$(extract_imports "$pkg")
  for other in "${engines[@]}"; do
    [ "$engine" = "$other" ] && continue
    if echo "$imports" | grep -Fxq "dowdiness/incr/cells/internal/$other"; then
      echo "FAIL: cells/internal/$engine imports cells/internal/$other"
      fail=1
    fi
  done
done

# Invariant 2: internal/shared is a leaf — no engine imports.
# (The back-edge check for shared is covered by invariant 3 below.)
shared_pkg="cells/internal/shared/moon.pkg"
if [ -f "$shared_pkg" ]; then
  imports=$(extract_imports "$shared_pkg")
  for other in "${engines[@]}"; do
    if echo "$imports" | grep -Fxq "dowdiness/incr/cells/internal/$other"; then
      echo "FAIL: cells/internal/shared imports cells/internal/$other"
      fail=1
    fi
  done
else
  echo "MISSING: $shared_pkg"
  fail=1
fi

# Invariant 3: no back-edges from any internal/* to cells/.
# Allow `dowdiness/incr/cells/internal` and its sub-paths; flag every
# other `dowdiness/incr/cells`-prefixed import as a back-edge. The
# two-stage grep (include `cells($|/)`, exclude `cells/internal($|/)`)
# is more robust than a single regex against future rename drift.
for engine in shared "${engines[@]}"; do
  pkg="cells/internal/$engine/moon.pkg"
  [ -f "$pkg" ] || continue
  imports=$(extract_imports "$pkg")
  if echo "$imports" \
    | grep -E '^dowdiness/incr/cells($|/)' \
    | grep -vE '^dowdiness/incr/cells/internal($|/)' \
    | grep -q .; then
    echo "FAIL: cells/internal/$engine imports cells/ (back-edge)"
    fail=1
  fi
done

exit "$fail"
```

The canonical version lives at `scripts/check-engine-isolation.sh`; if plan and script diverge, the script wins.

- [x] **Step 5.2: Make the script executable**

```bash
chmod +x scripts/check-engine-isolation.sh
```

- [x] **Step 5.3: Run the script against the current tree**

```bash
bash scripts/check-engine-isolation.sh
echo "exit: $?"
```

Expected: exit 0, no output.

- [x] **Step 5.4: Smoke-test the failure mode**

Temporarily break one invariant, confirm the script catches it, then revert.

```bash
# Inject a cross-engine import
sed -i.bak 's|import {|import {\n  "dowdiness/incr/cells/internal/push" @push,|' cells/internal/pull/moon.pkg
bash scripts/check-engine-isolation.sh
echo "exit: $?"
# Expected: exit 1, output "FAIL: cells/internal/pull imports cells/internal/push"

# Revert
mv cells/internal/pull/moon.pkg.bak cells/internal/pull/moon.pkg
bash scripts/check-engine-isolation.sh
echo "exit: $?"
# Expected: exit 0
```

If the script misses the violation, the regex or the quoted-path matcher needs adjustment. Debug by running `bash -x scripts/check-engine-isolation.sh` to see line-by-line execution.

- [x] **Step 5.5: Add the script to the standard per-commit verification**

This step is a doc update. Open `CLAUDE.md` and find the "Quality & Edit Workflow" or similar section. Add a bullet: "Before committing changes that touch `cells/internal/*/moon.pkg`, run `bash scripts/check-engine-isolation.sh`." If there's no appropriate section, skip — Task 6 will add it.

- [x] **Step 5.6: Run full verification**

```bash
moon check
moon test
moon info && moon fmt
git diff --exit-code pkg.generated.mbti tests/pkg.generated.mbti
bash scripts/check-engine-isolation.sh
```

All must pass / exit 0.

- [x] **Step 5.7: Commit**

```bash
git add scripts/check-engine-isolation.sh
git commit -m "test: add engine-isolation boundary checks

Shell script asserts (a) no cross-engine sibling imports,
(b) internal/shared is a leaf (no engine imports, no back-edge),
(c) no back-edges from cells/internal/* to cells/. Uses exact
quoted-path matching and filters // and # comments and the
\"test\" discriminator from \`for \"test\"\` import blocks.
"
```

---

## Task 6: Update project documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/todo.md`
- Modify: `docs/design.md`
- Modify: `docs/README.md`

- [x] **Step 6.1: Update `CLAUDE.md` package map**

Open `CLAUDE.md`. Find the "Architecture" section (it contains the tree-diagram of `cells/`).

Replace the current `cells/` layout block with the post-refactor layout:

```text
dowdiness/incr/
├── moon.pkg                    (root facade — imports types + cells + pipeline)
├── incr.mbt                    (pub type re-exports for all public types)
├── traits.mbt
│
├── types/                      (pure value types, zero dependencies)
│
├── cells/                      (coordinator + handles + algorithms + lifecycle)
│   ├── moon.pkg                (imports @shared, @pull, @push, @datalog)
│   ├── runtime.mbt             (Runtime + sub-states)
│   ├── cycle.mbt               (CycleError — stays here; format_path uses Runtime)
│   ├── pull_memo.mbt           (MemoData — stays here; compute references CycleError)
│   ├── pull_lifecycle.mbt      (CellLifecycle for PullSignalData)
│   ├── push_lifecycle.mbt      (CellLifecycle for PushReactiveData, PushEffectData)
│   ├── datalog_lifecycle.mbt   (CellLifecycle for Relation/Functional/Rule)
│   ├── push_reactive.mbt       (Reactive[T] handle; SoA moved to internal/push)
│   ├── push_effect.mbt         (Effect handle; SoA moved to internal/push)
│   ├── push_propagate.mbt      (push algorithm + PushEntry)
│   ├── datalog_relation.mbt    (Relation[T] handle; SoA moved to internal/datalog)
│   ├── datalog_functional_relation.mbt
│   ├── datalog_rule.mbt        (Runtime::new_rule + helpers; RuleData moved)
│   ├── datalog_fixpoint.mbt    (fixpoint algorithm)
│   ├── verify.mbt              (pull verification algorithm + PullVerifyFrame)
│   ├── batch.mbt               (batch algorithm)
│   ├── signal.mbt, memo.mbt    (Signal[T], Memo[T] handles)
│   ├── hybrid_memo.mbt         (HybridMemo[T] handle)
│   ├── tracked_cell.mbt        (TrackedCell[T] handle)
│   ├── memo_map.mbt            (MemoMap[K, V])
│   ├── scope.mbt, tracking.mbt, introspection.mbt
│   ├── cell.mbt, cell_ops.mbt  (local CellLifecycle trait + using re-exports)
│   ├── internal/               (engine sub-packages, MoonBit `internal` visibility)
│   │   ├── shared/             (CellOps, HasCellMeta, Committable, CellMeta, CellRef)
│   │   ├── pull/               (PullSignalData only — memo stays in cells/)
│   │   ├── push/               (PushReactiveData, PushEffectData)
│   │   └── datalog/            (RelationData, FunctionalRelationData, RuleData)
│   └── *_test.mbt, *_wbtest.mbt
│
├── pipeline/                   (unchanged; still deferred per todo)
└── tests/                      (unchanged; integration tests)
```

Replace any bullet list of `cells/` files with this hierarchy. Do not delete the "Key Facts" subsection.

Add a new "Key Facts" bullet:
- `cells/internal/{shared,pull,push,datalog}/` use MoonBit's `internal` package feature. External consumers cannot import them. Engine packages (`pull`, `push`, `datalog`) must not import each other — enforced by `scripts/check-engine-isolation.sh`.

- [x] **Step 6.2: Update `docs/todo.md`**

Find the "Runtime Modularization (Phase 4 — Remaining)" section. The two remaining items are:

```text
- [ ] Internal package split — Move engine types to `cells/internal/pull/`, `cells/internal/push/`, `cells/internal/datalog/`
- [ ] Verify engine packages do not import each other
```

Replace with:

```text
- [x] Internal package split — Engine types split across `cells/internal/{shared,pull,push,datalog}/` (PR TBD). Pull-engine split is partial: only `PullSignalData` moved; `MemoData` stays in `cells/` because its compute closure references `CycleError` (see [spec](superpowers/specs/2026-04-18-incr-stage5-internal-split-design.md) for rationale).
- [x] Verify engine packages do not import each other — `scripts/check-engine-isolation.sh` enforces pairwise engine isolation and the no-back-edge invariant.
- [ ] Complete pull-engine split: move `MemoData` to `cells/internal/pull/` once `CycleError` is untangled (requires redesigning `CycleError::format_path` or moving `CycleError` data into `types/` with a non-`Runtime` render pathway).
```

- [x] **Step 6.3: Update `docs/design.md`**

Find the Architecture section that references the current `cells/` layout. Per the project's documentation rules ("Architecture docs = principles only, never reference specific types/fields/lines"), keep changes to principles.

Add near the architecture description:

> **Engine isolation (2026-04-18).** Engine SoA types are partitioned into `cells/internal/{shared,pull,push,datalog}/` using MoonBit's `internal` package visibility. Engines cannot import each other (enforced by `scripts/check-engine-isolation.sh`), and no engine package imports back into `cells/`. The pull split is partial: `PullSignalData` moved; `MemoData` stays in `cells/` because its compute closure references `CycleError`. See [Stage 5 design spec](superpowers/specs/2026-04-18-incr-stage5-internal-split-design.md) for details.

- [x] **Step 6.4: Update `docs/README.md`**

Find the list of design specs (typically under "Specs" or "Plans" heading). Add a link to the Stage 5 spec:

```text
- [2026-04-18 — Runtime Modularization Stage 5: internal package split](superpowers/specs/2026-04-18-incr-stage5-internal-split-design.md)
```

- [x] **Step 6.5: Run `bash check-docs.sh`** (if it exists)

```bash
bash check-docs.sh
```

Expected: no warnings.

If the script is not present at that path (the monorepo's loom-level `check-docs.sh` may not apply to incr), skip this step.

- [x] **Step 6.6: Final full verification**

```bash
moon check
moon test
moon info && moon fmt
git diff --exit-code pkg.generated.mbti tests/pkg.generated.mbti
bash scripts/check-engine-isolation.sh
```

All must pass / exit 0.

- [x] **Step 6.7: Commit**

```bash
git add CLAUDE.md docs/todo.md docs/design.md docs/README.md
git commit -m "docs: update CLAUDE.md + todo + design.md for internal split

Refresh the package map to reflect cells/internal/{shared,pull,
push,datalog}/ layout. Note that pull-engine split is partial
(signals only; memos stay in cells/ because MemoData.compute
references CycleError). Track the memo move as a follow-up
requiring CycleError redesign.
"
```

---

## Final checks (after Task 6)

- [x] **All commits present, branch pushable.**

```bash
git log refactor/incr-structure --oneline | head -20
```

Expected: 6 new commits on top of `1048ad3` (spec) + the amendments; plus original branch tip.

- [x] **Worktree is clean.**

```bash
git status
```

Expected: "nothing to commit, working tree clean."

- [x] **Benchmarks (optional but recommended).**

```bash
moon bench --release
```

Compare hot-path numbers (verify dep-walk, push propagation) against pre-refactor measurements. Investigate any >5% regression; no action needed if numbers are within noise.

- [x] **Push and open PR.**

Only after user confirmation. See `superpowers:finishing-a-development-branch` for the branch-completion workflow.

---

## Rollback plan

If any task's verification fails in an unrecoverable way, roll back to the previous green commit with:

```bash
git reset --hard HEAD~1    # discard the failed commit
# or
git reset --hard <previous-green-sha>
```

Do not try to "fix forward" through a red state. Each commit is designed to be independently green; landing a red commit defeats the staged-green guarantee and makes bisection unusable.

---

## Notes for the implementing engineer

- **Do not change algorithms.** `verify.mbt`, `push_propagate.mbt`, `batch.mbt`, `datalog_fixpoint.mbt` are untouched by this refactor. If you find yourself editing them beyond adding `using @pull` / `using @push` / `using @datalog`, you are going outside scope.
- **Do not rename `cells/pull_memo.mbt` or `cells/cycle.mbt`.** They stay where they are with their contents unchanged.
- **Do not invent handle types.** There is no `Rule` struct. If you start drafting `pub struct Rule { ... }` in `cells/datalog_rule.mbt`, stop — that's the trap Codex round 3 flagged.
- **Every `impl Trait for Type` inside `cells/internal/*/` must be `pub impl`.** Without `pub`, cross-package trait-object dispatch (`&CellOps`, `&Committable`) silently fails to resolve.
- **Every moved struct must be `pub(all)`.** `pub` is readonly across packages and will break the mutating call sites in `cells/runtime.mbt`, `cells/batch_wbtest.mbt`, and others.
- **If `moon check` fails with "cannot import internal package"** from a non-`cells/` caller, it is by design — external packages must go through the root `@incr` facade. If `cells/` itself hits that error, something is wrong with the parent-child relationship; re-check that `cells/internal/<child>/moon.pkg` exists and the package name matches the path.
- **If `moon test` reveals a regression in a dispose/GC test**, suspect the `CellLifecycle` impl placement in `cells/{pull,push,datalog}_lifecycle.mbt`. The impl lives with the *trait* (in `cells/`), not the *type* (in `internal/*/`). Misplacing the impl — especially trying to put it into an internal package — recreates the back-edge cycle.
