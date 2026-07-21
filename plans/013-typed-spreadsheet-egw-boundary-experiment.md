# Plan 013: Typed Spreadsheet EGW Boundary Experiment

**Date:** 2026-07-20

**Status:** IN PROGRESS (single-user browser authority prototype works; collaboration transport remains a follow-up; Phase 4 performance A/B is blocked by its pre-adapter baseline)

**Decision record:** [ADR: Typed spreadsheet EGW register and projection boundary](../docs/decisions/2026-07-20-typed-spreadsheet-egw-register-projection.md)

**Reader:** Maintainers implementing the first typed-spreadsheet application-specific EGW boundary experiment.

**Decision:** Build an application-specific EGW adapter inside the existing `typed_spreadsheet_incr_tea_demo` module that demonstrates collaborative editing through LWW register projection, preserving authority boundaries between EGW, application, and `incr`.

**Keep until:** The experiment completes or is superseded by a different integration approach.

**Disposition:** Delete after the experiment concludes and update the linked ADR with the accepted or rejected result. Git history is the recovery path for this time-bounded plan.

## Context

Plan 012 shipped in [PR #421](https://github.com/dowdiness/incr/pull/421), merged as commit `d512b63`. It established package-local parse-don't-validate `SheetCommand` variants with typed `CellId` and `DocumentGeneration`, focus-only `UiEffect`, and unconditional AI publication. The reconciliation noted: "The future application-specific EGW adapter and formula policy remain separate; issue [dowdiness/event-graph-walker#72](https://github.com/dowdiness/event-graph-walker/issues/72) remains driver-gated; no generic `egw_incr` bridge."

The typed spreadsheet demonstration (PR #408, closed issue #268) proved that `incr` can serve as the reactive foundation for a collaborative spreadsheet-shaped application. The next boundary question is: how does an application integrate with EGW for multi-user synchronization without violating the separation between `incr` (reactive computation), EGW (CRDT operations and convergence), and application logic (commands, document identity, UI)?

This plan is the first typed-spreadsheet application-specific EGW boundary experiment. The ADR is Accepted, and Phase 0 verified that the standalone `incr` workspace resolves the published EGW 0.4.0 package. Phase 1 domain package promotion, Phase 2 pure adapter core, and Phase 3 mutable adapter shell passed 2026-07-20. Phase 4 began 2026-07-21: release JS microbench evidence is reproducible, but the pre-adapter browser baseline missed advisory budgets and blocks a valid browser A/B conclusion on this host.

## STOP conditions

**Step 0 must STOP unless:**

1. The linked register/projection ADR has been reviewed and marked `Accepted`.
2. The standalone `incr` workspace (not parent Canopy) resolves `dowdiness/event-graph-walker` version 0.4.0 or later in `moon.mod` dependencies.
3. The verified EGW container APIs match the assumptions in this plan: `Document::new`, `root_id`, `create_node`, `is_alive`, `set_property`/`get_property`, `sync`/`export_all`/`export_since`/`apply`, `Version`, `SyncReport` count accessors.
4. The current standalone `incr` workspace does NOT silently implement against 0.3.0 or parent workspace override.

**Current state:** Phase 0 dependency/API verification is committed at `15b9be4`, Phase 1 domain package promotion at `9176b67`, Phase 2 pure adapter core at `a41126d`, Phase 3 mutable adapter shell at `93314b4`, and Phase 4 benchmark/API-quality evidence at `50c948d`. The Phase 4 performance route remains blocked because two unchanged pre-adapter browser runs missed advisory budgets; production remote projection remains FullScan. After the user authorized productization, the current working-tree prototype made the adapter the executable browser's single-user committed authority while preserving trace/evidence, reset, drafts, AI context, and DOM behavior. Remote transport, room/join lifecycle, and presence are not implemented. Phase 5 reconciliation is partial, and a collaboration follow-up plan should be shaped after prototype feedback rather than folded into the original bounded experiment.

**Do not proceed if:** EGW resolves to 0.3.0, or if the container APIs have changed in incompatible ways.

## Decision

### 1. Package structure inside existing demo module

Promote `SheetCommand`, opaque `DocumentGeneration`, `CommandApplicability`, `SheetExecutionContext`, and the pure `validate_sheet_command` function to ONE importable app-domain package inside the existing `typed_spreadsheet_incr_tea_demo` module. Move, never copy or embed. `SheetPlan`, `SheetPlanningContext`, `plan_sheet_command`, `sheet_execution_context`, `execute_sheet_command`, `Msg`, and `UiEffect` remain demo-local.

Proposed package layout inside `examples/typed_spreadsheet_incr_tea_demo`:

```text
domain/
  moon.pkg
  command.mbt
  # Command/admission types, pure validation, and opaque application identity

egw_adapter/core/
  moon.pkg
  register.mbt
  projection.mbt
  # Pure codec, snapshot diff, reconciliation, decisions, diagnostics

egw_adapter/
  moon.pkg
  adapter.mbt
  # Application-specific mutable EGW and projection shell
```

Every directory is a MoonBit package with an explicit `moon.pkg`. The domain package imports only typed spreadsheet identity. The core package imports domain/core value dependencies but not EGW, `incr_tea`, DOM, or the executable package. The shell imports EGW container, domain, core, typed spreadsheet, typed-spreadsheet demo parsing, and `incr` as required. Package imports must not form a cycle.

**Step 0 verification:** Before creating files, run `moon ide outline` and `moon ide doc` on the existing module, inspect nearby multi-package modules, and validate each proposed package root/import direction. Stop rather than moving the adapter to the parent Canopy repo if feasibility is unclear.

### 2. Committed cell source as tagged atomic LWW register

One tagged atomic LWW register property per cell address on one synchronized worksheet node. Property keys and payloads are fixed for this experiment:

```text
property key = "cell/" + canonical grid address

Source(text) = {"v":1,"kind":"source","text":"..."}
Deleted      = {"v":1,"kind":"deleted"}
```

The encoder uses MoonBit `Json` and compact stringification; it does not concatenate or escape JSON manually. The decoder accepts object fields in any JSON order but requires the exact field set for the selected tag, integer version `1`, and string values of the documented types. Extra or missing fields, duplicate semantic fields, unknown versions/tags, and non-object JSON are diagnostics. A missing EGW property is `Unset`, not an encoded register and not a decode error. `Unset` and `Deleted` both project to an absent Worksheet cell, but remain distinct raw observations.

Only addresses from the canonical 50×50 `grid_cells()` order are read or written. Property suffixes supplied by messages are never trusted as arbitrary keys; typed `CellId` is converted to an address and checked against the known grid before mutation.

- No torn multi-property state (text + deleted as separate properties).
- No empty-string ambiguity (`Source("")` is representable even though current local admission rejects it; `Deleted` is a distinct tag).
- Formula text is whole-submit, not sequence CRDT.
- Invalid or malformed remote register/source produces deterministic diagnostics and retains local last-good semantic `Worksheet` state.

**Do not use** EGW text sequence APIs. Do not invent a multi-property encoding.

### 3. Authority boundaries

**EGW** owns: operations, replica identity, causal history, merge semantics, convergence.

**Application** owns: `SheetCommand` variants, logical collaborative document identity, reset/replacement, schema, projection, local UI state (selection, editing focus, draft text).

**`incr`** owns: `Runtime`, `Revision`, dependency tracking, cell cache semantics.

**Keep distinct:**

- `DocumentGeneration`: local admission guard across document replacement.
- Logical document identity: application-level concept of "which collaborative document."
- EGW `Version`/op IDs: CRDT operation identity and causal history.
- `incr` `Revision`: invalidation and verification metadata.
- Dataflow `Epoch`: temporal progress (future concern, not this plan).

Do not conflate these. Do not use EGW `Version` as `DocumentGeneration`. Do not use `incr` `Revision` as operation identity.

### 4. Bootstrap and reset

**Bootstrap:** One authoritative initializer creates the worksheet node, writes the seed A1/B1 registers to EGW, and derives the initial `Worksheet` only through the shared projection path before peers edit. Peers receive logical app document identity plus the synced node/bootstrap. Do not retain the existing direct-Worksheet seeding path, rely on property/node discovery, or permit concurrent duplicate roots.

**ResetDocument:** Application logical-document replacement:

- Fresh logical identity.
- Fresh EGW `Document`/node.
- Seed registers written to the fresh EGW document before projection.
- Fresh `Worksheet` derived through the shared projection path.
- `DocumentGeneration` advance.

Existing-doc clearing and cross-peer routing/transport are out of scope. Caller supplies identity allocation; no clock/random/serializer invented in the command.

### 5. Shared projection path

Both local command execution and remote `SyncMessage` MUST:

1. Mutate authoritative EGW first.
2. Call the exact same shared projection path.

The projection path keeps three states distinct:

- `last_seen_register_snapshot`: the last authoritative raw register snapshot successfully processed by the application shell;
- `last_good_semantic_projection`: the per-cell semantic sources/results currently installed in `Worksheet`;
- current projection diagnostics for malformed, unsupported, or semantically invalid registers.

The shell scans owned property strings for known bounded 50×50 addresses because EGW lacks property enumeration or a changed-entity report. The pure core decodes the new raw snapshot and reduces the three prior states into candidate next states plus immutable Worksheet/UI decisions. One `Runtime::batch` applies only those decisions. The adapter commits candidate retained states only after that batch succeeds. If application fails, retained states stay unchanged, EGW remains authoritative and ahead, and the next projection attempt rereads the same EGW state and retries.

**Draft reconciliation:**

- Clean drafts follow committed changes.
- Dirty drafts remain (user is actively editing).
- Selection and editing state unchanged by projection.

**AI publication:** Remains unconditional global post-flush.

### 6. Functional core constraints

The functional core MUST NOT read mutable EGW `Document`. The shell creates an owned property snapshot (immutable copy), then pure decode/diff/reconcile returns immutable decisions and diagnostics.

**Do not expose mutable arrays from the core.** Use `ReadOnlyArray` or owned immutable values.

### 7. Core result and shell result shapes

Preserve these semantic shapes. Exact MoonBit syntax may change only to satisfy the compiler without weakening ownership or state separation:

```text
CollaborativeSheetId(String) // opaque; caller supplied

RegisterObservation
  Unset
  Decoded(CellRegister)
  Invalid(ProjectionDiagnostic)

CellProjectionState {
  address
  last_seen_register
  last_good_source?
  diagnostic?
}

ProjectionState(ReadOnlyArray[CellProjectionState])

ProjectionDecision
  ApplyWorksheet(SheetOp)
  SetCommitted(address, source?)
  SetDraft(address, source?)
  SetDiagnostic(address, diagnostic?)

ProjectionTransition {
  candidate_state: ProjectionState
  decisions: ReadOnlyArray[ProjectionDecision]
  diagnostics: ReadOnlyArray[ProjectionDiagnostic]
}

AdapterApplyResult
  Rejected(CommandApplicability)
  SourceRejected(FormulaTextParseError)
  MutationNotLanded
  ProjectionFailed(ProjectionApplyError)
  NoSemanticChange(ProjectionReport)
  Applied(ProjectionReport)
```

`ProjectionDiagnostic` is deterministic application data, not an exception string captured from EGW or the DOM. `ProjectionReport` contains application projection counts/timing inputs only; it is not an EGW receipt and carries no operation ID. The shell may pair a remote adapter result with the existing EGW `SyncReport`, but does not merge their identity domains.

All source parsing and construction of Worksheet `SheetOp` decisions completes before entering `Runtime::batch`. The batch executes only a prepared frame. Unexpected Worksheet results raise `ProjectionApplyError`, rolling back the frame. `ProjectionTransition.candidate_state` becomes retained state only after the prepared frame succeeds.

### 8. Runtime projection applicator

Runtime projection must call `Worksheet::set_input`, `Worksheet::set_formula_ast`, and `Worksheet::delete` directly, or introduce a new app-local unbatched applicator with explicit responsibility.

**NEVER call `@demo.run_batched_op` inside an outer `Runtime::batch`.** Existing `run_batched_op` is reused only for the current pre-adapter path (single-user demo) or checked as unsuitable for bulk projection.

**Parsing:** Reuse `@demo.parse_cell_text_op`, then match public `SheetOp` in the app-specific projection shell. The mutable EGW property scan and Worksheet application are imperative; register decoding, diffing, draft reconciliation, and projection decisions remain pure.

### 9. EGW API usage and evidence gaps

**Use:**

- `Document::new`, `root_id`, `create_node`, `is_alive`.
- `set_property`/`get_property` for LWW register.
- `sync`/`export_all`/`export_since`/`apply` for synchronization.
- `Version`, `SyncReport` count accessors.

**Evidence gaps (record but do not change EGW):**

- `set_property` returns `Unit` with silent no-op paths. Preflight with `is_alive`, then read the property back and compare it with the desired encoded register. An already-equal register is success; a different read-back is `MutationNotLanded`. EGW `Version` changes may be recorded as evidence but are not substituted for value confirmation.
- `SyncReport` provides only operation counts, no changed-entity report. This forces the 50×50 scan.
- `Document::transaction` is undo grouping only, NOT atomic commit. Do not use or name it as commit.

**Do not use:**

- EGW text sequence APIs.
- `CausalSnapshot`.
- Dataflow APIs (future concern).
- `HashMap` unless evidence requires it (prefer `ReadOnlyArray` for projection state).

### 10. No generic abstractions

**No generic `egw_incr` bridge.** This is an application-specific adapter.

**No EGW source or API changes.** Record evidence gaps but do not modify EGW in this plan.

**No command IDs, dedup, network, transport, or dataflow.** Out of scope.

### 11. EGW improvement experiment

This adapter is also an EGW improvement experiment. Include:

**Evidence ledger:**

- `get_property` read counts.
- Scan/decode/diff/projection/end-to-end latency for 1/10/100/2500 changed cells.
- Release mode, existing browser/interaction budget.
- Do not optimize before measurement.

**Private A/B projection-hint seam:**

- `FullScan` (baseline, no hints).
- `ChangedProperties` (if EGW later provides changed-entity report).
- Private to the adapter, no public generic abstraction.

**EGW candidate improvement requires:**

1. Current adapter works correctly.
2. Reproducible correctness or performance limitation.
3. Application-independent shape (not spreadsheet-specific).
4. Second driver (Loom) confirmation.
5. Same convergence suite.
6. Quantified gain.

**No GitHub issue comment or EGW change without separate approval.** Mention related EGW issue #72 but research updates require separate authorization.

## Implementation phases

### Phase 0: Dependency and API verification

**Verification record (2026-07-20): PASS.**

- **Safety and starting state:** Branch `advisor/013-egw-boundary-experiment` was at HEAD `86a61a8`, with parent checkpoint `48aa16e` and no upstream. The superproject was `/home/antisatori/ghq/github.com/dowdiness/canopy/loom`; the standalone workspace root was `/home/antisatori/ghq/github.com/dowdiness/canopy/loom/incr`.
- **Resolution and provenance:** Before refresh, the standalone cache had no EGW. The stale sibling cache at `../.mooncakes/dowdiness/event-graph-walker/moon.mod` was 0.3.0; the parent-local `../../event-graph-walker/moon.mod` was 0.4.0 but was not used as evidence. Exact dependency `dowdiness/event-graph-walker@0.4.0` resolved into the distinct, non-symlink standalone `.mooncakes/dowdiness/event-graph-walker` directory. `moon ide doc @container` reported `dowdiness/event-graph-walker@0.4.0`; `outline` and `peek-def` resolved definitions only from its standalone `container/` source.
- **Container API:** Verified `Document::new`, `root_id`, `create_node(parent~)`, `is_alive`, `set_property`/`get_property`, `sync`, `SyncSession::export_all`/`export_since`/`apply`, opaque `Version`, and all four `SyncReport` count accessors. `set_property` retains silent early-return behavior. `Document::transaction` groups undo history and does not roll back mutations already landed.
- **Existing API First:** Confirmed reuse candidates `parse_cell_text_op`, direct `Worksheet::set_input`/`set_formula_ast`/`delete`, and `Runtime::batch`; `run_batched_op` remains unsuitable inside an outer batch. Checked core candidates `Json::object`/`stringify`, `Map::get_from_string`, `ReadOnlyArray::from_array`/`map`, `String::strip_prefix`, `StringView::to_owned`, `Result::map`, and `Option::map`. No helper or implementation code was added.
- **Package feasibility:** Nested `domain/`, `egw_adapter/core/`, and `egw_adapter/` are valid package roots under the existing demo module, consistent with nearby nested packages such as `typed_spreadsheet_rabbita_demo/data`. The domain package owns the pure command-admission vocabulary and validator required by both the executable root and future shell. The root executable may import the shell; the shell may import EGW, `incr`, typed-spreadsheet demo/Worksheet APIs, the pure core, and domain; the pure core/domain packages never import the shell, executable root, or DOM. This direction has no cycle.
- **Baseline behavior:** Before and after adding the dependency, the targeted JS check completed with 0 errors and the same 16 pre-existing warning 0020 diagnostics; targeted tests passed 27/27 both times. A temporary root-package container import compiled but added two unused-package warnings, so it was removed under the "only where needed" rule. The production import belongs in the Phase 3 shell package.
- **Scope and parent safety:** The final Phase 0 diff retains only the exact demo-module dependency and documentation. Parent status remained the pre-existing `M event-graph-walker` and `m loom`; no parent workspace or submodule pointer was edited or staged. No Phase 1 scaffolding was created.

Before editing, record the current branch, superproject path, standalone workspace root, current absence of an EGW demo dependency, and any stale cached EGW package location/version. Do not infer standalone 0.4.0 resolution from the user's release report or the parent workspace.

With the ADR Accepted and EGW 0.4.0 publication reported:

1. Add exactly `dowdiness/event-graph-walker@0.4.0` to the demo module manifest and the container package import only where needed.
2. Refresh dependencies from the understood standalone `incr` workspace root, then immediately re-check the branch and superproject state. Do not run dependency update through the parent Canopy workspace.
3. Use `moon ide doc`, `outline`, and `peek-def` to verify the resolved version and source location plus every assumed container API.
4. Run standalone targeted check/tests before adding adapter packages.
5. Use `moon ide outline` on the demo module and inspect its manifests to confirm that `domain/`, `egw_adapter/core/`, and `egw_adapter/` are valid package roots. Stop rather than moving the adapter to the parent repository.

**STOP unless:** the ADR is Accepted, the standalone workspace resolves published EGW 0.4.0, the resolved definitions do not come from the parent workspace override, all assumed APIs match, and baseline tests pass.

**DONE when:** dependency resolution, API shape, package feasibility, branch state, and baseline behavior are recorded and verified.

### Phase 1: Domain package promotion

Move `SheetCommand`, `DocumentGeneration`, `CommandApplicability`, `SheetExecutionContext`, and `validate_sheet_command` from `sheet_command.mbt` into `domain/command.mbt`. `SheetCommand` and `CommandApplicability` expose their variants for cross-package construction and matching. `DocumentGeneration` remains an opaque `pub struct` with only public `initial()` and `next()` operations; do not expose its tuple constructor or representation. `SheetExecutionContext` is constructed through a public `SheetExecutionContext::SheetExecutionContext(...)` named constructor so its fields need not be externally constructible. Update the demo-local `sheet_execution_context` helper to use that constructor. Keep `SheetPlan`, `SheetPlanningContext`, `plan_sheet_command`, `sheet_execution_context`, `execute_sheet_command`, `Msg`, and `UiEffect` demo-local. Move validation-specific tests to the domain package; keep planner/interpreter tests in the executable package.

**Verification:** Use `moon ide doc`/`peek-def` to confirm the domain package exposes the command variants, applicability variants, generation operations, execution-context constructor, and validator without exposing generation representation. Run `moon check`, `moon test`, `moon fmt`, `moon info`, and review `.mbti` diff for unintended trait bound changes.

**DONE when:** The domain package is importable, a consumer package can construct `SheetExecutionContext` and call `validate_sheet_command`, the future shell can return `Rejected(CommandApplicability)` without importing the executable root, all existing tests pass, and there is no unintended API regression.

**Completion record (2026-07-20): PASS.**

- **Package boundary:** New package `examples/typed_spreadsheet_incr_tea_demo/domain` imports only `examples/typed_spreadsheet` and supports JS. The root package imports domain with package-local `using`; planning, UI, and interpreter helpers remain root-local.
- **Domain API:** The package is the single source of truth for opaque `DocumentGeneration` (`initial`/`next`, no public constructor), public `SheetCommand`, public `CommandApplicability`, `SheetExecutionContext` with a `Type::Type` constructor, and pure public `validate_sheet_command` preserving stale-generation precedence.
- **Interfaces and tests:** Root public API remains only `mount_typed_spreadsheet_incr_tea_demo`; moved private type entries left the root `.mbti` as intended. Domain `.mbti` exposes only the intended surface. The validation-specific test moved to a domain black-box test; root tests passed 26/26 and the domain test passed 1/1.
- **Validation:** `moon fmt`, `moon info`, `.mbti` review, `moon check`, `moon test` (1116 wasm-gc and 180 JS tests), workspace/engine boundary scripts, and diff check passed. Independent `moonbit-reviewer` review passed with no findings.
- **Scope:** Phase 2 (`egw_adapter`) was not created.

### Phase 2: EGW adapter core (pure)

Implement `egw_adapter/core/`:

- A strict versioned JSON register codec with `Source(text)` and `Deleted`; use MoonBit `Json` rather than hand-written escaping.
- An owned, address-ordered raw register snapshot supplied by the shell. The core must not call EGW.
- Separate immutable `last_seen_register_snapshot`, `last_good_semantic_projection`, and diagnostics state.
- A deterministic reducer from prior projection state plus a new raw snapshot to candidate next state and immutable application decisions.
- Pure committed/draft reconciliation and projection diagnostics.
- An opaque application logical document identity supplied by the caller; do not reuse `SheetId`, `DocumentGeneration`, EGW `Version`, or replica identity.

**Test ownership:** White-box codec/diff/reconciliation tests live beside the core as `*_wbtest.mbt`. Shell ownership/bootstrap tests live beside `egw_adapter/`. End-to-end Program, UI-state, browser, and two-peer application-flow tests remain in the executable demo package. No package retests imported EGW or typed-spreadsheet behavior beyond their public contracts.

**Pure tests:**

- Register round-trip, malformed payload, unknown version/tag, missing and extra field cases.
- Address-order-independent decode into canonical grid order.
- Snapshot transitions for source, deletion, unchanged, malformed, repeated-malformed, and malformed-to-valid recovery.
- Clean-draft follow and dirty-draft retention.
- Separation of last-seen raw state, last-good semantics, and deterministic diagnostics.
- Failed-shell retry: an uncommitted candidate transition can be recomputed from unchanged retained state.

**Property-based generators:** Must crash on invalid promised inputs, not skip.

**DONE when:** all pure core tests pass without a mutable EGW `Document`, `Runtime`, `Worksheet`, `InputField`, callback, or mutable collection in retained results.

**Completion record (2026-07-20): PASS.**

- **Package boundary:** Added only `egw_adapter/core/`. It directly imports typed-spreadsheet values, the pure demo parser/`SheetOp` vocabulary, and core JSON; it does not directly import EGW, `incr`, `incr_tea`, DOM, or the executable root.
- **Codec:** Added compact version-1 `Source`/`Deleted` JSON encoding, exact-field decoding, deterministic diagnostics, and a bounded top-level member scanner required because core JSON maps overwrite duplicate keys.
- **Functional core:** Added caller-owned collaborative identity, canonical immutable raw snapshots and projection state, separate last-seen/last-good/diagnostic state, ordered immutable decisions, clean/dirty draft reconciliation, and deterministic retry from unchanged retained state. Ephemeral local maps/arrays only build immutable `ReadOnlyArray` results.
- **Tests and review:** Eighteen white-box tests cover codec/schema failures, duplicate scanning, canonical deduplication/order, source/formula/deleted/unset transitions, unchanged and malformed repetition, recovery, draft policy, diagnostics order, and retry purity. Final independent `moonbit-reviewer` review passed with no findings.
- **Validation and scope:** `moon fmt`, `moon info`, interface review, `moon check`, `moon test` (1116 wasm-gc and 198 JS tests), workspace/engine boundary scripts, and diff check passed. Phase 3 shell was not created.

### Phase 3: EGW adapter shell (mutable boundary)

Implement `egw_adapter/adapter.mbt`:

- Bootstrap/reset write seed registers to a fresh authoritative EGW document, then derive `Worksheet` through the shared projection path.
- Local command execution receives an owned `SheetExecutionContext`, calls the domain `validate_sheet_command` function before any EGW mutation, parses an applicable command, writes the desired register, verifies read-back, then calls the shared projection path.
- Remote sync applies `SyncMessage` to EGW, then calls the same projection path.
- Projection scans 50×50 addresses, invokes the pure transition reducer, and applies one candidate frame in `Runtime::batch`.
- Unexpected Worksheet boundary results become a catchable application projection error so the outer batch rolls back; returning an error value must not leave a partially accepted frame.
- Retained raw/semantic/diagnostic state advances only after successful batch completion. EGW is not rolled back when projection fails; retry starts from unchanged retained application state.
- Draft reconciliation keeps clean drafts aligned and dirty drafts local.
- Return a structured application result that distinguishes local precondition rejection, parse rejection, `MutationNotLanded`, projection failure, no semantic change, and applied projection. Do not identify this result with an EGW operation receipt.

**DO NOT:**

- Call `run_batched_op` inside an outer `Runtime::batch`.
- Read mutable EGW `Document` from functional core.
- Expose mutable arrays from core.
- Use `Document::transaction` as commit.

**Integration tests:**

- Invalid local source is rejected before EGW mutation, preserving current behavior.
- Missing/dead worksheet node and mismatched read-back return structured failure without advancing retained projection state.
- Unexpected Worksheet failure rolls back all frame-local Worksheet/InputField writes, leaves retained application state unchanged, and succeeds on retry after the fault is removed.
- Bootstrap and reset seed EGW first; no direct Worksheet seed path remains.
- Local command and equivalent remote sync produce identical projection decisions.
- Two peers converge after concurrent same-cell source updates.
- Apply/delete races converge.
- Duplicate, out-of-order, and pending sync preserve deterministic projection.
- Clean drafts follow and dirty drafts survive remote changes.
- Malformed remote application payloads produce matching diagnostics and retain each peer's local last-good Worksheet; no computed-state convergence is claimed until a valid register replaces the invalid value.
- After valid recovery from a malformed register, peers reconverge in projection and computed Worksheet results.
- Reset advances generation and rejects pre-reset commands; cross-peer replacement routing remains out of scope.
- Peers converge in EGW document state, decoded projection, and computed Worksheet results.

**Verification:**

- `moon check`, `moon test` in standalone `incr`.
- Targeted JS demo build and test.
- `incr_tea` tests.
- Full validation: `moon fmt` → `moon info` → `.mbti` review → `moon check` → `moon test` → boundary scripts → `npm build` → `npm test:dom`.
- EGW dependency package tests are trusted by public contract; two-peer adapter tests belong here.
- Verify from parent Canopy only as downstream integration after standalone passes, without editing parent/submodule pointers.

**DONE when:** both authority paths call one projection function and all convergence/application-state tests pass.

**Completion record (2026-07-20): PASS.**

- **Package and ownership:** Added pure canonical `domain/grid.mbt` (identical root helpers, no behavior change) and app-specific `egw_adapter/` shell importing exact published EGW 0.4 container, `incr`, typed-spreadsheet/demo, domain, and child core. No generic bridge, root, DOM, tea, transport, dataflow, or EGW API change. Opaque `EgwAdapter` hides mutable `Document`/`Worksheet`/state. Public façade exposes bootstrap/attach, local apply, remote apply, export/version, immutable projection state, and read_cell/inspect_cell. `ProjectionBindings` are explicit draft/UI `InputField` capabilities; no mutable `Document`/`Worksheet` is exposed.
- **Authority ordering:** All bootstrap/local/remote/reset authority paths perform EGW authority work first, then invoke one shared full-scan projection path. Local order: adapter generation guard + domain validation + sheet ownership + parse + liveness + set/readback + project. Remote: `SyncSession.apply` then the same project path. Reset uses lazy caller authority, seeds/reads-back/projects a fresh `Worksheet`, and swaps/advances/disposes only after success.
- **Batch and errors:** One outer `Runtime::batch` applies prepared direct `Worksheet` operations and UI binding writes. A private typed wrapper rolls back on failure; retained `ProjectionState` commits only after success. No `run_batched_op` nesting or `Document::transaction`. Structured results preserve `CommandApplicability`, parse rejection, `MutationNotLanded`, typed projection errors, and no-change/applied reports; remote `SyncReport` remains separate.
- **Tests and review:** 15 adapter white-box integration tests cover bootstrap computed 10/11, stale/foreign/invalid no-mutation, dead/readback mismatch, no-op readback, real later `Worksheet` failure rollback+retry, lazy successful/failed reset and old-context stale rejection, local/remote decision parity, concurrent writes, apply/delete race, duplicate/out-of-order/pending, clean/dirty drafts, malformed+unknown payload with differing last-good states, recovery, and separate EGW/projection/`Worksheet` convergence. An independent `moonbit-reviewer` initially found a generation bypass and a mutable `Worksheet` getter; both were fixed. Final re-review PASS, no findings.
- **Validation and scope:** `moon fmt` check, `moon info`/interface review, targeted root JS 26/26, domain 1/1, core 18/18, adapter 15/15; full default 1116 wasm-gc +213 JS, explicit workspace target JS total 1329; `moon check` 16 existing warnings/0 errors; boundary scripts/docs check; `npm build`; 8 DOM scenarios. Generated `.mbti` canonical trailing blank is tool output. Parent files/pointers untouched; no push. The executable root remains the pre-adapter baseline and is not wired to the shell in this phase; the adapter is exercised by package-owned integration tests. At this Phase 3 checkpoint, Phase 4 metrics/evidence was unstarted; the current Phase 4 status is recorded below.

### Phase 4: Evidence ledger and metrics

Add a package-owned MoonBit benchmark file following the existing `@bench.T` pattern and retain the existing browser benchmark harness for interaction-level evidence. Prime projection state before warm measurements and keep measured results alive with the benchmark API.

Record baseline metrics:

- `get_property` read counts for 1/10/100/2500 changed cells.
- Scan/decode/diff/projection/end-to-end latency.
- Release mode, existing browser/interaction budget.

Keep a private A/B projection-hint seam (`FullScan` vs `ChangedProperties`). Production remote sync uses `FullScan`; a benchmark-only synthetic changed-property hint measures the maximum avoidable scan work without claiming that EGW already supplies it.

Write a new dated snapshot under `docs/performance/` and add it to `docs/performance/README.md` and `docs/README.md`. Record toolchain, EGW version, sample/warmup counts, raw summary statistics, existing interaction budget, and an evidence ledger classifying every pressure point as adapter-local, EGW candidate, or deferred pending a second driver.

Pre-register the performance decision rule:

1. Run the existing browser scenarios without the adapter on the same host/toolchain. If that baseline already misses its advisory p95 budget, record the environment as unsuitable and make no EGW performance conclusion.
2. Run the adapter-enabled full-scan path in at least two independent benchmark runs. A microbenchmark speedup or O(N) shape alone is not material.
3. Performance pressure may advance to an EGW candidate only when the pre-adapter baseline meets budget, the full-scan adapter causes the same relevant scenario to miss budget in both runs, and the benchmark-only synthetic `ChangedProperties` path restores that scenario within budget in both runs.
4. Even then, the candidate remains deferred until Loom or another second driver confirms the same application-independent reporting need and the convergence suite is unchanged.
5. If the adapter stays within budget, classify changed-property reporting as deferred regardless of the isolated scan speedup.

Correctness or mutation-observability pressure follows the separate six-part EGW candidate gate above and cannot be justified by performance measurements alone.

**Do not optimize before measurement.** Do not treat an O(N) shape or a faster synthetic path as evidence of material product impact without the measured end-to-end result.

**Measurement checkpoint (2026-07-21): BLOCKED by browser baseline.**

- Added package-owned JS release benchmarks and a private benchmark-only `FullScan`/`ChangedProperties` seam sharing the production address scanner. A normal test pins 2,500 versus N property reads and equal semantic decisions; the partial synthetic candidate state is never retained.
- Two independent runs cover scan, decode, decode/diff, prepared projection, and end-to-end authority-write/projection cost for 1/10/100/2,500 changed cells. One-cell end-to-end FullScan measured 2.04/1.97 ms versus 0.452/0.422 ms for the synthetic lower bound; at 2,500 cells the advantage disappears.
- The unchanged pre-adapter browser baseline failed selection in run 1 and formula-bar draft plus visible edit in run 2. Per rule 1, this host is unsuitable and no adapter-enabled browser A/B or EGW performance conclusion is authorized.
- The dated evidence snapshot classifies sparse property reporting as deferred, the full-prior-state reducer floor and dense projection as adapter/application-local, mutation observability under the separate correctness gate, and browser variance as a measurement-environment blocker.
- **Separate API-quality checkpoint (2026-07-21): RECORDED.** Browser variance blocks only the performance route. The [API-quality evidence note](../docs/research/2026-07-21-typed-spreadsheet-egw-api-quality-evidence.md) evaluates correctness, misuse resistance, convenience, and generality separately. EGW 0.4 is sufficient for the tested adapter but cumbersome: `set_property` exposes no failure channel, and `SyncReport` exposes counts rather than post-apply impact. Error-transparent property mutation is concrete candidate pressure; a conservative impact report remains a research candidate. Rich semantic receipts are not advanced. Both candidates remain gated by a second container driver, compatibility, convergence, and quantified gain.
- Production local/remote paths remain FullScan. No EGW API, generic bridge, transport, browser wiring, optimization, or issue comment was added. Phase 5 reader-document reconciliation is partial; final boundary review and Plan disposition remain blocked.

**Unblock when:** the unchanged browser baseline meets every advisory p95 budget on the same stable host/toolchain. Then run adapter-enabled FullScan and benchmark-only ChangedProperties composition twice before applying the remaining decision rules.

**DONE when:** the release-mode baseline and synthetic comparison are reproducible, indexed, and classified without proposing or publishing an EGW API.

### Phase 5: Documentation and boundary review

**Checkpoint (2026-07-21): PARTIAL.** The ADR, demo README, Plan index, and
evidence indexes distinguish the blocked performance route from bounded
API-quality evidence. A later user-authorized prototype now routes executable
browser commits through `EgwAdapter` while retaining local UI state and observed
trace/evidence. Final boundary review and Plan disposition remain open; remote
collaboration belongs in a separately shaped follow-up after prototype feedback.

Document the integration boundary:

- What the adapter owns (command translation, projection, generation tracking).
- What EGW owns (operation identity, causal history, merge, convergence).
- What `incr` owns (reactive computation, dependency tracking, cell cache).
- What the application owns (logical document identity, UI policy, local state).

Update the linked Accepted ADR with the bounded result. If the experiment contradicts the accepted decision, write a superseding ADR rather than silently rewriting its outcome. Update the demo README and plan index. Record whether EGW issue #72 has adapter-only evidence worth reporting, but do not publish to that issue without explicit approval.

**DONE when:** the durable ADR, reader-facing demo boundary, evidence links, and plan disposition agree with the code and measured result.

## Done criteria

All criteria are mandatory:

- [x] The register/projection ADR is Accepted before implementation begins.
- [x] Published EGW 0.4.0 resolves in the standalone `incr` workspace, with no parent override or 0.3.0 fallback.
- [x] `SheetCommand`, opaque `DocumentGeneration`, `CommandApplicability`, `SheetExecutionContext`, and `validate_sheet_command` have one source of truth in an importable app-domain package; no copy remains and the future shell does not import the executable root.
- [x] Property keys, strict version-1 JSON payloads, `Unset`, `Source`, and `Deleted` semantics match the fixed schema; formula sequence text is not introduced.
- [x] Application logical document identity, `DocumentGeneration`, EGW identity/version, `incr` `Revision`, and dataflow `Epoch` remain distinct.
- [x] Local accepted commands mutate EGW before projection; invalid local source does not mutate EGW.
- [x] Remote sync mutates EGW before projection, and local/remote paths invoke the same projection function.
- [x] The functional core receives owned snapshots and returns immutable states, decisions, and diagnostics without reading EGW/DOM/Runtime/InputFields.
- [x] Last-seen authoritative registers, last-good semantic projection, and current diagnostics are distinct retained states represented by the fixed core result shapes.
- [x] EGW mutation read-back, structured application results, batch rollback, retained-state commit-after-success, and projection retry semantics are directly tested.
- [x] Malformed or unsupported remote application payloads publish deterministic diagnostics, retain local last-good Worksheet state without a false convergence claim, and reconverge after valid recovery.
- [x] One outer `Runtime::batch` applies each projection frame; `run_batched_op` is never nested inside it.
- [x] Clean drafts follow authoritative committed source; dirty drafts, selection, editing, and focus remain local.
- [x] Initial bootstrap and reset write seed registers to a fresh EGW document before deriving Worksheet state; reset also creates a fresh application identity and next generation without clearing the old CRDT document.
- [x] Required two-peer concurrency, delete race, duplicate/out-of-order/pending sync, draft, malformed payload, reset, and convergence tests pass.
- [x] No generic `egw_incr`, EGW source/API change, command ID, dedup store, transport, network, or dataflow coupling is introduced.
- [ ] Release-mode 1/10/100/2500 evidence and two independent full-scan/synthetic-hint browser comparisons are recorded and indexed against the pre-registered budget rule.
- [x] Every observed EGW pressure point is classified as adapter-local, EGW candidate, or deferred, with second-driver gating explicit.
- [x] `moon fmt`, `moon info`, `.mbti` review, standalone checks/tests, boundary scripts, targeted JS tests, and demo build/browser tests pass in order; superproject safety is verified and parent validation applicability is reported honestly.
- [ ] The ADR and README describe the shipped boundary and experiment result; Plan 013 is reconciled according to its disposition.

## Non-goals

- **No generic `egw_incr` package.** The adapter is application-specific.
- **No changes to `incr` public API.** The adapter uses existing `Worksheet`, `InputField`, and `Runtime` APIs.
- **No changes to EGW public API.** Record evidence gaps but do not modify EGW.
- **No formula grammar or type-checking changes.** Reuse existing `parse_cell_text_op` and runtime checking; this plan does fix committed formula source as an atomic register rather than sequence text.
- **No conflict resolution in the adapter.** EGW's merge semantics handle conflicts.
- **No synchronization of application-local state.** Selection, editing focus, and draft text remain application-local.
- **No command IDs, dedup, network, transport, or dataflow.** Out of scope.
- **No optimization before measurement.** Record baseline metrics first.

## Validation

**Ordered phases:**

1. **Standalone `incr` workspace first:** `moon fmt` → `moon info` → `.mbti` review → `moon check` → `moon test` → boundary scripts.
2. **Targeted JS demo:** Build and test the typed spreadsheet demo.
3. **`incr_tea` tests:** Ensure framework integration is not broken.
4. **Full validation:** `npm build` → `npm test:dom`.
5. **Superproject safety:** Verify that parent Canopy status and submodule pointers remain unchanged. Parent `moon check/test` counts as downstream validation only if the live parent `moon.work` explicitly includes this module; otherwise record it as not applicable rather than reporting a no-op as evidence.

**Commands:**

```bash
# Run from the standalone incr workspace root.
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
git diff -- '*.mbti'
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test
bash scripts/check-workspace-boundaries.sh
bash scripts/check-engine-isolation.sh
NEW_MOON_MOD=0 moon test --target js incr_tea

# Targeted JS demo and browser checks.
NEW_MOON_MOD=0 moon check --target js examples/typed_spreadsheet_incr_tea_demo
NEW_MOON_MOD=0 moon test --target js examples/typed_spreadsheet_incr_tea_demo
NEW_MOON_MOD=0 moon build --target js examples/typed_spreadsheet_incr_tea_demo
cd examples/typed_spreadsheet_incr_tea_demo
npm run build
npm run test:dom

# Adapter measurements always use release mode.
cd ../../
NEW_MOON_MOD=0 moon bench --release examples/typed_spreadsheet_incr_tea_demo

# Superproject safety after returning to the incr root.
git -C ../.. status --short --branch
rg -n 'loom/incr|typed_spreadsheet' ../../moon.work || true
# If the live parent moon.work has no matching member, parent MoonBit validation
# is not applicable. Do not edit or stage parent/submodule pointers to make it run.
```

**DO NOT:**

- Run validation in parent Canopy before standalone passes.
- Edit parent or submodule pointers.
- Commit, push, or publish without separate authorization.

## Drift check

Verify against merged commit `d512b63` (Plan 012) and current planning HEAD `48aa16e` (if different). Exact commands:

```bash
git log --oneline -1  # Verify current HEAD
git diff d512b63..HEAD -- examples/typed_spreadsheet_incr_tea_demo/
git diff d512b63..HEAD -- examples/typed_spreadsheet_demo/
git diff d512b63..HEAD -- examples/typed_spreadsheet/
```

If drift is detected in `SheetCommand`, `DocumentGeneration`, `CommandApplicability`, `SheetExecutionContext`, `validate_sheet_command`, Worksheet APIs, or `run_batched_op`/`parse_cell_text_op`, update this plan before proceeding.

## References

- [ADR: Typed spreadsheet EGW register and projection boundary](../docs/decisions/2026-07-20-typed-spreadsheet-egw-register-projection.md) — proposed durable authority, register, and evidence policy
- [Plan 012 reconciliation](README.md#reconciliation-notes) — `SheetCommand` variants and `DocumentGeneration`
- [PR #421](https://github.com/dowdiness/incr/pull/421) — Plan 012 implementation, merged as `d512b63`
- [PR #408](https://github.com/dowdiness/incr/pull/408) — Typed spreadsheet `incr_tea` integration (R16)
- [dowdiness/event-graph-walker#72](https://github.com/dowdiness/event-graph-walker/issues/72) — EGW public API surface (mention only; research updates require separate approval)
- [ADR: Independent differential dataflow module boundary](../docs/decisions/2026-07-19-independent-differential-dataflow-module.md) — EGW integration principles
- [ADR: Typed Spreadsheet Formula Type Checking](../docs/decisions/2026-06-02-typed-spreadsheet-runtime-checking.md) — Runtime checking boundary
- [ADR: Typed Spreadsheet Deleted-Cell Tombstone Lifecycle](../docs/decisions/2026-06-02-typed-spreadsheet-tombstone-lifecycle.md) — Presence anchor policy
