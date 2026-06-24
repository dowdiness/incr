# Plan: Typed Spreadsheet — Cross-Root Locality Validation

**Date:** 2026-06-24
**Status:** Partial — Phases 1–2 complete, Phase 3 partial (view_recomputes only), Phases 4–5 pending
**PR:** [dowdiness/incr#294](https://github.com/dowdiness/incr/pull/294)
**Driver:** [typed_spreadsheet_incr_tea_demo](../../examples/typed_spreadsheet_incr_tea_demo/)
**Research context:** [incr_tea UI direction](../../docs/research/incr-tea-ui-direction.md) (success metric: "unchanged child roots skip patching across parent updates")
**Performance baseline (single-root):** [incr_tea vs dirty-cell benches](../../docs/performance/2026-06-10-incr-tea-vs-dirty-cell-benches.md)

## Goal

Convert the single-root `TypedSheetApp` into 4 independent watched roots (grid, formula bar, status, trace) that share model state via per-region `InputField`s. Validate that a change to one region's data leaves the other roots' view `Derived`s unevaluated (or backdate-equal) and their DOM patches skipped.

## Current state

`examples/typed_spreadsheet_incr_tea_demo/` uses a **single** `@tea.Program[Msg, Html[Msg]]` whose `view()` reads the full `Model` struct (cells, drafts, selected_cell, editing_cell, status, error, trace_data, last_edit). Every model change — regardless of which field changed — recomputes the entire view tree and diffs the full DOM.

## Design

### State: per-region InputFields

Owned by a shared `SheetState` struct holding one `@incr.Scope` + all
`InputField`s. The `Program`s receive a `SheetState` value (the handles are
shared). The scope lives as long as the sheet is mounted (the main module holds
it). Each `InputField` tracks its own revision, so `selected_cell.set(...)` does
not invalidate `status`'s dependents.

Replace the monolithic `Ref[Model]` + `version : InputField[Int]` tick with individual `InputField`s, one per logical region:

| InputField | Read by roots | Written by update handlers |
|---|---|---|
| `selected_cell : InputField[String]` | Grid, FormulaBar, Status | `select_cell`, `move_selection`, `begin_inline_edit` |
| `drafts : InputField[Array[CellDraft]]` | Grid, FormulaBar | `update_draft_for_cell`, `use_example`, `apply_text_edit` … |
| `committed : InputField[Array[CellDraft]]` | (for dirty check) Grid | `apply_text_edit`, `delete_selected` |
| `editing_cell : InputField[String?]` | Grid | `begin_inline_edit`, `cancel_selected`, `apply_text_edit` |
| `status : InputField[String]` | Status | all handler functions |
| `error : InputField[String?]` | Status | parse/edit error paths |
| `trace : InputField[TraceData?]` | Trace | edit operations |
| `last_edit : InputField[String]` | Trace | `apply_operation` |
| `cells : InputField[Array[String]]` | Grid | `reset_sheet` only (the grid shape is fixed for the proof) |

Each handler updates only the `InputField`s its region owns. A cell-value edit touches `drafts`, `committed`, `status`, `trace`, `last_edit` **but not** `selected_cell` or `editing_cell`. A selection-change touches `selected_cell`, `status` **but not** `drafts`, `cells`, `trace`.

### View: per-region Programs

Four independent `Program`s, each reading only its slice:

```text
GridProgram:
  view() reads cells, selected_cell, editing_cell, drafts, committed
  → depends on 5 InputFields
  → skips when only status/error/trace data changes

FormulaBarProgram:
  view() reads selected_cell, drafts
  → depends on 2 InputFields
  → skips when cell values change but selection is stable

StatusProgram:
  view() reads status, error
  → depends on 2 InputFields
  → skips when only grid data or trace data changes

TraceProgram:
  view() reads trace, last_edit
  → depends on 2 InputFields
  → skips when only selection/draft changes
```

Each `Program` receives a `SheetState` value (the handles inside are shared)
for read access, but creates its own `@incr.Scope` for the view `Derived`/
`Watch` — so disposing one program's scope does not affect the shared
InputFields or the other roots.

### Mounting

`BrowserRenderer::mount` four roots on four sibling host divs. `BrowserRenderer::root_stats()` exposes per-root `view_recomputes`.

### Update: shared handler module

The `handle_msg` function moves to a shared module. Each handler updates the relevant `InputField`s:

```moonbit
fn select_cell(
  selected_cell : @incr.InputField[String],
  status : @incr.InputField[String],
  cell : String,
) -> Unit {
  selected_cell.set(cell)
  status.set("Selected \{cell}.")
}
```

No `Cmd` is returned for pure-model changes (returns `Cmd::none()`). The `Cmd::focus_element_by_id` for inline-edit remains, dispatched from the grid program's handler.

### Commands across roots

`Cmd::focus_element_by_id` targets a DOM element by id. Since all roots share one `BrowserRenderer`, the post-flush `focusElementById` implementation works regardless of which root's handler queued it — it calls `document.getElementById` on the shared document. No cross-root command routing needed.
### Instrumentation: per-root named counters

`RenderStats` provides `BrowserRenderer::stats()` (aggregate) and
`BrowserRenderer::root_stats()` (per-root `view_recomputes`). Per-root
`patch_attempts`/`skipped_patches` remain aggregate-only (see #295).

In Phase 3:

1. Give each `BrowserRoot` its own `RenderStats` (or per-root counters)
   tracked independently, with a `label : String` captured from
   `Program.label` or passed at mount time.
2. Expose per-root stats via a new accessor:

   ```moonbit
   pub struct RootStats {
     label : String
     view_recomputes : Int
     patch_attempts : Int
     skipped_patches : Int
   }
   pub fn BrowserRenderer::root_stats(self) -> Array[RootStats]
   ```
3. Keep the aggregate `BrowserRenderer::stats()` summing per-root values
   so existing callers (tests, after_flush callback) see correct totals.

For the validation test, a `flush_and_collect_stats()` helper drives one flush
cycle, reads per-root counters before and after, and returns the delta per root.

### Validation test

In `examples/typed_spreadsheet_incr_tea_demo/` (or a new `_wbtest.mbt`):

| Scenario | Action | Expected patch | Expected skip |
|---|---|---|---|
| Cell value edit | `UpdateDraft("A1", "42")` + `ApplySelected` | Grid (cell text changed), Status ("Applied" text), Trace (new step) | FormulaBar (selection unchanged) |
| Selection only | `SelectCell("A2")` | Grid (aria-selected), FormulaBar (selected_cell label), Status ("Selected A2") | Trace (trace_data unchanged) |
| Draft only (no commit) | `UpdateDraft("A1", "99")` | Grid (dirty class toggles), FormulaBar (draft text) | Status, Trace |
| Inline edit commit | `BeginInlineEdit("A1")` then `ApplyInlineEdit("A1")` | Grid (cell → input swap), FormulaBar (draft), Status, Trace | — (most roots change) |
| Status-only (future) | Set status text directly | Status | Grid, FormulaBar, Trace |

Each test records and asserts per-root recompute/patch counts, not just DOM state.

## Phases

### Phase 1 — State refactor (no behavior change)

- Replace `Ref[Model]` + `version` tick with per-region `InputField`s in a shared `SheetState` struct
- Rewrite each handler to update only its relevant `InputField`s
- Keep the single `Program` with the existing `view_model()` reading all fields
- **Verification:** all existing tests pass; spreadsheet renders identically in browser

### Phase 2 — View split

- Extract 4 `Program` constructors, each reading its slice
- Mount 4 roots in `main.mbt`
- **Verification:** spreadsheet renders identically; no change in visible behavior

### Phase 3 — Instrumentation + stats exposure

- Add `label : String` to mount config (captured from mount parameter)
- Expose per-root `view_recomputes` in `BrowserRenderer::root_stats()`
- Per-root `patch_attempts`/`skipped_patches` remain aggregate-only (tracked as [#295](https://github.com/dowdiness/incr/issues/295))
- **Verification:** all existing tests pass; `root_stats()` returns labeled recompute counts

### Phase 4 — Validation tests

- Write 5 test scenarios from the table above
- Each test asserts specific per-root skip/patch counts
- **Verification:** all 5 tests pass

### Phase 5 — Measurement record

- Run the 5 scenarios, record per-root recompute and patch times
- Compare against single-root baseline
- Write `docs/performance/2026-06-24-typed-spreadsheet-cross-root-locality.md`
- If any region fails to skip when expected, file a bug
## Follow-up issues

- [#295](https://github.com/dowdiness/incr/issues/295) — Per-root patch/skip counters: redesign stats to store per-root records (not keyed only by view_id)
- [#296](https://github.com/dowdiness/incr/issues/296) — Cross-root locality validation tests: automated assertions for the 5 scenarios listed above

## Risks

