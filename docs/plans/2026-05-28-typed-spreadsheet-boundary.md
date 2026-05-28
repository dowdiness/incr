# Typed Spreadsheet Responsibility Boundary

**Status:** Proposed

**Date:** 2026-05-28

## Goal

Define the precise contract for building a typed spreadsheet-style app on top of
`incr` without expanding `incr` with spreadsheet-specific APIs.

## Why this boundary matters

`incr` already covers reactive graph execution, freshness tracking, batching,
callbacks, disposal, and observational hooks.
The spreadsheet layer should supply typing, formulas, layout, editing, and
storage policies, and should only use the existing `incr` target APIs.

## What `incr` already guarantees

Use these APIs and invariants as the base contract:

- **Input mutation and batching**
  - `Input::set` and `Input::force_set` with same-value no-op behavior on
    `set` and rollback on raised batch errors.
  - `Runtime::batch` / `Runtime::batch_result` as the unit of atomic graph
    commits.

- **Recompute and read semantics**
  - `Input::get` / `Input::peek` (dependency-tracked vs non-tracked input reads), `Derived::read`, `Derived::read_or_abort`.
  - Backdating behavior (`changed_at`, `verified_at`) and no-op stability checks.

- **Graph lifecycle**
  - `Scope` ownership/`dispose`, `Input`/`Memo` disposal, `Watch` and `Observer` keep-alives.
  - `Runtime::gc` and `Watch::dispose`-driven retention boundaries.

- **Observation and diagnostics**
  - `set_on_change` and per-cell `on_change` callbacks.
  - Prefer `Watch` for new external subscribers; use `Observer` only for
    compatibility or when existing API requires it.
  - `Runtime::cell_info`/`CellInfo` provides point-in-time snapshots.
  - `Runtime::on_memo_event` provides recompute trace events.

- **Multi-mode execution support**
  - Pull verification and push/invalidation behavior remain stable via the public
    wrappers (`Derived`, `ReachableDerived`, `MemoMap`, `Relation`, etc.).

## Responsibility split for a typed spreadsheet

Keep the following in `incr` (minimum contract):

- Signal and derived creation, dependency registration, recompute triggering,
  validity checks, and revision progression.
- Event ordering and callback execution guarantees used by spreadsheet UI,
  persistence hooks, and test instrumentation.
- Subsystem lifecycle (`Scope`, `Watch`, `Runtime`, `gc`, batching)
  and disposal safety.

Move to spreadsheet application code:

- Canonical typed model for cell identity, address spaces, and value types.
- Formula language/parser and its static/typed semantics.
- Parsing and validating mutable editor state (selection, copy/paste, undo/redo,
  clipboard, imports/exports).
- Domain-specific persistence and synchronization policies.
- UI rendering/reconciliation and event handling (keyboard, pointer, focus,
  scroll, virtualization).
- Deterministic conflict resolution when editing or reconciling remote updates.

## In-band integration pattern

Recommended minimal graph shape:

- One `InputField` per logical spreadsheet field and one `Scope` per worksheet.
- Each formula computes into one `Derived` with explicit labeling for debug
  inspectability.
- Shared `Runtime` per editing session; per-document `Scope` for
  tear-down/undo-session reuse.
- Use `Watch` for external subscribers by default, and `Observer` only for
  compatibility or legacy usage.
- For batch failure handling, spreadsheet code should keep `Runtime::batch` paths
  `Result`-aware (through `batch_result` / `try?`) and avoid raising `Error`
  from within `Runtime::batch` if commit integrity matters.
- Keep `Runtime::cell_info` (snapshot) and `Runtime::on_memo_event` (trace)
  separate to avoid diagnostic role conflation.

## Acceptance checklist for next iteration

- [x] Add a short checked fixture that verifies:
  - [x] atomic edits inside `Runtime::batch` and rollback on raised failure;
  - [x] formula recompute event ordering and callback suppression under no-op updates;
  - [x] `cell_info` exposes expected changed/verified progression and
    dependencies.
- [x] Add one integration test for `Scope::dispose` removing an entire sheet while
  preserving unrelated scopes.
- [x] Add an observability smoke test combining `set_on_change` and `Watch` for one
  formula chain and one push-reactive chain.
- [x] Add `tests/typed_spreadsheet_spikes_test.mbt` and `docs/README` link in this
  plan before any `Expr`-style sugar work is started.
