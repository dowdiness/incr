# Roadmap

High-level future direction for the `incr` library, organized by phase. Each phase builds on the previous one. For a detailed explanation of the current architecture, see [design.md](design.md).

## Phase 1 — Error Handling ✓

- ~~**Cycle error recovery**: Replace `abort()` in cycle detection with a `CycleError` type that callers can handle gracefully~~ ✓ Implemented with `CycleError` suberror type
- ~~**Result-based APIs**: Offer `get_result()` variants on `Signal` and `Memo` that return `Result[T, CycleError]` instead of panicking~~ ✓ Implemented

## Phase 2 — API & Usability

- ~~**Batch updates**: Allow multiple `Signal::set` calls within a single revision bump to avoid redundant intermediate verifications~~ ✓ Implemented with two-phase signal values and revert detection

### Phase 2A: Introspection & Debugging ✓

- ~~**Introspection API**: Public methods to query the dependency graph~~ ✓ Implemented
  - Per-cell methods: `Signal::id()`, `Signal::durability()`, `Memo::dependencies()`, `Memo::changed_at()`, `Memo::verified_at()`
  - Runtime methods: `Runtime::cell_info(CellId)` returning structured `CellInfo` (with `label` field)
- ~~**Enhanced error diagnostics**: Include cycle path in `CycleError`~~ ✓ Implemented with `CycleDetected(CellId, Array[CellId])` and `format_path()`
- ~~**Debug output**: `Signal::debug()` and `Memo::debug()` methods~~ ✓ Implemented
- **Graph visualization**: Textual or DOT format dump of dependency graph

### Phase 2B: Observability ✓

- ~~**Per-cell change callbacks**~~ ✓ Implemented
  - `Signal::on_change(f : (T) -> Unit)`, `Memo::on_change(f : (T) -> Unit)`
  - `Signal::clear_on_change()`, `Memo::clear_on_change()`
  - Fires per-cell callbacks before `Runtime::fire_on_change()`
  - Stored on `CellMeta` via type-erased closures

### Phase 2C: Unified Constructors & Labels ✓

- ~~**Unified constructors with optional params**~~ ✓ Implemented (replaced builder pattern)
  - `Signal::new(rt, val, durability?=Low, label?=String)` replaces `Signal::new_with_durability`
  - `Memo::new(rt, f, label?=String)` with optional label
  - `create_signal(db, val, durability?=Low, label?=String)` replaces `create_signal_durable`
  - `create_memo(db, f, label?=String)` with optional label
- ~~**Labels**~~ ✓ Labels propagate through `CellMeta`, `CellInfo`, `format_path`, and debug output
- **Method chaining**: Fluent configuration for Runtime — deferred
- **Convenience helpers**: Shorter names for common patterns — deferred

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
