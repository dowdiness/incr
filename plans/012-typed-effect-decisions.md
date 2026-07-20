# Plan 012: Establish an adapter-ready strong `SheetCommand` boundary

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan in
> `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 6c30120..HEAD -- examples/typed_spreadsheet_incr_tea_demo examples/typed_spreadsheet incr_tea/command.mbt incr_tea/program.mbt incr_tea/renderer_js.mbt docs/decisions/2026-07-19-independent-differential-dataflow-module.md`
> If an in-scope source file changed, compare the "Current state" excerpts with
> the live code before proceeding. Stop on a semantic mismatch; line-number-only
> drift is not by itself a reason to stop.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: architecture / tech-debt
- **Planned at**: commit `6c30120`, 2026-07-20
- **Related EGW research**: [dowdiness/event-graph-walker#72](https://github.com/dowdiness/event-graph-walker/issues/72)

## Why this matters

The typed-spreadsheet driver currently hides application intent inside
`Cmd::effect` closures. An apply closure captures a cell but reads the draft
again when it executes; delete and reset similarly combine intent, local UI
preconditions, worksheet mutation, Runtime access, and lifecycle effects. This
is adequate for the current synchronous scheduler, but it is the wrong boundary
for a future collaborative document: an adapter cannot reliably translate an
opaque closure into one or more Event Graph Walker (EGW) operations.

This plan establishes a strong, closure-free application command:

```text
owned UI snapshot + Msg
  -> SheetPlan {
       command: SheetCommand?,
       ui_effect: UiEffect?,
     }

SheetCommand
  -> current local-precondition validation
  -> current imperative interpreter
  -> worksheet mutation

Future, separate adapter:
SheetCommand
  -> EGW transaction
  -> merged EGW state
  -> pure spreadsheet projection
  -> Runtime::batch
  -> incr InputFields
```

A strong command owns the submitted formula text, typed cell identity, document
generation, and explicit local UI precondition. It describes the request that
was submitted; the interpreter must not decide its payload by rereading the
latest draft. The same command may still produce different results against
different document states, so this plan guarantees a self-contained request,
not deterministic replay of outcomes.

The plan deliberately does not add EGW, change `incr_tea.Cmd`, or create a
generic `egw_incr` bridge. It creates an application-local boundary that a
future typed-spreadsheet/EGW adapter can consume after the command types are
promoted to an importable domain package. General bridge extraction remains
gated on a second application-shaped driver.

## Architectural decisions fixed by this plan

### Authority

- A future EGW document will own committed collaborative content, operation
  identity, causal history, merge, and convergence.
- The adapter will own projection from merged EGW state into spreadsheet/incr
  inputs.
- incr will own reactive dependency tracking, revisions, caches, and views; an
  incr `Revision` is not a document version.
- Selection, editing identity, focus, uncommitted drafts, and viewport remain
  local UI state unless a later product decision says otherwise.
- AI-context publication remains a global post-update/post-flush shell policy,
  not a collaborative document command.

### Time and identity domains

Do not identify or combine:

- application `SheetCommand` identity or `DocumentGeneration`;
- future EGW operation IDs, replica IDs, versions, or causal heads;
- incr `Revision`;
- dataflow `Epoch`.

One `SheetCommand` may lower to several EGW operations. Therefore application
commands and EGW operations must never share an identity type. EGW operation
IDs and causal parents will be allocated by the authoritative EGW document at
commit time, not predicted by this driver.

### Local and remote update path

A future adapter must route both sources through one projection path:

```text
local SheetCommand ─┐
                    ├─> authoritative EGW state changed
remote SyncMessage ─┘
                           -> projection
                           -> Runtime::batch
                           -> InputFields
```

Do not let local commands mutate collaborative InputFields directly while
remote sync uses a separate projection path. The current direct worksheet
interpreter is only a pre-EGW shell retained by this plan.

## Current state

### Files and roles

- `examples/typed_spreadsheet_incr_tea_demo/app.mbt` — shared update handler for
  five watched roots; directly chooses immediate handlers and opaque commands.
- `examples/typed_spreadsheet_incr_tea_demo/model.mbt` — `SheetState`, `Msg`,
  draft helpers, immediate UI mutation, and four direct `Cmd::effect` helpers.
- `examples/typed_spreadsheet_incr_tea_demo/ai_context.mbt` — global post-flush
  AI-context publication command.
- `examples/typed_spreadsheet_incr_tea_demo/model_wbtest.mbt` — existing model,
  reset, focus, and AI-context regression coverage.
- `examples/typed_spreadsheet_incr_tea_demo/scripts/test-dom.mjs` — real-browser
  focus, edit, reset, and AI-context checks.
- `examples/typed_spreadsheet/ids.mbt` — existing typed `SheetId` and `CellId`.
- `incr_tea/command.mbt` and `incr_tea/program.mbt` — opaque framework command
  representation and synchronous interpreter; unchanged by this plan.
- `../examples/lambda/crdt_egw_test.mbt` — limited authority-order precedent:
  both local edits and remote sync update EGW first, then derive text and update
  an imperative parser. It does **not** implement an incr adapter, shared
  `Runtime::batch` projection, or the full future contract specified here.

### Load-bearing excerpts

`app.mbt:66-87` currently creates one opaque command and unconditionally
schedules AI publication after it:

```moonbit
let command = match msg {
  ...
  ApplySelected => apply_selected_cmd(state)
  DeleteSelected => delete_selected_cmd(state)
  ResetSheet => reset_sheet_cmd(runtime, state)
  ...
  ApplyInlineEdit(cell) => apply_inline_edit_cmd(state, cell)
  ...
}
@tea.Cmd::batch([command, publish_ai_context_cmd(state)])
```

`model.mbt:426-453` captures identity but rereads text at execution time:

```moonbit
fn apply_selected_cmd(state : Ref[SheetState]) -> @tea.Cmd[Msg] {
  let cell = state.val.selected_cell.peek()
  @tea.Cmd::effect(_ => {
    if state.val.selected_cell.peek() == cell {
      apply_text_edit(
        state,
        cell,
        draft_text_from(state.val.drafts.peek(), cell),
      )
    }
  })
}
```

`Program::handle_message` and `run_cmd` execute returned effects synchronously
after the update batch (`incr_tea/program.mbt:154-185`). Thus current dispatch
cannot naturally interleave another message between planning and execution.
Existing stale-selection/editor guards are retained as future-proof shell
preconditions, but tests must exercise the extracted pure validator or direct
execution seam rather than claim such a race occurs through ordinary dispatch.

`SheetState` currently replaces its `Worksheet` during reset while reusing
logical `SheetId(1)` (`model.mbt:46-73`, `model.mbt:504-535`). A separate
`DocumentGeneration` is therefore required to distinguish commands admitted
before and after replacement.

### Existing characterization coverage

Before adding tests, inspect and reuse:

- `model_wbtest.mbt:72-126` — Program dispatch applies inline and selected
  edits.
- `model_wbtest.mbt:578-714` — AI context, reset, and worksheet behavior.
- `scripts/test-dom.mjs:99-220` — initial publication, focus, applied trace, and
  reset publication in Chromium.
- `locality_wbtest.mbt:185-291` — watched-root behavior for apply, selection,
  drafts, and inline editing.

Do not duplicate these as new characterization tests. Add only the pure command
planning/validation cases and the strong submitted-text/generation regressions
specified below.

## Existing API First / reuse check

Project APIs checked:

| Candidate | Defined at | Decision |
|---|---|---|
| `@typed_spreadsheet.CellId` | `examples/typed_spreadsheet/ids.mbt:31-47` | Reuse as command target. It already combines logical `SheetId` and address and derives `Eq`, `Hash`, and `Debug`. |
| `@typed_spreadsheet.SheetId` | `examples/typed_spreadsheet/ids.mbt:5-18` | Reuse in the owned planning snapshot when constructing command targets. It identifies a logical sheet, not a replacement generation. |
| `@demo.cell_id_to_string` | `examples/typed_spreadsheet_demo` public API | Reuse when a shell/UI boundary needs the address string; do not expose `CellId` fields or duplicate formatting. |
| `@demo.parse_cell_text_op` and `run_batched_op` | `examples/typed_spreadsheet_demo` | Reuse in the current imperative execution shell. Parsing remains execution work and its recoverable errors remain model state. |
| `Cmd::effect` | `incr_tea/command.mbt:51-53` | Reuse only in `interpret_sheet_command`; no framework change. |
| `Cmd::focus_element_by_id` | `incr_tea/renderer_js.mbt:49-58` | Reuse for `UiEffect::FocusInlineEditor`; do not duplicate DOM FFI. |
| `Cmd::batch` | `incr_tea/command.mbt:39-41` | Reuse to preserve immediate-command → document-command → AI-publication ordering and defensive snapshot semantics. |
| `publish_ai_context_cmd` | `ai_context.mbt:212-215` | Keep unchanged as the global post-flush policy and continue calling it for every message. It is intentionally not part of `SheetPlan`. |
| `Program::stateful_cmd` | `incr_tea/program.mbt:366-404` | Checked but not used: this demo intentionally has five watched roots sharing one InputField-backed state. |
| Existing `draft_text_from` | `model.mbt:186-191` | Reuse after widening its package-private input from `Array[CellDraft]` to `ArrayView[CellDraft]`, allowing an owned `ReadOnlyArray` snapshot to call it via `.view()`. |

MoonBit core APIs checked:

| Candidate | Decision |
|---|---|
| `ReadOnlyArray::from_array` | Reuse to make an owning defensive copy of drafts for the planning snapshot. Core implements it via a new `FixedArray`; it is not an aliasing `ArrayView`. |
| `ReadOnlyArray::view` / `ArrayView` | Reuse for read-only draft lookup after the owning copy exists. Do not retain a view without its owner. |
| `Option` | Reuse for optional command and UI effect plus optional editing cell. |
| `Result` | Keep existing parse/worksheet error handling. Do not add an error channel to `SheetCommand`; a command describes intent, not its execution result. |
| `Array` | Keep only for existing draft/model storage and framework batching. One message produces at most one document command and one UI effect, so `SheetPlan` uses `Option`, not arrays. |
| `@immut/vector.Vector` | Checked but not used: a plan contains at most two optional values and does not need persistent collection operations. |
| `HashMap` / immutable `HashMap` | Checked but not used: no keyed collection belongs in a single-message plan. |
| `String` / `StringView` | Store submitted text as owned `String`; never retain a borrowed `StringView` across command execution. |

EGW APIs checked but deliberately not used:

- `TextState`, `Document`, `Version`, `SyncMessage`, operation IDs, causal
  snapshots, and frontiers.
- Existing EGW APIs confirm that authoritative documents allocate operation
  identity and causal relationships. Importing or serializing those values in
  this application command would prematurely couple the boundary.

### New definitions and responsibility boundaries

- `DocumentGeneration` — package-local opaque value distinguishing replacements
  of the same logical sheet. It is not a CRDT version.
- `SheetCommand` — closure-free requested document operation whose variant
  binds owned payload, admitted generation, and the only valid local
  precondition. Selected apply/delete, editing apply, and reset are distinct
  variants, so mismatched operation/precondition pairs are unrepresentable.
- `UiEffect` — local post-render focus request, separate from document intent.
- `SheetPlan` — at most one command and one UI effect for one `Msg`.
- `SheetPlanningContext` — owned snapshot used only by the pure planner.
- `SheetExecutionContext` and `validate_sheet_command` — pure execution-time
  applicability decision used by both interpreter and direct tests.
- `interpret_sheet_command` — current imperative adapter from command data to
  existing `Cmd`; it is explicitly temporary until an EGW adapter owns commit.

## Target type shape

The executor should preserve this semantic shape. Exact MoonBit syntax may be
adjusted only to satisfy the current compiler without weakening the boundaries.

```text
DocumentGeneration(Int)
  initial()
  next()

SheetCommand
  ApplyFromSelection(
    target: CellId,
    submitted_text: String,
    generation: DocumentGeneration,
  )
  ApplyFromEditor(
    target: CellId,
    submitted_text: String,
    generation: DocumentGeneration,
  )
  DeleteFromSelection(target: CellId, generation: DocumentGeneration)
  ResetDocument(generation: DocumentGeneration)

UiEffect
  FocusInlineEditor(address: String)

SheetPlan {
  command: SheetCommand?
  ui_effect: UiEffect?
}

SheetPlanningContext {
  sheet_id: SheetId
  selected_cell: CellId
  editing_cell: CellId?
  drafts: ReadOnlyArray[CellDraft]
  generation: DocumentGeneration
}

SheetExecutionContext {
  selected_cell: CellId
  editing_cell: CellId?
  generation: DocumentGeneration
}

CommandApplicability
  Applicable
  StaleGeneration
  LocalPreconditionFailed
```

All value types derive `Eq` and `Debug` where their fields permit it.
`SheetPlanningContext` owns its draft snapshot. It must not expose a mutable
array from a retained result.

## Scope

**In scope** — the only source/docs files to modify or create:

- `examples/typed_spreadsheet_incr_tea_demo/sheet_command.mbt` — create; command
  values, pure planner, pure applicability validator, current interpreter.
- `examples/typed_spreadsheet_incr_tea_demo/sheet_command_wbtest.mbt` — create;
  pure planner/validator tests and direct execution regressions.
- `examples/typed_spreadsheet_incr_tea_demo/model.mbt` — add generation to
  `SheetState`; widen `draft_text_from` to `ArrayView`; add owned planning and
  execution snapshot helpers; extract command execution operations; remove old
  opaque effect helpers only after rewiring.
- `examples/typed_spreadsheet_incr_tea_demo/app.mbt` — rewire `handle_msg` to
  snapshot → pure plan → immediate local update → command/UI interpretation →
  unconditional AI publication.
- `examples/typed_spreadsheet_incr_tea_demo/model_wbtest.mbt` — add only the
  strong submitted-text and post-reset stale-generation regression if they
  cannot be expressed cleanly in `sheet_command_wbtest.mbt`.
- `examples/typed_spreadsheet_incr_tea_demo/README.md` — document authority,
  command semantics, future adapter, and non-goals.
- `examples/typed_spreadsheet_incr_tea_demo/pkg.generated.mbti` — generated by
  `moon info` only; inspect but never hand-edit.
- `plans/README.md` — executor updates Plan 012 status only.

**Out of scope** — do not modify:

- `examples/typed_spreadsheet_incr_tea_demo/ai_context.mbt`; its global policy
  stays unchanged.
- `incr_tea/command.mbt`, `program.mbt`, `renderer_js.mbt`, or any
  `incr_tea/*.mbti`.
- `examples/typed_spreadsheet`, `examples/typed_spreadsheet_demo`, or their
  public APIs.
- `incr/`, `dataflow/`, Event Graph Walker source, parent Loom source, or any
  submodule pointer.
- A future EGW adapter package, command serializer, command ID/dedup store,
  async runtime, network transport, generic `Program` effect parameter, or
  generic `egw_incr` module.
- Formula CRDT policy (atomic register versus sequence text); decide it in the
  adapter ADR with a real collaborative driver.
- Benchmarks, dependency installation, deployment, publication, issues, or pull
  requests.

Expected generated change:
`examples/typed_spreadsheet_incr_tea_demo/pkg.generated.mbti` records new
package-visible cross-file symbols. No `incr_tea/*.mbti` or imported module
interface may change.

## Commands you will need

Run from `/home/antisatori/ghq/github.com/dowdiness/canopy/loom/incr` unless a
command explicitly changes directory.

| Purpose | Command | Expected on success |
|---|---|---|
| Package outline | `NEW_MOON_MOD=0 moon ide outline examples/typed_spreadsheet_incr_tea_demo` | exit 0; current symbols listed |
| API reuse | `NEW_MOON_MOD=0 moon ide doc '@examples/typed_spreadsheet.CellId'` | existing typed ID shown |
| Core ownership check | `NEW_MOON_MOD=0 moon ide peek-def 'ReadOnlyArray::from_array'` | implementation copies into owning storage |
| Core view shape | `NEW_MOON_MOD=0 moon ide doc 'ReadOnlyArray::view'` | returns `ArrayView[T]`, matching widened `draft_text_from` input |
| Package check | `NEW_MOON_MOD=0 moon check --target js examples/typed_spreadsheet_incr_tea_demo` | exit 0, no diagnostics |
| Package tests | `NEW_MOON_MOD=0 moon test --target js examples/typed_spreadsheet_incr_tea_demo` | exit 0, all pass |
| Framework tests | `NEW_MOON_MOD=0 moon test --target js incr_tea` | exit 0, all pass |
| Format | `NEW_MOON_MOD=0 moon fmt` | exit 0 |
| Interfaces | `NEW_MOON_MOD=0 moon info` | exit 0; generated interfaces refreshed |
| Workspace check | `NEW_MOON_MOD=0 moon check` | exit 0 |
| Workspace tests | `NEW_MOON_MOD=0 moon test` | exit 0, all pass |
| Boundaries | `bash scripts/check-workspace-boundaries.sh && bash scripts/check-engine-isolation.sh` | both exit 0 |
| Demo build | `cd examples/typed_spreadsheet_incr_tea_demo && npm run build` | exit 0 |
| Browser regression | `cd examples/typed_spreadsheet_incr_tea_demo && npm run test:dom` | exit 0, all checks pass |

Do not run `npm install` without operator approval if dependencies are missing.
Do not hand-edit generated `.mbti` files.

## Git workflow

- Suggested branch: `advisor/012-strong-sheet-command`.
- Match conventional commits, for example:
  `refactor(typed-spreadsheet): add strong command boundary`.
- Keep implementation and its tests in one logical commit unless the operator
  requests otherwise.
- Do not push, publish, deploy, create an issue, or open a PR without explicit
  operator instruction.

## Steps

### Step 0: Verify the baseline and reuse assumptions

Before editing, run:

```bash
NEW_MOON_MOD=0 moon ide outline examples/typed_spreadsheet_incr_tea_demo
NEW_MOON_MOD=0 moon ide doc '@examples/typed_spreadsheet.CellId'
NEW_MOON_MOD=0 moon ide doc 'ReadOnlyArray::*'
NEW_MOON_MOD=0 moon ide peek-def 'ReadOnlyArray::from_array'
NEW_MOON_MOD=0 moon ide doc 'ReadOnlyArray::view'
NEW_MOON_MOD=0 moon test --target js examples/typed_spreadsheet_incr_tea_demo
cd examples/typed_spreadsheet_incr_tea_demo && npm run test:dom
```

Expected:

- `CellId` remains `SheetId + address` with `Eq`, `Hash`, and `Debug`.
- `ReadOnlyArray::from_array` creates owning storage rather than an aliasing
  view.
- `ReadOnlyArray::view()` returns the exact `ArrayView[T]` shape accepted by the
  planned widened `draft_text_from`; otherwise stop before Step 1.
- all existing MoonBit and browser tests pass.

If baseline tests fail, stop; do not combine unrelated repairs with this plan.

### Step 1: Add command values, the owned planner, and pure validation

Create `sheet_command.mbt` and `sheet_command_wbtest.mbt` without changing any
current call site.

Implement package-local:

1. `DocumentGeneration`, with only `initial()` and `next()` operations plus
   equality/debug support. New-helper boundary: replacement-incarnation
   identity only; do not add clocks, serialization, or ordering against other
   time domains.
2. The variant-based `SheetCommand`, `UiEffect`, `SheetPlan`,
   `SheetPlanningContext`, `SheetExecutionContext`, and `CommandApplicability`
   with the target semantics above. Do not represent operation and local
   precondition as independent fields: invalid combinations must be
   unrepresentable.
3. `plan_sheet_command(context, msg) -> SheetPlan`, pure and exhaustive over all
   current `Msg` variants.
4. `validate_sheet_command(command, execution_context) ->
   CommandApplicability`, pure and exhaustive.

Planner requirements:

- `ApplySelected` resolves the selected typed `CellId` and captures its current
  draft as an owned `String` in `ApplyFromSelection`.
- `ApplyInlineEdit(address)` constructs a typed `CellId` from the context sheet,
  captures that address's draft, and produces `ApplyFromEditor`.
- `DeleteSelected` captures the selected typed `CellId` in
  `DeleteFromSelection`.
- `ResetSheet` produces `ResetDocument`, whose variant carries no local UI
  precondition.
- `BeginInlineEdit(address)` and `BeginSelectedInlineEdit` produce only
  `FocusInlineEditor`; the latter must use the selected address from the owned
  context.
- All other messages produce `{ command: None, ui_effect: None }`.
- AI publication is absent from `SheetPlan`.
- No planner code calls `peek`, touches a Worksheet/Runtime, or captures a
  callback.

Use the existing package-private `draft_text_from` by widening it in
`model.mbt` from `Array[CellDraft]` to `ArrayView[CellDraft]`. The planning
context calls it with `drafts.view()`. This is the only Step 1 edit outside the
new files and keeps all current callers source-compatible.

Pure tests must cover:

- every `Msg` variant;
- exact strong payload for selected and inline apply, including submitted text;
- changing the source drafts after creating the owned planning context does not
  change the planned command;
- exact selected-apply, editing-apply, selected-delete, and reset variants;
- operation/precondition mismatches are absent from the representable command
  space;
- selected-inline focus uses the selected address;
- applicable, stale-generation, and failed-local-precondition results;
- generation and precondition are independent checks;
- no AI-publication value exists in any plan.

**Verify**:

```bash
NEW_MOON_MOD=0 moon check --target js examples/typed_spreadsheet_incr_tea_demo
NEW_MOON_MOD=0 moon test --target js examples/typed_spreadsheet_incr_tea_demo
```

Expected: exit 0; existing behavior is unchanged because no production call site
uses the new planner yet.

### Step 2: Add generation and a directly testable current interpreter

Update `SheetState` with
`generation : DocumentGeneration`, initialized with
`DocumentGeneration::initial()`.

Keep it a plain immutable field inside the value stored by `Ref[SheetState]`,
not an `InputField`:

- generation is a shell admission guard;
- no current view or Derived reads it;
- reset replaces `state.val` and can install `generation.next()` atomically with
  the new Worksheet;
- adding a reactive cell would create lifecycle and invalidation work without a
  reactive consumer.

The current synchronous `Program::handle_message` path does not need generation
to prevent an actual race: it executes the returned command immediately. Keep
generation because `execute_sheet_command` is an intentionally supported
package-private shell boundary for future delayed commit, retry, and the first
application-specific EGW adapter. This plan therefore fixes document-replacement
incarnation semantics before that adapter exists; generation is not presented as
a current scheduler bug fix. If review rejects that future shell boundary, stop
and defer generation together with its stale-command tests rather than leaving a
partially used counter.

Add package-private shell snapshot helpers:

- `sheet_planning_context(state) -> SheetPlanningContext`, which creates a
  defensive `ReadOnlyArray::from_array(state.val.drafts.peek())` copy and typed
  selected/editing IDs;
- `sheet_execution_context(state) -> SheetExecutionContext`, which reads only
  selected/editing identity and generation.

Extract current mutation bodies into Unit-returning operations with explicit
payloads:

- apply owned text to a typed target;
- delete a typed target;
- reset and install the next generation.

Do not reread draft text inside apply execution. Reuse current parse,
`run_batched_op`, trace/evidence, status/error, and InputField update behavior.
When rendering user-facing messages, reuse `@demo.cell_id_to_string(target)`.

Add `execute_sheet_command(runtime, state, command) -> CommandApplicability`:

1. build the current execution context;
2. call pure `validate_sheet_command`;
3. return the non-applicable reason without mutation; or
4. execute the operation with its owned payload and return `Applicable`.

Add `interpret_sheet_command(runtime, state, plan) -> @tea.Cmd[Msg]`:

- a document command lowers to `Cmd::effect` calling
  `execute_sheet_command`;
- `FocusInlineEditor` lowers to existing `Cmd::focus_element_by_id`;
- command precedes UI effect if both are present;
- an empty plan returns `Cmd::none()`;
- it does not schedule AI publication.

At this intermediate step, keep all old `apply_*_cmd`, `delete_*_cmd`, and
`reset_sheet_cmd` helpers and their existing app callers. To keep generation
correct on both old and new paths, make the old reset helper delegate its
mutation body to the new reset operation; leave the other old helpers
behaviorally unchanged until Step 3.

Direct tests must cover semantics ordinary synchronous dispatch cannot
interleave:

- plan an apply command, change the source draft, execute directly, and verify
  the captured submitted text—not the latest draft—was applied;
- plan selected/inline/delete commands, change the corresponding local UI
  identity, execute directly, and verify `LocalPreconditionFailed` with no
  worksheet mutation;
- plan a command, execute reset to advance generation, then execute the old
  command and verify `StaleGeneration` with no mutation;
- reset advances generation exactly once and preserves current seed/status
  behavior;
- the normal current-generation command remains applicable.

**Verify**:

```bash
NEW_MOON_MOD=0 moon check --target js examples/typed_spreadsheet_incr_tea_demo
NEW_MOON_MOD=0 moon test --target js examples/typed_spreadsheet_incr_tea_demo
```

Expected: exit 0; old app behavior still runs through old helpers while new
strong semantics are pinned through the direct execution seam.

### Step 3: Atomically rewire the app and remove old opaque command helpers

Modify `handle_msg` without changing framework APIs:

1. inspect `msg` before immediate mutation;
2. create the owning `SheetPlanningContext` and its defensive draft copy **only**
   for `ApplySelected`, `ApplyInlineEdit`, `DeleteSelected`, `ResetSheet`,
   `BeginInlineEdit`, and `BeginSelectedInlineEdit`;
3. return an empty `SheetPlan` directly for all other messages, avoiding a draft
   copy on typing, selection, movement, example, and cancellation hot paths;
4. for the six planning messages, call pure
   `plan_sheet_command(sheet_planning_context(state), msg)` before immediate
   mutation;
5. execute the existing immediate local-state handler for the message;
6. replace old apply/delete/reset command calls with `Cmd::none()` because the
   strong command now owns that work;
7. for begin-inline messages, perform the existing selection/editing/status
   mutation but return no focus command; focus now comes from `UiEffect`;
8. lower the plan with `interpret_sheet_command`;
9. return
   `Cmd::batch([immediate_cmd, interpreted_cmd, publish_ai_context_cmd(state)])`.

Use this rewrite table as the source of truth:

| `Msg` | Planning input | Immediate mutation | Interpreted work |
|---|---|---|---|
| `SelectCell(cell)` | none; empty plan | existing selection/editing/status update | none |
| `UpdateDraft(cell, text)` | none; empty plan | existing selected-cell/draft update | none |
| `UseExample(text)` | none; empty plan | existing selected draft update | none |
| `ApplySelected` | full owned context before mutation | none / `Cmd::none()` | apply captured target and submitted text |
| `DeleteSelected` | full owned context before mutation | none / `Cmd::none()` | delete captured target |
| `ResetSheet` | full owned context before mutation | none / `Cmd::none()` | replace worksheet and advance generation |
| `CancelSelected` | none; empty plan | existing draft revert/editing clear | none |
| `BeginInlineEdit(cell)` | full owned context before mutation | existing selection/editing/status update, without focus command | post-flush focus from `UiEffect` |
| `BeginSelectedInlineEdit` | full owned context before mutation | call existing begin-inline state update for the pre-update selected cell, without focus command | post-flush focus for that same captured cell |
| `ApplyInlineEdit(cell)` | full owned context before mutation | none / `Cmd::none()` | apply captured target and submitted text |
| `MoveSelection(dx, dy)` | none; empty plan | existing guarded selection movement | none |

`publish_ai_context_cmd(state)` remains the final batch member for **every** row,
including rows with an empty plan.

This ordering preserves:

- planning from the submitted pre-update snapshot;
- immediate local state writes inside the current Runtime batch;
- document command execution after batch commit;
- focus after the inline editor is rendered;
- unconditional after-flush AI publication for every message, including draft,
  selection, and movement messages;
- message-specific command/UI work before AI publication.

After rewiring, run `moon ide find-references` or `rg` for every old direct
command helper. Only then remove:

- `apply_selected_cmd`;
- `apply_inline_edit_cmd`;
- `delete_selected_cmd`;
- `reset_sheet_cmd`.

Do not remove or move `publish_ai_context_cmd`.

**Verify**:

```bash
rg -n 'fn (apply_selected_cmd|apply_inline_edit_cmd|delete_selected_cmd|reset_sheet_cmd)' examples/typed_spreadsheet_incr_tea_demo
rg -n 'Cmd::effect' examples/typed_spreadsheet_incr_tea_demo --glob '*.mbt'
NEW_MOON_MOD=0 moon check --target js examples/typed_spreadsheet_incr_tea_demo
NEW_MOON_MOD=0 moon test --target js examples/typed_spreadsheet_incr_tea_demo
cd examples/typed_spreadsheet_incr_tea_demo && npm run test:dom
```

Expected:

- old helper definition search returns no matches;
- direct document `Cmd::effect` construction appears only in
  `sheet_command.mbt`;
- MoonBit and browser tests pass, including focus, reset, and AI-context checks.

### Step 4: Document the future adapter boundary

Update the demo README with an architecture section that states:

- `SheetCommand` is a strong, closure-free, self-contained application request;
- submitted text is fixed at message handling;
- local UI and generation preconditions are validated at execution;
- results are not replay-deterministic without authoritative document state;
- `UiEffect` and AI publication are not collaborative commands;
- current worksheet execution is a temporary imperative shell;
- a future application-specific adapter alone depends on EGW and incr;
- EGW remains authoritative for operation IDs, causal history, merge, and
  convergence;
- local commands and remote sync must share one merged-state projection path;
- application command IDs, future EGW operation IDs, incr revisions, and
  dataflow epochs are distinct;
- command types stay package-local during the pilot and must be promoted to an
  importable application-domain package when the adapter is commissioned;
- no generic `egw_incr` package is justified until a second driver repeats the
  same adapter contract;
- formula atomic-register versus sequence-text semantics remain an adapter ADR
  decision.

Document this conceptual future contract, but do not implement it:

```text
SheetCommand
  -> typed-spreadsheet/EGW adapter
  -> EGW transaction + commit receipt
  -> merged EGW document
  -> pure spreadsheet projection
  -> Runtime::batch
  -> InputFields
```

Decision record for eventual plan completion:

- **No ADR needed:** this is an application-local, unpublished pilot that
  preserves current `incr_tea`, incr, EGW, and dataflow public contracts. The
  first real adapter, formula CRDT policy, command promotion, or reusable EGW
  commit/report API requires its own ADR.

No `docs/README.md` update is needed because no indexed Markdown file is added,
moved, or removed.

**Verify**:

```bash
rg -n 'SheetCommand|submitted text|UiEffect|application-specific|EGW|Runtime::batch|replay|atomic register|sequence text' examples/typed_spreadsheet_incr_tea_demo/README.md
```

Expected: all boundary and non-goal concepts are present without claiming a
shipped adapter or deterministic outcome replay.

### Step 5: Run full validation and inspect interface drift

From the repository root, run in order:

```bash
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test
bash scripts/check-workspace-boundaries.sh
bash scripts/check-engine-isolation.sh
cd examples/typed_spreadsheet_incr_tea_demo && npm run build && npm run test:dom
```

Then inspect:

```bash
git diff --stat
git diff -- '*.mbti'
git status --short
rg -n 'Cmd::effect' examples/typed_spreadsheet_incr_tea_demo --glob '*.mbt'
```

Expected:

- all validation commands exit 0;
- `examples/typed_spreadsheet_incr_tea_demo/pkg.generated.mbti` changes only to
  record intended package-visible cross-file symbols;
- no `incr_tea/*.mbti`, `examples/typed_spreadsheet/*.mbti`, or imported module
  interface changes;
- only in-scope files and `plans/README.md` are modified;
- direct document `Cmd::effect` construction is confined to
  `sheet_command.mbt`;
- `publish_ai_context_cmd` remains the only direct demo-level
  `Cmd::after_flush` constructor and remains outside `SheetPlan`.

After validation, update Plan 012's row in `plans/README.md` to `DONE`. This
repository's active-plan workflow uses root `plans/` and later deletes completed
plan files during separately commissioned reconciliation; it is distinct from
the parent Loom `docs/plans/` archive workflow. Do not archive or delete this
file in the implementation change unless the operator separately commissions
reconciliation. When later retiring it, retain the explicit No-ADR disposition
and update the local plan index as required.

## Test plan

### Pure planner tests

In `sheet_command_wbtest.mbt`:

- every `Msg` maps to the exact optional command/UI effect;
- selected apply owns the selected typed target and submitted text;
- inline apply owns the message target and submitted text;
- delete owns the selected typed target;
- reset owns the admitted generation and its variant carries no local UI
  precondition;
- begin-inline and begin-selected-inline produce only focus effects;
- draft/source mutation after context creation cannot change planned payload;
- no plan contains AI publication or an executable capability.

### Pure applicability tests

- current generation + matching selected target => `Applicable`;
- current generation + matching editing target => `Applicable`;
- generation mismatch => `StaleGeneration` regardless of local identity;
- current generation + local identity mismatch =>
  `LocalPreconditionFailed`;
- reset variant with current generation => `Applicable`.

### Direct execution tests

- captured text wins over a later draft mutation;
- stale selected, editing, and generation commands return the structured
  non-applicable result and leave worksheet/model state unchanged;
- reset advances generation once, installs a fresh worksheet, and seeds A1/B1;
- a pre-reset command cannot mutate the replacement worksheet.

### Existing regressions

- package `model_wbtest.mbt` and `locality_wbtest.mbt` retain current update,
  reset, watched-root, and AI-context behavior;
- `npm run test:dom` retains real focus, edit, reset, and global AI publication;
- `moon test --target js incr_tea` retains framework scheduler behavior;
- workspace tests protect all members.

## Done criteria

All criteria are mandatory:

- [ ] `SheetCommand` variants contain only typed IDs, owned value payloads,
  generation, and variant-implied local preconditions—no independent
  operation/precondition fields, closures, or effectful capabilities.
- [ ] Mismatched operation/precondition pairs and duplicated precondition
  targets are unrepresentable.
- [ ] Apply commands store submitted text captured at message handling and never
  reread draft text during execution.
- [ ] `DocumentGeneration` advances on reset and rejects commands admitted
  against a replaced worksheet.
- [ ] `validate_sheet_command` is pure, exhaustive, and returns structured
  applicability.
- [ ] `UiEffect` contains focus only; AI publication remains a separate global
  shell policy.
- [ ] `interpret_sheet_command` is the only typed-spreadsheet location that
  constructs document-mutation `Cmd::effect` callbacks.
- [ ] `publish_ai_context_cmd` remains unconditional for every handled message
  and runs after command/UI interpretation.
- [ ] Existing `CellId`, parser, operation runner, `Cmd::batch`, and focus APIs
  are reused.
- [ ] No EGW type, replica/operation identity, causal version, incr `Revision`,
  dataflow `Epoch`, serializer, command ID, or generic Program effect parameter
  is introduced.
- [ ] No framework, typed-spreadsheet library, EGW, dataflow, parent Loom, or
  submodule source is modified.
- [ ] README documents authority, strong semantics, adapter placement,
  shared local/remote projection path, and deferred CRDT policy.
- [ ] Targeted MoonBit and browser tests pass.
- [ ] `moon fmt`, `moon info`, workspace `moon check`, workspace `moon test`,
  boundary checks, demo build, and browser regression all pass.
- [ ] `.mbti` diff contains only expected package-local symbols and no widened
  trait bounds.
- [ ] `git status --short` contains only in-scope files and
  `plans/README.md`.
- [ ] Plan 012 status is updated.

## STOP conditions

Stop and report; do not improvise if:

- A step cannot remain compilable without simultaneously changing a later step.
- A strong command needs to retain `Ref`, `Runtime`, `InputField`, `Worksheet`,
  DOM/JS handles, callbacks, borrowed views, or mutable arrays.
- The planner must read mutable state instead of receiving
  `SheetPlanningContext`.
- Apply execution must reread submitted text from drafts.
- Selection/editing/generation preconditions cannot be checked through the pure
  validator and current shell snapshot.
- Reset cannot atomically install the next generation with the replacement
  Worksheet.
- Preserving behavior requires modifying `incr_tea`, `incr`, typed-spreadsheet
  library/demo APIs, EGW, dataflow, or parent Loom source.
- An EGW `Version`, frontier, operation/replica ID, incr `Revision`, or dataflow
  `Epoch` appears necessary in the application command.
- A generic bridge or serializer appears necessary before one real adapter and
  a second driver exist.
- `moon info` changes an out-of-scope interface or widens a trait bound.
- A verification command fails twice after one reasonable correction.
- Documentation work requires adding/moving/deleting another Markdown file;
  revisit docs index and ADR disposition first.

## Maintenance notes

- Strong command payloads improve inspectability and future adaptation, but do
  not make execution outcomes deterministic. Formula dependencies and document
  state remain external inputs.
- Local UI preconditions are not CRDT causal preconditions. A future adapter
  must not reject all commands merely because the EGW version advanced; CRDT
  merge owns concurrent history.
- `DocumentGeneration` distinguishes replacement of the same logical sheet. It
  is not a wall clock, incr revision, EGW version, or globally replicated value.
  Its present consumer is the supported package-private
  `execute_sheet_command` boundary for direct tests and future delayed/adapted
  commit—not a race in today's synchronous Program scheduler. Reassess it when
  the real adapter defines document identity, but do not silently remove the
  incarnation check while delayed commands can cross reset.
- Command IDs and idempotent retry belong at future adapter admission. Do not
  identify them with EGW operation IDs; one command may produce many operations.
- EGW should eventually expose driver-backed transaction receipts/change
  reports if applications need them, but this plan must not speculate that API
  into the command model.
- When the adapter is commissioned, first decide whether formula source is an
  atomic register/property or sequence text. Do not let this local pilot choose
  CRDT semantics accidentally.
- The future adapter may initially live with the application. Extract generic
  `egw_incr` lifecycle only after another application repeats the same
  authoritative-state → projection → Runtime batch contract.
- ADR disposition: **No ADR needed** for this scoped unpublished pilot. The
  adapter, command-type promotion, formula CRDT policy, or reusable EGW API is
  ADR-worthy future work.
