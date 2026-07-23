# Typed spreadsheet incr_tea proof

Side-by-side browser proof for expressing the typed spreadsheet's core edit loop
with the experimental `examples/incr_tea` renderer. The proof now exercises the
full 50×50 model while keeping the Rabbita demo as the primary live deployment.

## What it covers

The proof renders the full 50×50 grid and validates the interaction boundary
needed for the reusable `incr_tea` frame:

- selecting cells and editing the selected draft through the formula bar;
- double-clicking a cell to create an inline editor;
- focusing and selecting the inline editor with `Cmd::focus_element_by_id` after
  the renderer patches the DOM;
- applying with Enter/form submit and cancelling with Escape;
- routing committed apply, delete, and reset commands through the app-specific
  EGW adapter before projecting into the Worksheet;
- preserving unrelated DOM nodes while selection moves;
- resolving text payloads and keyboard actions at `BrowserRenderer::mount`,
  while cached `Html` values keep only pure event descriptors;
- rendering bounded trace/evidence panels as independent watched roots;
- publishing schema-versioned, bounded AI/tool context JSON after mount and
  after every update.

Spreadsheet parsing and operations reuse `examples/typed_spreadsheet_demo`; cell
calculation stays in `examples/typed_spreadsheet`.

## Architecture: the typed command pilot

`SheetCommand` is a strong, closure-free, self-contained application request.
Its variants bind each operation to its required local precondition, so an
apply/delete request cannot be paired with the wrong target or precondition.
Submitted text is fixed at message handling; variant-specific local UI and
document-generation preconditions are checked at execution. Outcomes are not
replay-deterministic without authoritative document state. `UiEffect` and
AI-context publication are local shell policy, not collaborative commands.

The current worksheet interpreter is a temporary imperative shell. A future
application-specific adapter alone may depend on EGW and incr:

```text
local SheetCommand
  -> typed-spreadsheet/EGW adapter mutation ─┐
                                            ├─> merged EGW document
remote SyncMessage
  -> EGW remote apply ─────────────────────┘
  -> shared pure spreadsheet projection
  -> Runtime::batch
  -> Worksheet + InputFields
```

EGW remains authoritative for operation IDs, causal history, merge, and
convergence. Local commands and remote sync must share this merged-state
projection path. Application command identities, future EGW operation IDs,
incr revisions, and dataflow epochs are distinct domains.

Command types live in the `domain/` package, promoted without copying by Plan 013
Phase 1 (2026-07-20). The domain package is the single source of truth for
opaque `DocumentGeneration` (`initial`/`next`, no public constructor), public
`SheetCommand`, public `CommandApplicability`, `SheetExecutionContext` with
`Type::Type` constructor, and pure `validate_sheet_command` preserving
stale-generation precedence. The root package imports domain with
package-local `using`; planning, UI, and interpreter helpers remain
root-local.

Phase 2 added the pure `egw_adapter/core/` package: strict versioned register
codec, immutable canonical snapshots and projection state, separate
last-seen/last-good/diagnostic state, ordered projection decisions, and pure
draft reconciliation. It has no mutable EGW document, Runtime, Worksheet,
InputField, DOM, or adapter shell. Phase 3 added the `egw_adapter/` shell
package boundary: an opaque `EgwAdapter` façade that imports the published EGW
container, `incr`, typed-spreadsheet/demo, domain, and child core, with no
generic bridge or EGW API change. The initial evidence used EGW 0.4.0; Phase 5
revalidated the unchanged adapter boundary against published EGW 0.5.0. The shell hides mutable
`Document`/`Worksheet`/state behind bootstrap/attach, local apply, remote
apply, export/version, immutable projection state, and read_cell/inspect_cell.
All authority paths perform EGW work first then invoke one shared full-scan
projection path; one outer `Runtime::batch` applies prepared operations with
rollback; structured results preserve rejection, `MutationNotLanded`, and
projection-error semantics. Nineteen package-owned white-box integration tests
exercise the mutable and observed boundaries end-to-end.

The browser executable now uses the adapter as its single-user committed
authority. It bootstraps the seed registers through EGW, routes apply/delete/
reset commands through `EgwAdapter`, observes trace and before/after evidence
without replaying Worksheet mutations, and reads projected cells through safe
adapter methods. Drafts, selection, editing, focus, status, and evidence remain
application-local. No remote transport, room/join protocol, or presence channel
exists yet.

Phase 4 added a package-owned JS release benchmark and a private benchmark-only
FullScan versus ChangedProperties lower bound for 1/10/100/2,500 changed cells.
The [dated evidence snapshot](../../docs/performance/2026-07-21-typed-spreadsheet-egw-adapter-evidence.md)
records the pre-wiring baseline and a reproducible sparse-workload advantage.
That historical baseline missed advisory p95 budgets on its measurement host,
so it cannot support an EGW performance conclusion; production remote
projection meanwhile continues to use FullScan. The accepted
[EGW register-projection ADR](../../docs/decisions/2026-07-20-typed-spreadsheet-egw-register-projection.md)
records durable correctness and API-quality conclusions: the current container
API is sufficient with adapter safeguards, and two narrow candidates
(error-transparent mutation, conservative impact reporting) are deferred until
a second driver, compatibility, convergence, and quantified-gain gates pass.
No generic `egw_incr` package is justified until a second driver repeats the
same adapter contract. The
accepted adapter ADR selects an atomic committed-source register for the first
bounded experiment; sequence-text formula collaboration would require a
superseding product decision.

Plan 013 closed on 2026-07-24 as a completed bounded experiment. The browser
baseline stop rule made the performance result inconclusive, so no EGW API or
optimization proposal follows from it. The adapter still consumes EGW
`container`, not `peer_sync`; transport, payload-opaque runtime/provider work,
room/join UX, and presence remain separate collaboration slices.

## Run

From this directory:

```bash
npm install
npm run dev
```

Production build, static smoke check, and browser interaction check:

```bash
npm run build
npm run smoke
npm run test:dom
```

Headless Chromium benchmark for the 50×50 edit paths:

```bash
BENCH_SAMPLES=20 BENCH_WARMUPS=3 npm run bench:dom
```

The benchmark dispatches pure messages through the mounted `BrowserRenderer`,
flushes all watched roots, and measures the in-page dispatch-to-DOM predicate
latency for selection, draft-only, visible edit, dependency, trace/evidence,
and offscreen edit scenarios. Budgets are advisory until a stable CI baseline
is established.

MoonBit-only validation from the repository root:

```bash
moon check --target js examples/typed_spreadsheet_incr_tea_demo
moon test --target js examples/typed_spreadsheet_incr_tea_demo
```
