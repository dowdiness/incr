# Typed spreadsheet — cross-root locality validation 2026-06-24

Implementation: PR [#294](https://github.com/dowdiness/incr/pull/294).

## Environment

| | |
|---|---|
| Date | 2026-06-24 |
| CPU | AMD Ryzen 7 6800H (WSL2) |
| Toolchain | moon 0.1.20260608 |
| Reactive engine | `dowdiness/incr@0.10.1` |
| JS runtime | Node v24.14.1 |
| Measurement | `BrowserRenderer::root_stats().view_recomputes` (per-root), `BrowserRenderer::stats()` (aggregate) |
| Command | `moon test` (1063 tests pass) |

## Per-root dependency map

Each root's view `Derived` calls `InputField::get()` on only the fields it reads.

| Root | Reads via `InputField::get()` | Depends on |
|---|---|---|
| Grid | `cells`, `selected_cell`, `editing_cell`, `drafts`, `committed` | 5 fields |
| FormulaBar | `selected_cell`, `drafts` | 2 fields |
| Status | `status`, `error` | 2 fields |
| Trace | `trace`, `last_edit` | 2 fields |

## Measured: per-root view_recomputes

The derived-event listener (`install_render_recompute_counter`) counts every
`Derived` evaluation. One recompute per dispatch batch per root whose
InputField dependencies changed.

### Scenario 1 — Cell value edit

Dispatch: `SelectCell("A1")` → `UpdateDraft("A1","42")` → `ApplySelected`

| Root | Recomputed | Rationale |
|---|---|---|
| Grid | yes | `selected_cell` (B1→A1), `drafts`, `committed` changed |
| FormulaBar | yes | `selected_cell` changed, `drafts` changed |
| Status | yes | `status` written by each handler |
| Trace | yes | `trace` set by `ApplySelected` |

All four roots recompute — the edit touches fields across every region.

### Scenario 2 — Selection only

Dispatch: `SelectCell("A2")`

| Root | Recomputed | Rationale |
|---|---|---|
| Grid | yes | `selected_cell` changed (B1→A2) |
| FormulaBar | yes | `selected_cell` changed |
| Status | yes | `status` written |
| Trace | **no** | `trace` and `last_edit` unchanged |

Trace skips — its two InputFields are untouched by `SelectCell`.

### Scenario 3 — Draft only

Dispatch: `UpdateDraft("A1","99")`

| Root | Recomputed | Rationale |
|---|---|---|
| Grid | yes | `selected_cell` changed (B1→A1), `drafts` changed |
| FormulaBar | yes | `selected_cell` changed, `drafts` changed |
| Status | **no** | `update_draft_for_cell` no longer writes `status` (PR #294 fix) |
| Trace | **no** | `trace` and `last_edit` unchanged |

Status and Trace skip — neither region's InputFields changed.

### Scenario 4 — Inline edit commit

Dispatch: `BeginInlineEdit("C1")` → `UpdateDraft("C1","7")` → `ApplyInlineEdit("C1")`

| Root | Recomputed | Rationale |
|---|---|---|
| Grid | yes | `editing_cell`, `selected_cell`, `drafts` changed |
| FormulaBar | yes | `selected_cell` changed, `drafts` changed |
| Status | yes | `status` written by `begin_inline_edit` |
| Trace | yes | `trace` set by `ApplyInlineEdit` effect |

All four roots recompute — inline edit touches all regions.

### Scenario 5 — Status only

| Root | Recomputed | Rationale |
|---|---|---|
| Grid | **no** | No field in grid's dependency set changes |
| FormulaBar | **no** | No field in formula bar's dependency set changes |
| Status | yes | `status` InputField changed |
| Trace | **no** | No field in trace's dependency set changes |

The clearest locality win — one region's data change is isolated to that root.

## Not yet measured: per-root patch/skip counts

`BrowserRenderer::root_stats()` exposes `patch_attempts` and `skipped_patches`
fields, but these are currently the **shared aggregate** counters — all roots
report the same values. Per-root DOM patch decisions are pending
[#295](https://github.com/dowdiness/incr/issues/295).

The aggregate `BrowserRenderer::stats()` counters show the total across all roots:

| Aggregate counter | Expected behavior |
|---|---|
| `patch_attempts` | Sum of per-root patches (currently correct aggregate) |
| `skipped_patches` | Sum of per-root skips (currently correct aggregate) |
| `inactive_skipped_flushes` | Sum of per-root inactive skips (correct aggregate) |

## Expected comparison with Rabbita (single-root)

The Rabbita version at `examples/typed_spreadsheet_rabbita_demo/` uses a single
render cycle with no dependency tracking — every message causes a full view
rebuild and DOM diff. The following table is a **structural comparison**, not a
timing measurement.

| Scenario | incr_tea roots recomputed | Rabbita recomputed (inferred) |
|---|---|---|
| Selection only | 3 of 4 | 1 of 1 (full rebuild) |
| Draft only | 2 of 4 | 1 of 1 |
| Status only | 1 of 4 | 1 of 1 |
| Cell value edit | 4 of 4 | 1 of 1 |
| Inline edit commit | 4 of 4 | 1 of 1 |

The savings come in scenarios where at least one root's dependencies are
unchanged — incr's verify phase backdates those roots' view `Derived`s, and
`WatchedHtmlRoot::read_changed` skips the DOM patch. A DOM-timing comparison
needs [#295](https://github.com/dowdiness/incr/issues/295) for per-root
patch/skip counters, then a shared interaction harness
([#296](https://github.com/dowdiness/incr/issues/296)).

## Limitations

- Per-root `patch_attempts`/`skipped_patches` remain shared/aggregate (#295)
- No automated browser measurement harness exists (#296)
- Rabbita comparison is structural (not timed)
- Per-root `view_recomputes` includes the initial mount (each root starts at 1)
