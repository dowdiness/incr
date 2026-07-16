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
