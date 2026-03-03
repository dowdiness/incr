# Panic-Safety Docs Pass — Design

**Date:** 2026-03-03
**Status:** Approved
**Scope:** Documentation-only; no source code changes.

## Problem

The `2026-02-25-panic-safety-hardening` plan implemented raised-error rollback in `Runtime::batch`, `batch_result`, `get_or`/`get_or_else`, and related features. The implementation is complete and all tests pass, but three gaps remain in the project's documentation:

1. `roadmap.md` has no record of the panic-safety features (Phase 2D).
2. `todo.md` has no checklist entries for those features.
3. `2026-02-25-panic-safety-hardening.md` still references the old `internal/` package path (renamed to `cells/`) and has no completion markers on its tasks.
4. `README.md` shows `get_result()` and `batch_result` but omits `get_or`/`get_or_else`.

## Approach

**Approach B (selected):** Update tracking docs, close the plan file, and extend README.

User-facing reference docs (`api-reference.md`, `design.md`, `getting-started.md`) are already comprehensive and require no changes.

## Changes

### 1. `docs/roadmap.md` — Add Phase 2D subsection

Insert a new **Phase 2D: Graceful Error Handling ✓** sub-section after Phase 2C, listing:

- Raised-error rollback in `Runtime::batch`
- `rollback_pending` closure on `CellMeta`
- `Runtime::batch_result` / `@incr.batch_result`
- `Memo::get_or`, `Memo::get_or_else`, `MemoMap::get_or`, `MemoMap::get_or_else`

The existing top-level Phase 2 bullet (`Batch updates`) is unchanged — it describes revision-bump semantics. Phase 2D captures the error-safety layer built on top.

### 2. `docs/todo.md` — Add Phase 2D checklist

Under "API Improvements", add a **"Graceful Error Handling (Phase 2D — Done)"** subsection with all items pre-checked:

```
- [x] Add raised-error rollback to `Runtime::batch` (accepts `() -> Unit raise?`)
- [x] Add `rollback_pending` closure to `CellMeta` for per-signal batch rollback hooks
- [x] Add `Runtime::batch_result` returning `Result[Unit, Error]` instead of re-raising
- [x] Add `@incr.batch_result(db, f)` Database helper form
- [x] Add `Memo::get_or(fallback : T) -> T` for cycle-safe reads without pattern matching
- [x] Add `Memo::get_or_else(fallback : (CycleError) -> T) -> T`
- [x] Add `MemoMap::get_or` and `MemoMap::get_or_else` with identical semantics
```

### 3. `docs/plans/2026-02-25-panic-safety-hardening.md` — Close out plan

- Replace all `internal/` path references with `cells/` throughout the file.
- Add `Status: Complete` to the plan header.
- Add a completion marker at the top of each Task block (Tasks 1–5).

### 4. `README.md` — Add `get_or`/`get_or_else` examples

In the "Graceful Error Handling" section, insert after the `get_result()` example:

> For a shorter form without pattern matching, use `get_or` or `get_or_else`:
>
> ```moonbit
> // Inline fallback value
> let value = sum.get_or(0)
>
> // Fallback computed from the error
> let value = sum.get_or_else(err => {
>   println(err.format_path(app.runtime()))
>   0
> })
> ```

## Out of Scope

- `concepts.md` — raised-error rollback is already covered in `getting-started.md`; no duplication needed.
- `api-design-guidelines.md` — no new patterns to add.
- Source code — no changes.

## Acceptance Criteria

- `roadmap.md` has a Phase 2D subsection listing all panic-safety features as ✓.
- `todo.md` has a "Graceful Error Handling (Phase 2D)" subsection with all items checked.
- `2026-02-25-panic-safety-hardening.md` has no `internal/` references and all tasks are marked complete.
- `README.md` "Graceful Error Handling" section includes `get_or`/`get_or_else` examples.
- `moon test` passes with no regressions (docs-only change).
