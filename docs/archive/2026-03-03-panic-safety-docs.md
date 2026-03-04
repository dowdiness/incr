# Panic-Safety Docs Pass Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close out the 2026-02-25 panic-safety hardening plan by updating tracking docs, fixing stale package paths in the old plan file, and surfacing `get_or`/`get_or_else` in the README.

**Architecture:** Documentation-only changes across four files. No source code touched. Each task is an independent edit followed by a regression check (`moon test`) and a commit. Tasks can be done in any order.

**Tech Stack:** MoonBit. Validate with `moon test` after each task to confirm no regressions.

---

### Task 1: Add Phase 2D to `docs/roadmap.md`

**Files:**
- Modify: `docs/roadmap.md`

**Step 1: Make the edit**

In `docs/roadmap.md`, find the end of the Phase 2C section (the line that reads `- **Convenience helpers**: Shorter names for common patterns — deferred`) and insert the Phase 2D block immediately after it, before the `## Phase 3` heading:

Old (lines 39–42):
```
- **Method chaining**: Fluent configuration for Runtime — deferred
- **Convenience helpers**: Shorter names for common patterns — deferred

## Phase 3 — Performance
```

New:
```
- **Method chaining**: Fluent configuration for Runtime — deferred
- **Convenience helpers**: Shorter names for common patterns — deferred

### Phase 2D: Graceful Error Handling ✓

- ~~**Raised-error rollback in `Runtime::batch`**~~ ✓ Implemented
  - `Runtime::batch` accepts `f : () -> Unit raise?`; raised errors roll back all pending signal writes before re-raising
  - `rollback_pending` closure added to `CellMeta` for per-signal rollback hooks
- ~~**`batch_result`**: Transactional batch returning `Result` instead of re-raising~~ ✓ Implemented
  - `Runtime::batch_result(f)` and `@incr.batch_result(db, f)` Database helper form
- ~~**Convenience reads**: `get_or` and `get_or_else` for cycle-safe reads without pattern matching~~ ✓ Implemented
  - `Memo::get_or(fallback : T) -> T`, `Memo::get_or_else(fallback : (CycleError) -> T) -> T`
  - `MemoMap::get_or`, `MemoMap::get_or_else` with identical semantics

## Phase 3 — Performance
```

**Step 2: Run regression check**

```bash
moon test
```
Expected: `Total tests: 200, passed: 200, failed: 0.`

**Step 3: Commit**

```bash
git add docs/roadmap.md
git commit -m "docs: add Phase 2D (graceful error handling) to roadmap"
```

---

### Task 2: Add Phase 2D checklist to `docs/todo.md`

**Files:**
- Modify: `docs/todo.md`

**Step 1: Make the edit**

In `docs/todo.md`, find the end of the Phase 2C ergonomics section (the line `- [ ] Explore RAII \`BatchGuard\` if MoonBit adds destructors`) and insert the Phase 2D subsection immediately after it, before the `### Advanced (Phase 4)` heading:

Old (lines 76–78):
```
- [ ] Explore RAII `BatchGuard` if MoonBit adds destructors

### Advanced (Phase 4)
```

New:
```
- [ ] Explore RAII `BatchGuard` if MoonBit adds destructors

### Graceful Error Handling (Phase 2D — Done)

- [x] Add raised-error rollback to `Runtime::batch` (accepts `() -> Unit raise?`)
- [x] Add `rollback_pending` closure to `CellMeta` for per-signal batch rollback hooks
- [x] Add `Runtime::batch_result` returning `Result[Unit, Error]` instead of re-raising
- [x] Add `@incr.batch_result(db, f)` Database helper form
- [x] Add `Memo::get_or(fallback : T) -> T` for cycle-safe reads without pattern matching
- [x] Add `Memo::get_or_else(fallback : (CycleError) -> T) -> T`
- [x] Add `MemoMap::get_or` and `MemoMap::get_or_else` with identical semantics

### Advanced (Phase 4)
```

**Step 2: Run regression check**

```bash
moon test
```
Expected: `Total tests: 200, passed: 200, failed: 0.`

**Step 3: Commit**

```bash
git add docs/todo.md
git commit -m "docs: add Phase 2D graceful error handling checklist to todo"
```

---

### Task 3: Close out `docs/plans/2026-02-25-panic-safety-hardening.md`

**Files:**
- Modify: `docs/plans/2026-02-25-panic-safety-hardening.md`

This task has three sub-edits applied in sequence to the same file. Commit once at the end.

**Step 1a: Add status header**

Find the line `**Important language constraint:** MoonBit \`abort()\` is not catchable. We can recover from \`raise\`, but not from \`abort\`.` and insert a status line after the closing `---` divider that follows it:

Old (lines 8–11):
```
**Important language constraint:** MoonBit `abort()` is not catchable. We can recover from `raise`, but not from `abort`.

---

### Scope
```

New:
```
**Important language constraint:** MoonBit `abort()` is not catchable. We can recover from `raise`, but not from `abort`.

**Status:** Complete ✓ — all tasks implemented and verified. See `docs/plans/2026-03-03-panic-safety-docs-design.md` for the follow-up docs-pass design.

---

### Scope
```

**Step 1b: Fix stale `internal/` paths in Progress Snapshot**

Old (lines 29–30):
```
  - `internal/batch_wbtest.mbt`
  - `internal/verify_wbtest.mbt`
```

New:
```
  - `cells/batch_wbtest.mbt`
  - `cells/verify_wbtest.mbt`
```

**Step 1c: Fix stale `internal/` paths in Task 2 and Task 3**

Old (lines 65–68):
```
- Modify: `internal/runtime.mbt`
- Modify: `internal/memo.mbt`
- Modify: `internal/verify.mbt`
- Modify tests under `internal/*_wbtest.mbt`
```

New:
```
- Modify: `cells/runtime.mbt`
- Modify: `cells/memo.mbt`
- Modify: `cells/verify.mbt`
- Modify tests under `cells/*_wbtest.mbt`
```

Old (lines 99–102):
```
- Modify: `internal/*.mbt`
- Modify: `traits.mbt`
- Modify: `incr.mbt` (re-exports if needed)
- Modify tests in `tests/*.mbt`
```

New:
```
- Modify: `cells/*.mbt`
- Modify: `traits.mbt`
- Modify: `incr.mbt` (re-exports if needed)
- Modify tests in `tests/*.mbt`
```

**Step 1d: Mark each task header complete**

For each of the five task headings, append ` ✓` to the heading line:

| Old | New |
|-----|-----|
| `### Task 1: Finish graceful API documentation pass` | `### Task 1: Finish graceful API documentation pass ✓` |
| `### Task 2: Audit and reduce user-triggerable aborts` | `### Task 2: Audit and reduce user-triggerable aborts ✓` |
| `### Task 3: Add explicit non-panicking entrypoints where missing` | `### Task 3: Add explicit non-panicking entrypoints where missing ✓` |
| `### Task 4: Validate behavior and coverage` | `### Task 4: Validate behavior and coverage ✓` |
| `### Task 5: Update project tracking docs` | `### Task 5: Update project tracking docs ✓` |

**Step 2: Run regression check**

```bash
moon test
```
Expected: `Total tests: 200, passed: 200, failed: 0.`

**Step 3: Commit**

```bash
git add docs/plans/2026-02-25-panic-safety-hardening.md
git commit -m "docs: close out panic-safety-hardening plan; fix stale internal/ paths"
```

---

### Task 4: Add `get_or`/`get_or_else` examples to `README.md`

**Files:**
- Modify: `README.md`

**Step 1: Make the edit**

In `README.md`, find the end of the `get_result()` example block in the "Graceful Error Handling" section. The closing ` ``` ` of that block is followed immediately by the line `` `Runtime::batch` (and `@incr.batch`) also supports raised-error rollback: ``.

Insert a `get_or`/`get_or_else` paragraph between those two points:

Old (lines 121–123):
```
}
```

`Runtime::batch` (and `@incr.batch`) also supports raised-error rollback:
```

New:
```
}
```

For a shorter form without pattern matching, use `get_or` or `get_or_else`:

```moonbit
// Inline fallback value
let value = sum.get_or(0)

// Fallback computed from the error
let value = sum.get_or_else(err => {
  println(err.format_path(app.runtime()))
  0
})
```

`Runtime::batch` (and `@incr.batch`) also supports raised-error rollback:
```

**Step 2: Run regression check**

```bash
moon test
```
Expected: `Total tests: 200, passed: 200, failed: 0.`

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add get_or/get_or_else examples to README graceful error handling"
```

---

## Acceptance Criteria

- `docs/roadmap.md` has a "Phase 2D: Graceful Error Handling ✓" sub-section after Phase 2C listing all panic-safety features.
- `docs/todo.md` has a "Graceful Error Handling (Phase 2D — Done)" sub-section with all 7 items checked.
- `docs/plans/2026-02-25-panic-safety-hardening.md` has `**Status:** Complete ✓`, no `internal/` references, and all 5 task headings end with ` ✓`.
- `README.md` "Graceful Error Handling" section includes `get_or`/`get_or_else` examples between the `get_result()` block and the `batch` block.
- `moon test` passes with no regressions after every task.
