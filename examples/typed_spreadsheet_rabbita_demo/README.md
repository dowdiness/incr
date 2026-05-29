# Typed spreadsheet Rabbita demo

Browser UI for the fixed five-step typed spreadsheet scenario. The demo keeps
worksheet evaluation, dependency tracking, trace collection, and ViewModel
serialization in MoonBit; Rabbita only renders and navigates the resulting data.

## Responsibility map

| Package | Responsibility |
| --- | --- |
| `dowdiness/incr/typed_spreadsheet` | Worksheet state, cell evaluation, formula dependencies, trace snapshots. |
| `dowdiness/incr/examples/typed_spreadsheet_demo` | Demo operation vocabulary, tiny formula text parser, shared fixed scenario, serializable ViewModel. |
| `dowdiness/incr/examples/typed_spreadsheet_cli_demo` | Text/JSON CLI rendering for the shared scenario. |
| `dowdiness/incr/examples/typed_spreadsheet_rabbita_demo` | Rabbita model/update/view and browser packaging. No spreadsheet calculation is reimplemented here. |

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
moon test examples/typed_spreadsheet_demo
```

## UI scope

This PR intentionally does **not** add editing. The user task is to make the
state transitions and dependency buckets easier to inspect than CLI output:

1. `A1 = 10`
2. `B1 = A1 + 1`
3. `A1 = 15` (`B1` changes)
4. `A1 = 15` again (`B1` recomputes but remains unchanged)
5. `delete B1`

The UI exposes step navigation, trace buckets (`recomputed`, `changed`,
`unchanged`), a tiny A1/B1 grid, and before/after snapshots.

## ViewModel and JS export

`@demo.fixed_scenario_view_model()` returns a schema-versioned MoonBit
ViewModel with reserved `extensions` maps. The sibling `data` package exports
`typed_spreadsheet_scenario_json()` through the JS backend for tests or external
demos that need the MoonBit-computed data without mounting the Rabbita app.

## Future extensions

- Range references can add fields under `extensions` before changing the schema.
- Multiple sheets can extend the `cells` identifiers from addresses to
  sheet-qualified labels.
- Editing should be added as new `Msg` values and MoonBit operations, not as JS
  spreadsheet logic.
