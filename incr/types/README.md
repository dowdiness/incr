# dowdiness/incr/types

Pure, zero-dependency value types used by [`dowdiness/incr`](../README.mbt.md).

Consumers normally import `dowdiness/incr`, which re-exports everything in this package. Import `dowdiness/incr/types` directly only when an API needs these value types without pulling in the incremental engine.

## Contents

- **Revision tracking:** `Revision`, `HasChangedAt`, `BackdateEq`
- **Durability:** `Durability`, `GcRole`
- **Errors:** `ReadError`, `CycleError`
- **Identifiers:** `RuntimeId`, `CellId`, `ListenerId`, `RuleId`, `AccumulatorId`, `InternId`
- **Interning:** `InternTable`

## See also

- [Library README](../README.mbt.md) — overview, quick start, and installation
- [API Reference](../../docs/api-reference.mbt.md) — public types, methods, and helpers
