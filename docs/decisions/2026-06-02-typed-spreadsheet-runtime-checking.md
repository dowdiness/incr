# ADR: Typed Spreadsheet Formula Type Checking

**Date:** 2026-06-02
**Status:** Accepted; amended 2026-07-26 with Blank reference semantics
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

A missing or deleted address owned by the worksheet reads as
`CellResult::Ok(CellValue::Blank)`. A direct `Formula::Ref` preserves that value
when its declared result type accepts `Blank`. Integer scalar operators (`Add`,
`Mul`, and `Gt`) and `If` conditions remain strict and report `TypeError` when
an active operand is `Blank`; `Eq` continues to use `CellValue` equality, so two
Blank values compare equal. Foreign worksheet identities remain `RefError`.
Aggregate formulas are not currently implemented; a future aggregate may treat
Blank as its identity without changing scalar operator semantics.

## Rationale

The package demonstrates how a spreadsheet-shaped application can sit on top of
`incr` cells. Adding install-time formula inference would expand the demo into a
spreadsheet language/typechecker and blur the boundary recorded in the typed
spreadsheet plan: application code owns formula syntax, typing, parsing, and UI
policy; `incr` owns dependency tracking and recomputation.

Runtime checking also preserves current useful behavior: formulas can reference
missing cells, deleted cells, or cells whose value type changes later. Missing
and deleted reads preserve absence as `Blank` and still resolve reactively when
the referenced cells become present. Scalar formulas that require another type
surface `TypeError` rather than silently coercing Blank to zero.

This intentionally does not copy Excel's context-dependent empty-cell
coercions. Keeping Blank as a first-class value avoids hiding missing input as a
numeric zero, while reserving identity behavior for future aggregate operators
where it is explicit and algebraically appropriate.

## Consequences

- `Worksheet::set_formula` and `Worksheet::set_formula_ast` can return
  `Ok(())` for formulas that later read as `CellResult::TypeError`.
- Same-sheet missing and deleted reads return `Ok(Blank)`; foreign reads remain
  `RefError`.
- Direct references may preserve Blank, while active scalar operations reject
  it unless a future operator explicitly defines Blank as its identity.
- The `declared` result type is an evaluation contract, not an install-time type
  proof.
- Documentation must describe `examples/typed_spreadsheet` as runtime-checked.
- A future static formula API needs its own driver and design; it should not be
  smuggled into this demo package as an implicit behavior change.
