# Typed spreadsheet Rabbita demo

Browser UI for an editable 50×50 typed spreadsheet. The app keeps worksheet
evaluation, dependency tracking, trace collection, and snapshot inspection in
MoonBit; Rabbita renders the sheet and routes user edits back to MoonBit
operations.

## Responsibility map

| Package | Responsibility |
| --- | --- |
| `dowdiness/incr/typed_spreadsheet` | Worksheet state, cell evaluation, formula dependencies, trace snapshots. |
| `dowdiness/incr/examples/typed_spreadsheet_demo` | Demo operation vocabulary, tiny formula text parser, fixed scenario, and serializable fixed ViewModel. |
| `dowdiness/incr/examples/typed_spreadsheet_cli_demo` | Text/JSON CLI rendering for the shared fixed scenario. |
| `dowdiness/incr/examples/typed_spreadsheet_rabbita_demo` | Rabbita model/update/view and browser packaging for the editable prototype. No spreadsheet calculation is reimplemented here. |

## Interface direction

The editor follows an Ephe-inspired "one quiet sheet" layout: the spreadsheet grid
owns the full viewport, while editing, trace, evidence, reset, and appearance
controls live behind a small toggle rail. Paper mode is the default; night mode
keeps the same grey-first palette for low-light demos. Formulas, values, and cell
labels stay in a tabular monospace.

Keyboard behavior mirrors a tiny spreadsheet:

- Arrow keys move the selected cell while the grid is focused.
- Use the `edit` rail toggle to open the formula bar and sheet controls.
- Double-click a cell to focus an inline editor.
- Enter applies the selected cell's draft.
- Moving focus away from the inline editor applies its draft.
- Escape reverts the selected draft to the last committed text.

All worksheet changes still flow through `@demo.parse_cell_text_op` and
`@demo.run_op`; the Rabbita layer does not evaluate formulas in JavaScript.

## Run

From this directory:

```bash
npm install
npm run dev
```

Then open the Vite URL printed by the command. `npm run dev` first runs
`moon build --target js --release` from the repository root so the MoonBit app
exists under `_build/js/release/...` before Vite imports it.

Production build and local smoke check:

```bash
npm run build
npm run smoke
```

`npm run smoke` serves `dist/` on localhost, fetches the built page and local
assets, and checks that the typed sheet editor bundle and styles are present.

## Cloudflare Pages deployment

`.github/workflows/spreadsheet-demo-build.yml` builds this demo on PRs that
change the spreadsheet app or its MoonBit dependencies.
`.github/workflows/spreadsheet-cloudflare-pages.yml` deploys the built `dist/`
directory to Cloudflare Pages on pushes to `main` and manual workflow runs.

Configure these repository settings before enabling deploys:

- Cloudflare Pages Git-connected builds disabled/disconnected, so GitHub Actions
  is the only deploy writer for the project
- secret `CLOUDFLARE_API_TOKEN` with Cloudflare Pages edit/deploy access
- secret `CLOUDFLARE_ACCOUNT_ID`
- variable `CLOUDFLARE_PAGES_PROJECT_NAME`

MoonBit-only validation from the repository root:

```bash
moon check --target js
moon test --target js
```

## Editor scope

The editor renders a 50×50 sheet from `A1` through `AX50`:

- `A1 = 10`
- `B1 = A1 + 1`
- all other cells start empty

Users can select a cell, double-click to edit it directly in the grid, apply the
edit, or delete the cell. Supported text intentionally stays tiny:

- `10` installs an integer input.
- `=A1` installs an integer cell-reference formula.
- `=A1 + 1` installs an integer addition formula.
- `=A1 * 2` installs an integer multiplication formula.
- `=if(A1 > 10, 1, 0)` installs an integer conditional formula.

After each applied edit, the toggle rail can reveal trace buckets (`recomputed`,
`changed`, `unchanged`) and before/after snapshots for the selected cell. The
grid scrolls in both directions and keeps row/column headers sticky while
navigating the 2,500 cells.

Out of scope for this prototype: ranges, multiple sheets, persistence,
collaboration, and a general Excel-compatible parser.

## Fixed scenario JSON export

The sibling `data` package still exports the fixed five-step scenario for tests
or external demos that need non-DOM JSON:

- `@demo.fixed_scenario_view_model()` returns the schema-versioned MoonBit
  ViewModel.
- `typed_spreadsheet_scenario_json()` exposes that data through the JS backend.

The editable Rabbita UI does not move or replace this non-DOM export.
