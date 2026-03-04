# Modularization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split the flat single-package library into four MoonBit sub-packages (`types`, `internal`, `pipeline`, root facade) using `pub typealias` re-exports to maintain a zero-breaking-change public API.

**Architecture:** `types/` holds pure value types (Revision, Durability, CellId) with zero deps. `internal/` holds all engine code importing from `types/`. The root package imports both and re-exports everything via `pub typealias` in `incr.mbt`. `pipeline/` is a standalone experimental package. Black-box tests (`*_test.mbt`) stay in root and need no changes. White-box tests (`*_wbtest.mbt`) move to `internal/` so they retain access to private fields.

**Tech Stack:** MoonBit, `moon check` (type-check), `moon test` (run tests), `moon build` (build)

**Design doc:** `docs/plans/2026-02-22-modularization-design.md`

---

## Task 1: Verify baseline

**Files:** none

**Step 1: Confirm all tests pass before touching anything**

```bash
moon test
```

Expected: 128 tests pass, 0 failures.

**Step 2: Confirm type-check passes**

```bash
moon check
```

Expected: no errors.

---

## Task 2: Create `types/` package

**Files:**
- Create: `types/moon.pkg`
- Create: `types/revision.mbt`
- Create: `types/cell_id.mbt`

**Step 1: Create the package directory and config**

```bash
mkdir types
```

Create `types/moon.pkg`:
```
import {}
```

**Step 2: Create `types/revision.mbt`**

Copy `revision.mbt` verbatim to `types/revision.mbt`. No changes needed — the file is already self-contained.

**Step 3: Create `types/cell_id.mbt`**

Create `types/cell_id.mbt` with just the `CellId` type and its `Hash` implementation, extracted from `cell.mbt` (lines 1–24 of the current `cell.mbt`):

```moonbit
///|
/// A unique identifier for a cell (signal or memo) in the runtime.
///
/// Cell IDs are monotonically increasing integers allocated by the runtime.
/// They serve as direct array indices for O(1) cell lookup.
///
/// Each CellId is scoped to its originating runtime via `runtime_id`.
/// This prevents cells from different runtimes being incorrectly queried
/// against each other.
pub(all) struct CellId {
  runtime_id : Int
  id : Int
} derive(Eq, Show, Debug)

///|
impl Hash for CellId with hash(self) {
  self.runtime_id.hash() * 31 + self.id.hash()
}

///|
impl Hash for CellId with hash_combine(self, hasher) {
  self.runtime_id.hash_combine(hasher)
  self.id.hash_combine(hasher)
}
```

**Step 4: Type-check the new package in isolation**

```bash
moon check
```

Expected: no errors. (The root package still defines CellId and Revision — that is fine for now, they are in separate packages and don't conflict yet.)

**Step 5: Commit**

```bash
git add types/
git commit -m "feat: create types sub-package with Revision, Durability, CellId"
```

---

## Task 3: Create `internal/moon.pkg` and `internal/cell.mbt`

**Files:**
- Create: `internal/moon.pkg`
- Create: `internal/cell.mbt`

**Step 1: Create the internal directory and config**

```bash
mkdir internal
```

Create `internal/moon.pkg`:
```
import {
  "dowdiness/incr/types" as @incr_types,
  "moonbitlang/core/hashset",
}
```

**Step 2: Create `internal/cell.mbt`**

Copy `cell.mbt` to `internal/cell.mbt`, then make these changes:

- **Remove** the `CellId` struct definition and both `Hash` impl blocks (they now live in `types/cell_id.mbt`)
- **Replace** every bare type name from the `types` package with its qualified form:

| Find | Replace with |
|------|-------------|
| `CellId` | `@incr_types.CellId` |
| `Revision` | `@incr_types.Revision` |
| `Durability` | `@incr_types.Durability` |
| `Low` (as Durability constructor) | `@incr_types.Low` |
| `Revision::initial()` | `@incr_types.Revision::initial()` |

`CycleError` remains unqualified — it will be defined in `internal/cycle.mbt` (same package).

The resulting `CellMeta` struct signature should look like:
```moonbit
priv struct CellMeta {
  id : @incr_types.CellId
  kind : CellKind
  mut changed_at : @incr_types.Revision
  mut verified_at : @incr_types.Revision
  mut dependencies : Array[@incr_types.CellId]
  mut durability : @incr_types.Durability
  mut recompute_and_check : (() -> Result[Bool, CycleError])?
  mut commit_pending : (() -> Bool)?
  mut on_change : (() -> Unit)?
  mut in_progress : Bool
  mut label : String?
}
```

**Step 3: Type-check**

```bash
moon check
```

Expected: no errors. (internal/cell.mbt will fail if CycleError is not yet defined — if so, add a temporary stub `pub suberror CycleError { CycleDetected(@incr_types.CellId, Array[@incr_types.CellId]) }` at the top of `internal/cell.mbt` to unblock, then remove it in Task 4.)

---

## Task 4: Create `internal/cycle.mbt`

**Files:**
- Create: `internal/cycle.mbt`

**Step 1: Create `internal/cycle.mbt`**

Copy `cycle.mbt` to `internal/cycle.mbt`. Replace bare type names:

| Find | Replace with |
|------|-------------|
| `CellId` | `@incr_types.CellId` |

`Runtime` remains unqualified — it will be defined in `internal/runtime.mbt` (same package).

If you added a temporary stub in Task 3, remove it now.

**Step 2: Type-check**

```bash
moon check
```

Expected: no errors (Runtime not yet defined but cycle.mbt only references it in a function parameter — MoonBit resolves within-package references lazily at link time).

**Step 3: Commit**

```bash
git add internal/
git commit -m "feat: create internal sub-package with cell and cycle modules"
```

---

## Task 5: Create `internal/tracking.mbt`

**Files:**
- Create: `internal/tracking.mbt`

**Step 1: Create `internal/tracking.mbt`**

Copy `tracking.mbt` to `internal/tracking.mbt`. Replace bare type names:

| Find | Replace with |
|------|-------------|
| `CellId` | `@incr_types.CellId` |

`@hashset` is already imported in `internal/moon.pkg` so `@hashset.HashSet` and `@hashset.new()` remain unchanged.

**Step 2: Type-check**

```bash
moon check
```

Expected: no errors.

---

## Task 6: Create `internal/runtime.mbt`

**Files:**
- Create: `internal/runtime.mbt`

**Step 1: Create `internal/runtime.mbt`**

Copy `runtime.mbt` to `internal/runtime.mbt`. Replace bare type names:

| Find | Replace with |
|------|-------------|
| `Revision` | `@incr_types.Revision` |
| `Durability` | `@incr_types.Durability` |
| `CellId` | `@incr_types.CellId` |
| `DURABILITY_COUNT` | `@incr_types.DURABILITY_COUNT` |
| `Low` (as Durability constructor) | `@incr_types.Low` |
| `Revision::initial()` | `@incr_types.Revision::initial()` |
| `Revision::next(` | `@incr_types.Revision::next(` |

The `Runtime` struct's `durability_last_changed` field initialization becomes:
```moonbit
durability_last_changed: FixedArray::make(
  @incr_types.DURABILITY_COUNT,
  @incr_types.Revision::initial(),
),
batch_max_durability: @incr_types.Low,
```

**Step 2: Type-check**

```bash
moon check
```

Expected: no errors.

**Step 3: Commit**

```bash
git add internal/tracking.mbt internal/runtime.mbt
git commit -m "feat: add tracking and runtime modules to internal package"
```

---

## Task 7: Create `internal/verify.mbt`

**Files:**
- Create: `internal/verify.mbt`

**Step 1: Create `internal/verify.mbt`**

Copy `verify.mbt` to `internal/verify.mbt`. Replace bare type names:

| Find | Replace with |
|------|-------------|
| `Revision` | `@incr_types.Revision` |
| `CellId` | `@incr_types.CellId` |

`CellMeta`, `Runtime`, `CycleError`, `CellKind` are all in the same `internal` package — leave them unqualified.

**Step 2: Type-check**

```bash
moon check
```

Expected: no errors.

---

## Task 8: Create `internal/signal.mbt`

**Files:**
- Create: `internal/signal.mbt`

**Step 1: Create `internal/signal.mbt`**

Copy `signal.mbt` to `internal/signal.mbt`. Replace bare type names:

| Find | Replace with |
|------|-------------|
| `Durability` | `@incr_types.Durability` |
| `CellId` | `@incr_types.CellId` |
| `Low` (default durability value) | `@incr_types.Low` |

The `Signal::new` signature becomes:
```moonbit
pub fn[T] Signal::new(
  rt : Runtime,
  initial : T,
  durability? : @incr_types.Durability = @incr_types.Low,
  label? : String,
) -> Signal[T] {
```

**Step 2: Type-check**

```bash
moon check
```

Expected: no errors.

**Step 3: Commit**

```bash
git add internal/verify.mbt internal/signal.mbt
git commit -m "feat: add verify and signal modules to internal package"
```

---

## Task 9: Create `internal/memo.mbt`

**Files:**
- Create: `internal/memo.mbt`

**Step 1: Create `internal/memo.mbt`**

Copy `memo.mbt` to `internal/memo.mbt`. Replace bare type names:

| Find | Replace with |
|------|-------------|
| `Durability` | `@incr_types.Durability` |
| `CellId` | `@incr_types.CellId` |
| `Revision` | `@incr_types.Revision` |
| `Low` (in `compute_durability`) | `@incr_types.Low` |
| `High` (in `compute_durability`) | `@incr_types.High` |

**Step 2: Add `Memo::is_up_to_date` method**

This method currently lives in `traits.mbt` but accesses private fields. Add it to `internal/memo.mbt`:

```moonbit
///|
/// Returns true if the memo has a cached value and its verified_at matches
/// the runtime's current revision. Returns false if the memo has never been
/// computed (value is None), even at the initial revision.
pub fn[T] Memo::is_up_to_date(self : Memo[T]) -> Bool {
  match self.value {
    None => false
    Some(_) => {
      let cell = self.rt.get_cell(self.cell_id)
      cell.verified_at == self.rt.current_revision
    }
  }
}
```

**Step 3: Type-check**

```bash
moon check
```

Expected: no errors.

**Step 4: Commit**

```bash
git add internal/memo.mbt
git commit -m "feat: add memo module to internal package"
```

---

## Task 10: Move whitebox tests to `internal/`

**Files:**
- Move: `cell_wbtest.mbt` → `internal/cell_wbtest.mbt`
- Move: `verify_wbtest.mbt` → `internal/verify_wbtest.mbt`
- Move: `durability_wbtest.mbt` → `internal/durability_wbtest.mbt`
- Move: `batch_wbtest.mbt` → `internal/batch_wbtest.mbt`
- Move: `signal_wbtest.mbt` → `internal/signal_wbtest.mbt`
- Move: `memo_dep_diff_wbtest.mbt` → `internal/memo_dep_diff_wbtest.mbt`

**Step 1: Copy whitebox tests to `internal/`**

```bash
cp cell_wbtest.mbt internal/cell_wbtest.mbt
cp verify_wbtest.mbt internal/verify_wbtest.mbt
cp durability_wbtest.mbt internal/durability_wbtest.mbt
cp batch_wbtest.mbt internal/batch_wbtest.mbt
cp signal_wbtest.mbt internal/signal_wbtest.mbt
cp memo_dep_diff_wbtest.mbt internal/memo_dep_diff_wbtest.mbt
```

**Step 2: Update `@incr_types` qualifications in whitebox tests**

Within `internal/`, any reference to `Revision`, `Durability`, `CellId`, `DURABILITY_COUNT`, or their constructors (`Low`, `Medium`, `High`, `Revision::initial()` etc.) must be qualified with `@incr_types.`.

Go through each file and apply the same substitution table used in Tasks 3–9:

| Find | Replace with |
|------|-------------|
| `CellId` | `@incr_types.CellId` |
| `Revision` | `@incr_types.Revision` |
| `Durability` | `@incr_types.Durability` |
| `Low` (as constructor) | `@incr_types.Low` |
| `Medium` (as constructor) | `@incr_types.Medium` |
| `High` (as constructor) | `@incr_types.High` |

Be careful with `CellId::{ runtime_id: 1, id: 2 }` style struct literals — they become `@incr_types.CellId::{ runtime_id: 1, id: 2 }`.

**Step 3: Type-check and run internal whitebox tests**

```bash
moon check
moon test -p dowdiness/incr/internal
```

Expected: all whitebox tests pass (same count as before they were moved).

**Step 4: Commit**

```bash
git add internal/
git commit -m "feat: move whitebox tests to internal package"
```

---

## Task 11: Wire up the root package facade

This is the switchover task. Do all steps before running `moon check`.

**Files:**
- Modify: `moon.pkg`
- Create: `incr.mbt`
- Modify: `traits.mbt`
- Delete: `revision.mbt`, `cell.mbt`, `cycle.mbt`, `tracking.mbt`, `runtime.mbt`, `verify.mbt`, `signal.mbt`, `memo.mbt`, `pipeline_traits.mbt`

**Step 1: Update root `moon.pkg`**

Replace the current contents of `moon.pkg` with:

```
import {
  "dowdiness/incr/types" as @incr_types,
  "dowdiness/incr/internal" as @internal,
  "moonbitlang/core/hashset",
}
```

**Step 2: Create `incr.mbt`**

```moonbit
///|
pub typealias Revision = @incr_types.Revision

///|
pub typealias Durability = @incr_types.Durability

///|
pub typealias CellId = @incr_types.CellId

///|
pub typealias Runtime = @internal.Runtime

///|
pub typealias CellInfo = @internal.CellInfo

///|
pub typealias Signal[T] = @internal.Signal[T]

///|
pub typealias Memo[T] = @internal.Memo[T]

///|
pub typealias CycleError = @internal.CycleError
```

**Step 3: Update `traits.mbt`**

Remove the `pub fn[T] Memo::is_up_to_date` method body (it moved to `internal/memo.mbt` in Task 9). The `impl Readable for Memo[T]` block that calls `self.is_up_to_date()` stays — it now dispatches to `@internal.Memo::is_up_to_date`.

The rest of `traits.mbt` — `Database`, `Readable`, `Signal::is_up_to_date`, `impl Readable for Signal`, `impl Readable for Memo`, `create_signal`, `create_memo`, `batch` — stays unchanged. Within the root package, `Signal`, `Memo`, `Runtime`, `Durability` etc. resolve through the typealiases defined in `incr.mbt`.

**Step 4: Delete root engine source files**

```bash
rm revision.mbt cell.mbt cycle.mbt tracking.mbt runtime.mbt verify.mbt signal.mbt memo.mbt pipeline_traits.mbt
```

**Step 5: Type-check**

```bash
moon check
```

Expected: no errors. If you see "undefined type X", check that `incr.mbt` has a `pub typealias` for X and that the alias points to the correct package.

**Step 6: Run the full test suite**

```bash
moon test
```

Expected: same number of tests pass as in Task 1 (128). No new failures.

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: wire up root package facade with pub typealias re-exports"
```

---

## Task 12: Create `pipeline/` package

**Files:**
- Create: `pipeline/moon.pkg`
- Create: `pipeline/pipeline_traits.mbt`

**Step 1: Create the pipeline package**

```bash
mkdir pipeline
```

Create `pipeline/moon.pkg`:
```
import {}
```

Create `pipeline/pipeline_traits.mbt` as a verbatim copy of the deleted `pipeline_traits.mbt`.

**Step 2: Type-check**

```bash
moon check
```

Expected: no errors.

**Step 3: Run all tests**

```bash
moon test
```

Expected: all tests pass. Note: pipeline trait tests live in root's `traits_test.mbt` and import via the root package — they continue to work without changes.

**Step 4: Commit**

```bash
git add pipeline/
git commit -m "feat: create pipeline sub-package for experimental traits"
```

---

## Task 13: Final verification

**Step 1: Full test suite**

```bash
moon test
```

Expected: same pass count as Task 1.

**Step 2: Build check**

```bash
moon build
```

Expected: clean build with no warnings.

**Step 3: Verify package structure**

```bash
find . -name "moon.pkg" -not -path "./_build/*" -not -path "./.claude/*"
```

Expected output:
```
./moon.pkg
./types/moon.pkg
./internal/moon.pkg
./pipeline/moon.pkg
```

**Step 4: Final commit if anything was missed**

If any cleanup was needed, commit it:
```bash
git add -A
git commit -m "chore: finalize modularization into types/internal/pipeline packages"
```
