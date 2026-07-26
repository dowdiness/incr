# ADR: Typed Spreadsheet Deleted-Cell Tombstone Lifecycle

**Date:** 2026-06-02
**Status:** Accepted; amended 2026-07-26 with Blank reference semantics
**Driver:** GitHub issue [#130](https://github.com/dowdiness/incr/issues/130)

## Decision

`examples/typed_spreadsheet` keeps a stable lightweight presence anchor for every
address that formulas have observed or that the worksheet has created. Deleting a
cell sets that anchor to `false`, so reads return
`CellResult::Ok(CellValue::Blank)` and formulas that reference the missing
address are invalidated when the address is later recreated. Scalar formulas
that require a non-Blank operand report `TypeError`; direct references whose
declared type accepts Blank preserve the Blank value.

Deleted cells retain their heavyweight definition/value slot by default. Long-lived
sparse sessions may call `Worksheet::compact_deleted_cells()` after a successful
edit or after `Runtime::batch`/`Runtime::batch_result` returns. Compaction refreshes
present formulas first, then disposes deleted cells' heavyweight slots while
preserving the presence anchors.

No core `incr` lifecycle API is added for this policy.

## Rationale

The presence anchor is the part that carries spreadsheet address identity across
delete/recreate cycles. Removing it would break two important behaviors: formulas
depending on a deleted address need to observe the deletion, and formulas that
reference a missing address need to observe later recreation.

The heavyweight slot is different. Keeping it makes ordinary delete/recreate and
batch rollback straightforward, but retaining many distinct deleted addresses can
grow memory in long sessions. Explicit compaction gives sparse applications a
bounded-slot maintenance path without weakening dependency invalidation.

Compaction is post-commit because reads inside an open batch observe pre-commit
values. Running it after the batch result is known preserves rollback semantics:
failed delete/create batches restore prior state, and a compaction pass sees only
committed deleted cells.

## Consequences

- Deleted addresses remain represented by `cell_presence` anchors until the
  worksheet is disposed.
- `Worksheet::compact_deleted_cells()` returns the number of heavyweight slots it
  pruned.
- Deleted cells read as `Ok(Blank)` after delete and after compaction.
- Dependent formulas observe that Blank and resolve after recreation; strict
  scalar formulas report `TypeError` while the dependency is Blank.
- Compaction is example-local policy for `examples/typed_spreadsheet`; future core
  lifecycle APIs require a separate driver.
