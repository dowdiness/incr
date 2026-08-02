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

The command prints the full candidate value for every live `CellRef` kind,
exercises variant-specific queries, constructs the old `CellInfo` literal from
a downstream package, and checks that `ReadOnlyArray::from_array` owns a copy.

## Candidate boundary

`CellSnapshot` contains:

- `CellSnapshotCommon`: only metadata meaningful for every live cell;
- `CellSnapshotDetails`: one variant per runtime storage/engine kind.

The vocabulary intentionally follows runtime cells rather than facade
compositions. `AcceptedDerived` and `DerivedMap` remain compositions of cells;
they are not invented as runtime cell kinds.

| Internal `CellRef` | Candidate detail |
|---|---|
| `PullInput` | `Input` |
| `PullMemo` | `PullDerived` |
| `HybridMemo` | `ReachableDerived` |
| `PushReactive` | `EagerDerived` |
| `PushEffect` | `Effect` |
| `Relation` | `Relation` |
| `FunctionalRelation` | `MapRelation` |
| `Rule` | `Rule` |
| `Disposed` | no snapshot (`None` at the query seam) |

## Existing interface and core candidates checked

- Project: `CellInfo`, `Runtime::cell_info`, `Runtime::dependents`,
  `Runtime::gc_root_count`, `CellRef`, `CellOps`, and Derived revision/dependency
  accessors.
- MoonBit core: enum pattern matching, `Option`, `Result`, `Array::copy`, and
  `ReadOnlyArray::from_array`. `Map`/`Set` add no leverage to this value shape.

## Stop conditions

The shape fails if it requires changing a `CellInfo` field, inventing facade
kinds that Runtime cannot distinguish, using absent metadata as sentinel
values, exposing a mutable collection, or adding a second dependency-query
implementation.

## Verdict

**GO with the common-header + discriminated-details shape.** The prototype
established that:

1. all eight live `CellRef` variants fit without optional-field soup;
2. the runtime vocabulary must describe engine cells, not facade compositions;
3. the existing `pub(all) CellInfo` literal remains source-compatible beside
   the additive snapshot types;
4. declaring `CellSnapshot` and `CellSnapshotCommon` as `pub struct` lets
   downstream code read them but rejects invalid external struct literals;
5. `ReadOnlyArray::from_array` owns an immutable copy, so snapshot collections
   do not expose runtime arrays;
6. `Disposed`, invalid, and cross-Runtime IDs should remain `None` at the query
   seam rather than becoming a fake cell-kind variant.

The production implementation should keep one mapping seam:
`CellRef + CellOps + kind-specific SoA data + RuntimeCore.gc_root_counts ->
CellSnapshot`. The deprecated `cell_info` adapter should delegate to that result
for pull kinds, which makes the old implementation deletable in the later
contract phase.
