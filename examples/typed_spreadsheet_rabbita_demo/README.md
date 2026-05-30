# Typed spreadsheet Rabbita demo

Browser UI for a small editable typed spreadsheet. The app keeps worksheet
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

## Run

From this directory:

```bash
npm install
npm run dev
```

Then open the Vite URL printed by the command. `npm run dev` first runs
`moon build --target js --release` from the repository root so the MoonBit app
exists under `_build/js/release/...` before Vite imports it.

Production build:

```bash
npm run build
```

MoonBit-only validation from the repository root:

```bash
moon check --target js
moon test --target js
```

## Editor scope

The editor starts with a four-cell sheet:

- `A1 = 10`
- `B1 = A1 + 1`
- `A2` and `B2` empty

Users can select a cell, edit its draft text, apply the edit, or delete the
cell. Supported text intentionally stays tiny:

- `10` installs an integer input.
- `=A1 + 1` installs an integer addition formula.
- `=A1 * 2` installs an integer multiplication formula.
- `=if(A1 > 10, 1, 0)` installs an integer conditional formula.

After each applied edit, the UI shows trace buckets (`recomputed`, `changed`,
`unchanged`), the current sheet cells, and before/after snapshots for the
selected cell.

Out of scope for this prototype: ranges, multiple sheets, persistence,
collaboration, and a general Excel-compatible parser.

## Fixed scenario JSON export

The sibling `data` package still exports the fixed five-step scenario for tests
or external demos that need non-DOM JSON:

- `@demo.fixed_scenario_view_model()` returns the schema-versioned MoonBit
  ViewModel.
- `typed_spreadsheet_scenario_json()` exposes that data through the JS backend.

The editable Rabbita UI does not move or replace this non-DOM export.
