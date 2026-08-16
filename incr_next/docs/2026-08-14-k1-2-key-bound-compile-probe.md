# K1.2 key-bound compile probe

**Reader:** K1.2 implementers and reviewers.

**Decision:** Put the public `K : Hash + Eq` bound on `Region::query`. Keep
`Query[K,V]` unbounded and preserve the unbounded `Query::at` interface by
capturing the required dictionary in the private Query recipe created at the
Region boundary.

**Keep until:** K1 alpha is superseded or a durable ADR is separately
authorized.

**Disposition:** Accepted K1.2 implementation evidence. K1.2 is accepted at
implementation head `12ec2404b676ef7864e353aeb3681c0fef6f20e3` and merged as
squash commit `db2ac77ac0362a7c5ff8d20887868cbdbb635aa8`. K1.3 is accepted and
merged as squash commit `5657cfc99734c9ac9e7093dd71819d6a0c48df87`. This
K1.2 probe authorizes no cutoff interface or spelling. The separate K1.4
compile probe selected that generated-interface delta. K1.4 is accepted at
implementation/validation head `0036bdd199a685823b6769bf1acdac3f9b6b9014`,
finalized at status-only head `c88e724383ca5f3e817f30226a9fa23cf3ad7358`,
and merged as squash commit `9d53d51d6ec6e282b8aa247442ee126acfe64a2d`.

Hosted acceptance passed 46/46, public diff review was APPROVE, maintainer
acceptance was PASS, and squash-tree equivalence passed. CodeRabbit skipped
content review and is not positive evidence; independent public review supplies
review evidence. K1.5 is implementation complete and maintainer accepted at
validated review-fix head `378df40f7b84e1b6a3ebdb7f32299e2d628f1d54`;
PR #480 merge is pending. This probe authorizes no proof-loss or eviction
interface.

## Reproduction identity

```text
Exact base: 0c5ae4e50622f55b288aa536722e3ac77a71e030
moon:       0.1.20260713 (75c7e1f)
moonc:      0.10.4+ade96c819
Feature:    NEW_MOON_MOD=0
Binary SHA: 5cce093c6795211fcade5e5ff697d88ec4ff416d2785197f004188aca724a753
Core SHA:   e2bf3cc765412055242384fb72a618b62ad4889eae11956251ff921839d022d2
Artifact:   scripts/probe-incr-next-k1-2-key-bound.sh
```

Run from the repository root:

```bash
./scripts/probe-incr-next-k1-2-key-bound.sh
```

The retained script downloads the repository CI's pinned binary and core
archives directly, verifies their recorded SHA-256 digests, and asserts the
reported toolchain version. It contains all three probe modules, requires error
`3002` for the type-bound candidate, verifies the fixed base commit, creates a
detached worktree for the consumer check, prints the generated-interface delta,
asserts the kernel and differential test counts, and removes its temporary
worktree on exit.

## Core API evidence

The pinned MoonBit toolchain reports:

```text
Map::Map       [K : Hash + Eq, V]
Map::get       [K : Hash + Eq, V]
Map::set       [K : Hash + Eq, V]
Map::default   [K, V]
```

`Hash` and `Eq` are separate Self-based core traits. `Unit`, `Int`, tuples whose
members satisfy the traits, and `Array[T]` where `T` satisfies the traits all
implement both. The actual K1.1 callers use `Unit`, `(Int, Int)`, and
`Array[Int]`, so adding the selected constructor bound compiles for every
current caller.

`Map`, `Hash`, and `Eq` are reused. `Map::default` was checked but does not
remove the operation-level bounds required by lookup and insertion. A linear
search would conceal the public key contract and abandon the commissioned typed
Map. A global erased key registry would weaken type ownership and violate the
K1.2 boundary.

## Generated-interface comparison

The three isolated modules retained in the reproduction script exercise real
Map construction, lookup, and insertion. Each viable variant stores the trait
capability at the public seam where it is available.

### Bound on `Region::query`

```text
pub struct Query[K, V]
pub fn[K, V] Query::at(Self[K, V], K) -> View[V]
pub fn[K : Hash + Eq, V] Region::query(Self, (K) -> V) -> Query[K, V]
```

This variant compiled. It creates the typed Map and the private key-to-View
recipe while the bound is available. Generic consumers can hold a Query and
call `Query::at` without repeating the bound.

### Bound on `Query::at`

```text
pub struct Query[K, V]
pub fn[K : Hash + Eq, V] Query::at(Self[K, V], K) -> View[V]
pub fn[K, V] Region::query(Self, (K) -> V) -> Query[K, V]
```

This variant compiled by creating an unbound empty Map and deferring bounded
operations until `Query::at`. It permits constructing a Query whose key cannot
produce a View and pushes the intrinsic Query-key requirement onto every
generic View constructor, so it was rejected.

### Bound on `Query[K,V]`

```text
pub struct Query[K : Hash + Eq, V]
```

The pinned compiler rejected this syntax with error `3002`: generic struct type
parameters cannot carry this trait bound. MoonBit expresses the requirement on
functions that use the capability.

## Existing-consumer probe

The reproduction script creates a detached checkout at the recorded base,
changes only the current `Region::query` signature, and regenerates its
interface. The sole public delta is:

```text
-pub fn[K, V] Region::query(...)
+pub fn[K : Hash + Eq, V] Region::query(...)
```

The existing K1.1 kernel tests passed `26/26`; differential tests passed `5/5`.
The temporary no-memo body warned that the bounds were unused, as expected; the
warning disappears when K1.2 constructs and accesses its typed Map.

## Caller contract

Two keys share a memo exactly when the selected `Hash` and `Eq` implementations
place them in the same Map entry. Hash and equality behavior, including all
mutable state they observe, must remain stable for as long as any View or memo
can retain the key. The kernel does not defensively copy generic keys.

The K1.1 mutable-`Array[Int]` key counterexample compiles because arrays provide
`Hash` and `Eq`, but mutating the array after View construction violates the new
stability contract. K1.2 must replace its post-mutation behavioral expectation
with an explicit contract-violation counterexample before accepting typed memo
behavior.

## Selected public interface

```text
pub struct Query[K, V]
pub fn[K, V] Query::at(Self[K, V], K) -> View[V]
pub fn[K : Hash + Eq, V] Region::query(
  Self,
  (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError]
```

The private QueryCore owns `Map[K,MemoEntry[V]]`. `Region::query` constructs the
core and a private recipe closure while the trait capability is available;
`Query::at` only captures a key through that recipe. This keeps the public
delta to one constructor bound and preserves View opacity.
