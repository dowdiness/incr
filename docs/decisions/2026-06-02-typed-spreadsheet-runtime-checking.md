# ADR: Typed Spreadsheet Formula Type Checking

**Date:** 2026-06-02
**Status:** Accepted
**Driver:** GitHub issue [#131](https://github.com/dowdiness/incr/issues/131)

## Decision

`examples/typed_spreadsheet` remains a runtime-checked demo boundary, not a
statically validated formula language.

Formula installation validates worksheet ownership and cross-sheet references.
It does not infer the formula result type, prove operator argument types, or
reject formulas such as `Text("x") + Int(1)` before replacing the cell
definition. Formula evaluation checks operator argument types and the declared
result type when the cell is read, returning `CellResult::TypeError` for
mismatches.

## Rationale

The package demonstrates how a spreadsheet-shaped application can sit on top of
`incr` cells. Adding install-time formula inference would expand the demo into a
spreadsheet language/typechecker and blur the boundary recorded in the typed
spreadsheet plan: application code owns formula syntax, typing, parsing, and UI
policy; `incr` owns dependency tracking and recomputation.

Runtime checking also preserves current useful behavior: formulas can reference
missing cells, deleted cells, or cells whose value type changes later. Those
reads naturally surface `RefError` or `TypeError` at evaluation time and then
resolve when the referenced cells become valid.

## Consequences

- `Worksheet::set_formula` and `Worksheet::set_formula_ast` can return
  `Ok(())` for formulas that later read as `CellResult::TypeError`.
- The `declared` result type is an evaluation contract, not an install-time type
  proof.
- Documentation must describe `examples/typed_spreadsheet` as runtime-checked.
- A future static formula API needs its own driver and design; it should not be
  smuggled into this demo package as an implicit behavior change.
