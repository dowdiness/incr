# Roadmap

High-level future direction for the `incr` library, organized by phase. Each phase builds on the previous one. For a detailed explanation of the current architecture, see [DESIGN.md](DESIGN.md).

## Phase 1 — Error Handling ✓

- ~~**Cycle error recovery**: Replace `abort()` in cycle detection with a `CycleError` type that callers can handle gracefully~~ ✓ Implemented with `CycleError` suberror type
- ~~**Result-based APIs**: Offer `get_result()` variants on `Signal` and `Memo` that return `Result[T, CycleError]` instead of panicking~~ ✓ Implemented

## Phase 2 — API & Usability

- ~~**Batch updates**: Allow multiple `Signal::set` calls within a single revision bump to avoid redundant intermediate verifications~~ ✓ Implemented with two-phase signal values and revert detection
- **Introspection API**: Public methods to query the dependency graph — list dependents/dependencies of a cell, inspect cell state (`changed_at`, `verified_at`, durability)
- **Debug output**: Graph visualization or textual dump of the dependency graph for debugging

## Phase 3 — Performance

- ~~**HashSet-based dependency deduplication**: Replace linear scan in `ActiveQuery::record` with a `HashSet` for O(1) dedup~~ ✓ Implemented
- ~~**Array-based cell storage**: Use `CellId` as a direct index into an array instead of a `HashMap` lookup~~ ✓ Implemented
- ~~**Iterative verification**: Convert recursive `maybe_changed_after` to iterative with explicit stack~~ ✓ Implemented
- **Incremental dependency diffing**: When a memo recomputes, diff the new dependency list against the old one to avoid full replacement

## Phase 4 — Advanced Features

- **Subscriber (reverse) links**: Add bidirectional edges so cells know their dependents. This is a prerequisite for push-based invalidation, automatic cleanup, and the effect system. Inspired by [alien-signals](https://github.com/nicepkg/alien-signals) which uses subscriber links for efficient propagation.
- **Push-pull hybrid invalidation**: Combine push notifications (via subscriber links) with pull verification. When an input changes, propagate dirty flags eagerly; on read, verify lazily. This avoids the full verification walk for unchanged subgraphs while preserving backdating benefits.
- **Accumulator queries**: Support Salsa-style accumulators that collect values across the dependency graph
- **Interning**: Deduplicate structurally equal values to reduce memory and speed up equality checks
- **Garbage collection**: Reclaim cells that are no longer reachable from any live memo or signal. Requires subscriber links for reference tracking.

## Phase 5 — Ecosystem

- **Persistent caching**: Serialize the dependency graph and cached values to disk for cross-session incrementality
- **Parallel computation**: Explore concurrent memo evaluation if MoonBit gains thread or async support
- **Effect system**: First-class side effects (like alien-signals' `Effect` type) that trigger when observed values change. Out of scope for the current pure-computation model but worth revisiting once subscriber links are in place.
