# Examples

Standalone workspace modules that exercise or demonstrate `dowdiness/incr` without adding demo-only dependencies to the core library module.

The quickest practical demo is the live typed spreadsheet:
<https://typed-spreadsheet.pages.dev>. Edit one cell, then inspect which formulas
recomputed, which values changed, and where work produced the same result.

## Typed spreadsheet

- [`typed_spreadsheet/`](typed_spreadsheet/) — worksheet state, cell evaluation, formula dependencies, trace snapshots, and tests for the example boundary.
- [`typed_spreadsheet_demo/`](typed_spreadsheet_demo/) — shared operation vocabulary, formula text parser, fixed scenario, and serializable view model.
- [`typed_spreadsheet_cli_demo/`](typed_spreadsheet_cli_demo/) — CLI rendering for the shared fixed scenario.
- [`typed_spreadsheet_rabbita_demo/`](typed_spreadsheet_rabbita_demo/) — editable browser UI built with Rabbita; deployed at <https://typed-spreadsheet.pages.dev>.

## UI experiments

- [`incr_tea/`](incr_tea/) — experimental `incr`-native TEA skeleton with scope-owned model fields, batched message dispatch, and watched tracked views.

## Spikes

- [`spikes/ideal_api_rename_phase0/`](spikes/ideal_api_rename_phase0/) — checked language-mechanics probe for the public API rename migration plan.

## Commands

Run from the repository root:

```bash
moon check
moon test
moon test examples/incr_tea
moon run examples/typed_spreadsheet_cli_demo -- --format json
```

Run the browser demo from its module directory:

```bash
cd examples/typed_spreadsheet_rabbita_demo
npm run dev
```
