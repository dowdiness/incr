# Typed spreadsheet incr_tea proof

Side-by-side browser proof for expressing the typed spreadsheet's core edit loop
with the experimental `examples/incr_tea` renderer. This is **not** a replacement
for the Rabbita demo or the live site; `examples/typed_spreadsheet_rabbita_demo`
remains the primary editable demo until this proof is evaluated.

## What it covers

The proof intentionally renders a small 4×4 grid instead of full visual parity.
It validates the interaction boundary that issue #271 needs:

- selecting cells and editing the selected draft through the formula bar;
- double-clicking a cell to create an inline editor;
- focusing and selecting the inline editor with `Cmd::focus_element_by_id` after
  the renderer patches the DOM;
- applying with Enter/form submit and cancelling with Escape;
- resolving text payloads and keyboard actions at `BrowserRenderer::mount`, while
  cached `Html` values keep only pure `on_input`, `on_keydown`, `on_submit`,
  `on_dblclick`, and `on_blur` descriptors.

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

MoonBit-only validation from the repository root:

```bash
moon check --target js examples/typed_spreadsheet_incr_tea_demo
moon test --target js examples/typed_spreadsheet_incr_tea_demo
```
