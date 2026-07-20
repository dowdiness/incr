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

Command types stay package-local until Plan 013 Phase 1 promotes them—without
copying—to an importable application-domain package. Phase 0 standalone EGW
0.4.0 verification passed 2026-07-20; Phase 1 will promote the types next. No
generic `egw_incr` package is justified until a second driver repeats the same
adapter contract. The accepted adapter ADR selects an
atomic committed-source register for the first bounded experiment;
sequence-text formula collaboration would require a superseding product
decision.

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
