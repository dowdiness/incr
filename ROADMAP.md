# Roadmap

High-level future direction for the `incr` library, organized by phase. Each phase builds on the previous one.

## Phase 1 — Error Handling

- **Cycle error recovery**: Replace `abort()` in cycle detection with a `CycleError` type that callers can handle gracefully (see `cycle.mbt`)
- **Result-based APIs**: Offer `get_result()` variants on `Signal` and `Memo` that return `Result[T, Error]` instead of panicking

## Phase 2 — API & Usability

- **Batch updates**: Allow multiple `Signal::set` calls within a single revision bump to avoid redundant intermediate verifications
- **Introspection API**: Public methods to query the dependency graph — list dependents/dependencies of a cell, inspect cell state (`changed_at`, `verified_at`, durability)
- **Debug output**: Graph visualization or textual dump of the dependency graph for debugging

## Phase 3 — Performance

- **HashSet-based dependency deduplication**: Replace linear scan in `ActiveQuery::record` with a `HashSet` for O(1) dedup
- **Array-based cell storage**: Use `CellId` as a direct index into an array instead of a `HashMap` lookup
- **Incremental dependency diffing**: When a memo recomputes, diff the new dependency list against the old one to avoid full replacement

## Phase 4 — Advanced Features

- **Accumulator queries**: Support Salsa-style accumulators that collect values across the dependency graph
- **Interning**: Deduplicate structurally equal values to reduce memory and speed up equality checks
- **Garbage collection**: Reclaim cells that are no longer reachable from any live memo or signal

## Phase 5 — Ecosystem

- **Persistent caching**: Serialize the dependency graph and cached values to disk for cross-session incrementality
- **Parallel computation**: Explore concurrent memo evaluation if MoonBit gains thread or async support
