# K1.4 typed cutoff compile probe

**Reader:** K1.4 implementers and reviewers.

**Decision:** Select separate typed `Region` constructors. Preserve the
existing `Region::query` as the unbounded-`V` AlwaysChanged baseline; add
explicit `query_always_changed`, `query_eq` with `V : Eq`, and
`query_type_owned` with a standalone `pub(open)` `CutoffEq` trait. The smallest
natural type-owned spelling emitted by the pinned compiler is:

```moonbit
pub(open) trait CutoffEq {
  fn cutoff_equal(Self, Self) -> Bool
}
```

The selected constructor surface is:

```text
pub fn[K : Hash + Eq, V] Region::query(
  Self,
  (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError]

pub fn[K : Hash + Eq, V] Region::query_always_changed(
  Self,
  (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError]

pub fn[K : Hash + Eq, V : Eq] Region::query_eq(
  Self,
  (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError]

pub(open) trait CutoffEq {
  fn cutoff_equal(Self, Self) -> Bool
}

pub fn[K : Hash + Eq, V : CutoffEq] Region::query_type_owned(
  Self,
  (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError]
```

`K : Hash + Eq` remains the K1.2 baseline bound. `V` remains unbounded on
`Region::query` and `query_always_changed`. There is no public policy enum,
arbitrary predicate parameter, or `TrustedCutoff` contract.

**Keep until:** The selected K1.4 public interface is removed, superseded, or
folded into a durable published API record.

**Disposition:** **Retain as generated-interface provenance for the adopted,
unpublished Incr Next product.** This evidence fixes the interface
used by the accepted K1.4 implementation at validation head
`0036bdd199a685823b6769bf1acdac3f9b6b9014`, finalized at status-only head
`c88e724383ca5f3e817f30226a9fa23cf3ad7358`, and merged as squash commit
`9d53d51d6ec6e282b8aa247442ee126acfe64a2d`. Hosted acceptance passed 46/46,
public diff review was APPROVE, maintainer acceptance was PASS, and squash-tree
equivalence passed. K1.5 is accepted and merged at implementation head
`064a80ac884f7c5588f123cc62dd784adeb26b48`, review-fix head
`378df40f7b84e1b6a3ebdb7f32299e2d628f1d54`, status-only head
`6de46abf19acb69cc5d5274b89a0ee780e48fb8d`, and squash merge commit
`4e66654d021435179116c0cffd56c0216b1bc664`; it adds no public proof-loss or
eviction surface. K1.6 conformance is accepted and merged, completing K1. This
record does not authorize publication or Canopy production integration.

## Scope and Existing API First

The probe starts from exact base
`f875e5326df3659674cd8574f947322ec960caaf` and leaves `incr_next/`, current
`incr/`, generated `.mbti` files, testkit, and CI unchanged. It uses isolated
temporary MoonBit modules with the existing public shape (`Region`, `Query`,
`QueryContext`, `ReadError`, `RegionError`) only to compile constructor
boundaries and generated interfaces.

The c640f65 cutoff spike was consulted for candidate names and the
standalone-trait idea. Its provider implementation was not copied. The probe
rechecks the names and bounds independently against the pinned compiler. Core
`Hash`/`Eq` trait bounds are retained from the K1.2 interface; no new policy
representation or counters are introduced by this probe.

## Compared variants

### A — separate constructors: selected

The isolated API compiled, and an external consumer compiled all four cases:

- baseline `Region::query` with a commissioned non-`Eq` result;
- explicit `query_always_changed` with that same result;
- `query_eq` with an `Eq` result;
- `query_type_owned` with a non-`Eq` result implementing `CutoffEq`.

The generated interface was:

```text
pub fn[K : Hash + Eq, V] Region::query(Self, (QueryContext, K) -> Result[V, ReadError]) -> Result[Query[K, V], RegionError]
pub fn[K : Hash + Eq, V] Region::query_always_changed(Self, (QueryContext, K) -> Result[V, ReadError]) -> Result[Query[K, V], RegionError]
pub fn[K : Hash + Eq, V : Eq] Region::query_eq(Self, (QueryContext, K) -> Result[V, ReadError]) -> Result[Query[K, V], RegionError]
pub fn[K : Hash + Eq, V : CutoffEq] Region::query_type_owned(Self, (QueryContext, K) -> Result[V, ReadError]) -> Result[Query[K, V], RegionError]
pub(open) trait CutoffEq {
  fn cutoff_equal(Self, Self) -> Bool
}
```

### B — `V : Eq` on baseline `Region::query`: rejected

A separate API variant changed only the baseline to `V : Eq`. The same external
non-`Eq` consumer was rejected by the compiler. This narrows the existing
baseline consumer boundary, so it cannot preserve K1.2 compatibility. The
selected interface keeps `V` unbounded and puts `Eq` only on `query_eq`.

### C — public generic policy/predicate: rejected

A compiling variant exposed:

```text
pub(all) enum CutoffPolicy[V] {
  AlwaysChanged
  Compare((V, V) -> Bool)
}
pub fn[K : Hash + Eq, V] Region::query_with_policy(
  Self,
  (QueryContext, K) -> Result[V, ReadError],
  CutoffPolicy[V],
) -> Result[Query[K, V], RegionError]
```

The generated interface consequently leaks both the public generic policy and
an arbitrary `(V, V) -> Bool` predicate contract. Making that policy private
would not make it a suitable public constructor boundary; a public signature
must expose the policy contract. The selected interface therefore has no
policy enum or predicate constructor.

### D — standalone trait vs supertrait: standalone selected

The standalone `CutoffEq` API compiled with the commissioned non-`Eq`
consumer. The alternative
`pub(open) trait CutoffEq : Eq` also generated successfully, but its external
non-`Eq` consumer failed with compiler error `[4018]`: `NonEq` does not
implement `Eq`. The supertrait adds an unnecessary structural constraint and
cannot support the commissioned type-owned non-`Eq` case.

A second supertrait variant added a public `HasChangedAt`-style projection. A
consumer implementing only type-owned propagation equality was rejected because
it lacked that unrelated projection, and the generated interface exposed the
extra trait and method.

The standalone trait is therefore the smallest natural contract: one open
method, no `Eq` requirement, and no `HasChangedAt`-style changed-at projection.
The exact method spelling is selected because it is what the generated
interface records and because the external implementation compiled under the
pinned toolchain.

## Current-candidate delta guard

The script compares the tracked current `incr_next/pkg.generated.mbti` with the
same path at the exact base. The result is intentionally empty:

```text
=== exact current-candidate delta ===
(empty; production remains at the commissioned K1.4 base)
```

Before the production edit, the delta is empty. After implementation, the same
probe accepts only the three selected constructors and standalone trait/method
as additions, with no deletion or widening of the baseline interface. It rejects
any other current-candidate delta. No private policy, predicate, cutoff counter,
or storage representation may appear.

## Reproduction identity and output

Run from the repository root:

```bash
./scripts/probe-incr-next-k1-4-cutoff.sh
```

The script downloads and verifies the same pinned archives as the K1.2 probe,
bundles the core for both required checks, asserts `NEW_MOON_MOD=0`, resolves
the exact base, compiles the passing variants, regenerates their interfaces,
and checks the two rejected consumer boundaries.

```text
moon 0.1.20260713 (75c7e1f 2026-07-13)
moonc v0.10.4+ade96c819 (2026-07-13)
probe base: f875e5326df3659674cd8574f947322ec960caaf
D Eq-supertrait non-Eq consumer: rejected
D HasChangedAt-supertrait consumer without changed_at: rejected
B V:Eq baseline non-Eq consumer: rejected
K1.4 typed cutoff constructor interface probe: PASS
```

```text
NEW_MOON_MOD=0
Binary SHA-256: 5cce093c6795211fcade5e5ff697d88ec4ff416d2785197f004188aca724a753
Core SHA-256:   e2bf3cc765412055242384fb72a618b62ad4889eae11956251ff921839d022d2
```

## Uncertainty

This is a compile and generated-interface probe, not semantic evidence by
itself. It does not validate cutoff timing, backdating, trace replacement,
failure/cycle atomicity, Fresh parity, or runtime ownership. Those separate
implementation and acceptance gates pass at
`0036bdd199a685823b6769bf1acdac3f9b6b9014`. The spelling is established for
the recorded MoonBit toolchain; a future toolchain may render equivalent syntax
differently and must be rechecked before implementation.
