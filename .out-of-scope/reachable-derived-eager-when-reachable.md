# ReachableDerived: Eager-When-Reachable Differentiation

**Category:** enhancement
**Outcome:** wontfix for the current request — not commissioned, not implemented.

This record captures a durable deferral. It does not declare the work
permanently impossible; it is gated until a concrete driver exists.

## Summary

The request was to differentiate `ReachableDerived` into a genuine
eager-when-reachable memo: while downstream push roots exist, the cell would
recompute during push propagation (not lazily on read) and emit per-edit
recomputed / changed / verified-clean events. For eager evaluation,
`ReachableDerived` currently behaves like `Derived`: it remains lazy until
read through a downstream push node.

## Durable reason

The architecture decision record
[2026-05-30 — ReachableDerived: differentiate or collapse](../docs/decisions/2026-05-30-reachable-derived-differentiate-or-collapse.md)
explicitly defers differentiation. Its re-open trigger requires a maintained
in-repo consumer that observes per-edit change-set events for a bounded visible
region of a lazy derived graph. No such consumer exists. The
[roadmap](../docs/roadmap.md) confirms that no core implementation is currently
commissioned.

Push propagation traverses `HybridMemo` and `PullMemo` branches to downstream
push nodes but evaluates only push reactive and effect cells — memos are
recomputed lazily when a push node reads them. This is the gap the request
targets, and it remains unbridged.

## Partial existing capabilities

Several facilities touch adjacent concerns but do not satisfy the
commissioning trigger:

- **Typed Spreadsheet** (`examples/typed_spreadsheet/`) provides bounded
  snapshot-diff formula tracing by reading caller-provided observed formulas.
  It does not consume per-edit change events from a viewport anchor.
- **Derived event lifecycle** (`incr/cells/derived_event.mbt`) exposes
  recompute lifecycle events but has no verified-clean event.
- **Canopy canvas runtime** (`dowdiness/canopy`,
  `apps/canvas/main/canvas_runtime.mbt`) watches a single
  `scope.reachable_derived` inspector but does not consume change events.
- **Canopy visualizer** (`dowdiness/canopy`,
  `modules/visualizer/incr_tap.mbt`) consumes derived events on a separate
  editor runtime. It does not provide bounded viewport change sets.

None of these adopt the viewport-anchor-and-consume-events pattern that the
ADR's trigger requires.

## Reconsider when

A maintained in-repo consumer needs to observe the per-edit change-set
(recomputed / changed / verified-clean) of a bounded visible region of a lazy
derived graph — the concrete candidate being a projectional-editor viewport
over a `Derived`-to-registry-to-source chain. That consumer adopting a viewport
anchor and consuming the events is the driver; absent it, do not implement.

When this trigger fires, create or reopen an implementation request rather
than treating this closed record as currently actionable.

## Prior requests

- [#124 — ReachableDerived: differentiate into eager-when-reachable](https://github.com/dowdiness/incr/issues/124) (Deferred — re-open trigger inside)
