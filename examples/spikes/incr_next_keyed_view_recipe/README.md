# Issue #460: keyed View recipe spike

**Status:** Evidence-only standalone spike. This is not production `incr/` code.

**Reader:** Maintainers deciding whether a keyed Query can expose a rematerializable
`View[V]` without a memo-entry or global-erasure owner.

**Decision:** Select A (opaque recipe-backed `View[V]`) as the feasible
representation candidate. Keep B (`ExplicitView[K,V]`) only as the typed
comparison baseline; this does not authorize production adoption.

**Keep until:** Issue #460 reaches a design decision and the evidence is
summarized elsewhere.

**Disposition:** Preserve this spike only on its evidence branch; do not merge
it into main or promote it to the kernel or canonical docs. No production `incr/` or canonical `docs/` changes are part of
this result.

## Question and command

Can `Query[K,V] + K` be hidden in an opaque `View[V]` as a rematerializable
recipe, with no memo-entry owner and no global-erasure owner?

From the repository root, run the one harness command:

```bash
bash examples/spikes/incr_next_keyed_view_recipe/run.sh
```

It formats and regenerates interfaces, checks and runs the consumer under
wasm-gc and native, runs native RC evidence, checks expected negative compiler
probes by diagnostic code, and checks workspace/documentation boundaries.

## Field graph

The provider is standalone and does not wrap `@incr.DerivedMap`:

```text
Store
└── StoreCore { StoreId, ID allocator }

Region
└── RegionCore { RegionId, RegionEpoch, close_actions[] }

Query[K,V]
└── QueryCore[K,V]
    ├── owner StoreId
    ├── creation RegionGeneration
    ├── RegionEpoch                 (no RegionCore reference)
    ├── QueryId and counters
    ├── optional compute (K) -> V
    └── Map[K, MemoEntry[V]]         (typed, Query-owned)

View[V]
├── private metadata { owner, generation, ViewHandleId }
└── private recipe { QueryCore[K,V] + K }

ExplicitView[K,V]  (B)
├── private metadata
├── private QueryCore[K,V]
└── private K (K remains in the public type; no recipe closure)
```

`at` and `at_explicit` allocate only a ViewHandleId. They do not look up a
memo or run compute. Equal keys from multiple Views use one typed memo entry.
Eviction removes that entry; reading the same surviving View then allocates a
new MemoId.

Region close invokes Query close actions, clears each query's compute and memo
payloads, clears the action list, marks the region closed, and increments its
epoch. QueryCore references RegionEpoch but never RegionCore, so the
close-action edge has no library-controlled return edge. A surviving View
consequently returns structured `ClosedRegion`.

`Store::read(View[V])` and `EvalCtx::read(View[V])` check View metadata before
recipe invocation or Query lookup. Cross-store reads return structured
`CrossStore`; the debug counters show zero lookup/materialization/recipe change.
B uses the explicitly named `read_explicit` methods because MoonBit cannot
same-receiver-overload `read` by argument type. `View` has no public `get`,
`read`, or call operator.

## Alternatives and result matrix

| Property | A: opaque `View[V]` | B: `ExplicitView[K,V]` | Result |
|---|---:|---:|---|
| Hide `Query[K,V] + K` | Yes | No, K is retained | A answers the question |
| Rematerializable recipe | Closure-packaged | Direct typed Query+K | Pass |
| Memo-entry/global-erasure owner | Neither | Neither | Pass |
| Distinct K types accepted by one consumer | Yes | Generic only; K remains visible | A is more ergonomic |
| Metadata-first CrossStore rejection | Yes | Yes | Pass |
| Shared equal-key memo | Yes | Yes | Pass |
| Region-close release with surviving View | Yes | Yes | Pass |
| Mutable keys after `at` | Caller contract violation | Caller contract violation | Not supported |

**Actual constrained verdict:** A is feasible as an evidence-only shape. B is
type-honest but retains K and requires explicit read naming. This does not
authorize a production API or replacement kernel.

## Mutable-key counterexample

Both A and B deliberately mutate a `MutableKey` after materialization. The
provider's `Map` uses the key's current `Hash`/`Eq` value; changing it after
insertion can make lookup behavior invalid or create a second entry. The
caller contract is therefore: **keys must remain hash/equality stable for the
entire lifetime of every View and memo entry**, or the query must evict before
mutation. This is not solved by hiding K in A.

## Existing API First reuse check

This spike first compared the project evidence in V12.5 and V12.4:

- `examples/spikes/v12_5_view_alternatives` — opaque metadata and explicit
  read/error boundary language mechanics.
- `examples/spikes/ownership_field_skeleton` and
  `examples/spikes/ownership_native_rc` — scoped ownership and the V12.4
  external-object finalizer technique.

Core candidates checked before adding data manipulation were `Map`, `Hash`,
`Eq`, `Option`, `Result`, `Array`, and `Ref`. The provider uses a typed core
`Map`, optional compute/payloads, structured `Result` errors, arrays for close
actions, and `Ref` only for allocator/epoch/debug probe state. Mutation is
limited to allocator allocation, typed memo entries, counters, the close
transition, and mutable-key/RC probe state. These mutations are necessary to
model identity, caching, lifecycle, and the evidence observations; no mutable
global erasure or all-Views owner exists.

## Native RC evidence

`native_rc` reuses the V12.4 external-object finalizer technique: C external
tokens made by `moonbit_make_external_object` update live/finalized counters
in their finalizer. It does not use cache length as a proxy and makes no claim
of direct MoonBit destructors.

The executable proves:

1. An acyclic unclosed Store/Region/Query/View field graph releases the captured
   compute token and materialized payload token after all handles drop.
2. After materialization, `RegionCore::close` releases both tokens while a
   View remains; the surviving View returns `ClosedRegion`.

The wasm-gc consumer separately passes the same behavioral checks; native RC is
observation-only evidence.

## Negative compiler probes

The harness expects these current diagnostic codes:

| Probe | Code |
|---|---:|
| external View literal | 4036 |
| private View mutation | 4091 |
| `View.get` | 4015 |
| View call | 4014 |
| B key-type erasure | 4014 |

## Limitations and boundaries

- This is a minimal provider, not an adapter over current `DerivedMap`.
- It does not implement invalidation, scheduling, cancellation, effects, or a
  production retention policy.
- Hash-stable mutable-key behavior is a caller contract, not a runtime repair.
- Native finalizers observe marked tokens rather than every private MoonBit
  object; wasm-gc has no equivalent direct RC claim.
- The evidence does not claim direct MoonBit destructors or production API
  authorization.
- No replacement-kernel authorization and no ADR are included.
