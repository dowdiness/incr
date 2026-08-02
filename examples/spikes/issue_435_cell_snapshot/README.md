# PROTOTYPE — Issue #435 kind-aware cell snapshot

This is throwaway code on `prototype/435-cell-snapshot-shape`. It is not a
public interface implementation and must not be merged to `main`.

## Question

Can one discriminated per-cell snapshot represent every live runtime cell kind
without optional-field soup, while leaving the current `pub(all) CellInfo`
field shape source-compatible?

## Run

```bash
moon run examples/spikes/issue_435_cell_snapshot/consumer
```

The command prints the candidate value for every live `CellRef` kind, exercises
variant-specific queries, constructs the real `@incr.CellInfo` literal from a
downstream package, checks current cross-Runtime/disposed soft-fail behavior,
and verifies that `ReadOnlyArray::from_array` owns a copy.

## Candidate seam

`CellSnapshot` exposes only `id`, `label`, and `CellSnapshotDetails`. The details
enum is the kind discriminator; there is no separate `CellKind` or common-header
type.

The variants describe physical runtime cells using public semantic names.
`AcceptedDerived` and `DerivedMap` remain compositions rather than invented cell
kinds.

| Internal `CellRef` | Snapshot detail |
|---|---|
| `PullInput` | `Input` |
| `PullMemo` | `Derived` |
| `HybridMemo` | `ReachableDerived` |
| `PushReactive` | `EagerDerived` |
| `PushEffect` | `Effect` |
| `Relation` | `Relation` |
| `FunctionalRelation` | `MapRelation` |
| `Rule` | payload-free `Rule` |
| `Disposed` | no snapshot (`None` at the query seam) |

## Existing interface and core candidates checked

- Project: `CellInfo`, `Runtime::cell_info`, `Runtime::dependents`,
  `Runtime::gc_root_count`, `CellRef`, `CellOps`, and Derived revision/dependency
  accessors.
- MoonBit core: enum pattern matching, `Option`, `Result`, `Array::copy`, and
  `ReadOnlyArray::from_array`. The shape uses the real `CellId`, `Revision`, and
  `Durability` types. `Map`/`Set` add no leverage to this value shape.

## Stop conditions

The shape fails if it changes a `CellInfo` field, invents composition kinds,
uses sentinel metadata, exposes mutable collections, publishes rule
declarations, or duplicates reverse-edge/root-ownership queries.

## Verdict

**GO with a read-only snapshot struct plus discriminated details.** The final
prototype decision is:

1. all eight live `CellRef` variants fit without optional-field soup;
2. `CellSnapshotCommon` and a separate `CellKind` fail the deletion test and are
   removed;
3. `subscribers` stays behind `Runtime::dependents` and root count stays behind
   `Runtime::gc_root_count`;
4. Rule carries no declaration payload, preserving the accepted Datalog
   lifecycle decision;
5. the real `pub(all) @incr.CellInfo` literal remains source-compatible in a
   downstream package;
6. `pub struct CellSnapshot` is readable but rejects external literals;
7. `ReadOnlyArray::from_array` owns immutable detail collections;
8. current cross-Runtime and disposed queries return `None`; production should
   preserve the same existing soft-fail rule for invalid IDs.

The production implementation should keep one pure lowering seam:
`CellRef + CellOps + kind-specific SoA data -> CellSnapshot`. The deprecated
`cell_info` adapter should consume that result for pull kinds and obtain reverse
edges through the existing `dependents` interface. Typed Derived introspection
remains because its handle-local seam has different locality and leverage.
