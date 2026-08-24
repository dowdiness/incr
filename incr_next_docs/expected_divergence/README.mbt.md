# Expected caller-contract divergence

**Reader:** Reviewers and advanced consumers who need concrete counterexamples
to the Incr Next caller contract.

**Decision:** Keep caller-contract violations executable and isolated from the
successful guide and independent Fresh conformance.

**Keep until:** The K2 disposition is accepted.

**Disposition:** At K2 closure, retain these examples as warnings or delete
them with the disposition rationale.

**Status:** K2.2 accepted and squash-merged as `9360816f`; K2.3 distribution
evidence accepted and squash-merged as `3007f5ff`; K2.4 disposition is active.

These tests intentionally violate public caller obligations. Their observed
results are deterministic demonstrations of aliasing, missing tracking, or an
unsound propagation relation; they are **expected divergence**, not promised
kernel semantics. This package imports only `dowdiness/incr_next`. It neither
imports nor copies the testkit or Fresh implementation.

## Mutable Query-key meaning

A key's `Hash`, `Eq`, and semantic meaning must remain stable while a View or
memo retains it. Here identity stays stable while aliased meaning changes, so a
same-epoch memo still represents the old meaning.

```mbt check
///|
priv struct MutableMeaningKey {
  identity : Int
  meaning : Ref[Int]
}

///|
impl Eq for MutableMeaningKey with fn equal(self, other) {
  self.identity == other.identity
}

///|
impl Hash for MutableMeaningKey with fn hash(self) {
  self.identity.hash()
}

///|
impl Hash for MutableMeaningKey with fn hash_combine(self, hasher) {
  Hash::hash_combine(self.identity, hasher)
}

///|
test "incr next expected divergence: mutable key meaning stays memoized" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let key = MutableMeaningKey::{ identity: 42, meaning: Ref(10) }
  let query = region
    .query((_ctx, key : MutableMeaningKey) => Ok(key.meaning.val))
    .unwrap()
  let view = query.at(key)

  assert_eq(store.read(view), Ok(10))
  key.meaning.val = 99
  assert_eq(key.meaning.val, 99)
  assert_eq(store.read(view), Ok(10))
  region.close().unwrap()
}
```

## Mutable Source payload alias

Source publication replaces a value; it does not deep-copy an arbitrary value.
Mutating a retained Array alias changes what a later read observes without a
Transaction or Revision advance.

```mbt check
///|
test "incr next expected divergence: Source payload aliases committed state" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let payload = [4]
  let source = region.source(payload).unwrap()

  assert_eq(store.read(source.view()).unwrap()[0], 4)
  assert_eq(store.revision().value(), 0)
  payload[0] = 8
  assert_eq(store.read(source.view()).unwrap()[0], 8)
  assert_eq(store.revision().value(), 0)
  region.close().unwrap()
}
```

## Mutable memo-result alias

A Query result is cached by reference when its value has reference semantics.
Mutating the returned Array changes the cached value observed by a later memo
hit.

```mbt check
///|
test "incr next expected divergence: returned memo Array aliases cache" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let query = region.query((_ctx, _unit : Unit) => Ok([6])).unwrap()
  let view = query.at(())
  let returned = store.read(view).unwrap()

  returned[0] = 12
  assert_eq(store.read(view).unwrap()[0], 12)
  region.close().unwrap()
}
```

## Structural `ReadError` converted to `Ok`

The callback type permits matching a structural error, but the caller contract
requires transparent propagation. The graph below starts with a valid value,
then enters a temporary cycle. The transparent View reports the cycle and
recovers after its Source is repaired. The callback that converts the cycle to
`Ok(77)` instead records a successful memo without the failed dependency, so it
can remain stale after the transparent View recovers. This illustrates one
possible failure mode. Its exact shape is outside the kernel contract.

```mbt check
///|
test "incr next expected divergence: hidden structural error severs recovery" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let cycle_enabled = region.source(false).unwrap()
  let recursive : Ref[@incr_next.View[Int]?] = Ref(None)
  let unstable = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(cycle_enabled.view()) {
        Ok(false) => Ok(10)
        Ok(true) => ctx.read(recursive.val.unwrap())
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let unstable_view = unstable.at(())
  recursive.val = Some(unstable_view)
  let hides_error = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(unstable_view) {
        Ok(value) => Ok(value)
        Err(_) => Ok(77)
      }
    })
    .unwrap()
  let hidden_view = hides_error.at(())

  assert_eq(store.read(hidden_view), Ok(10))
  ignore(store.transaction(tx => tx.set(cycle_enabled, true)).unwrap())
  assert_true(store.read(unstable_view) is Err(@incr_next.ReadError::Cycle(_)))
  assert_eq(store.read(hidden_view), Ok(77))
  ignore(store.transaction(tx => tx.set(cycle_enabled, false)).unwrap())
  assert_eq(store.read(unstable_view), Ok(10))
  assert_eq(store.read(hidden_view), Ok(77))
  region.close().unwrap()
}
```

## Unsound type-owned cutoff

`CutoffEq` must be a propagation equivalence. Local nearness is not transitive:
10 is near 11 and 11 is near 12, but a downstream observation of 10 is not a
valid substitute for 12. The target retains each newest value while downstream
reuse remains stale.

```mbt check
///|
priv struct LocalStep {
  value : Int
}

///|
impl @incr_next.CutoffEq for LocalStep with fn cutoff_equal(self, other) {
  let distance = self.value - other.value
  distance >= -1 && distance <= 1
}

///|
test "incr next expected divergence: non-transitive cutoff stales downstream" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let input = region.source(10).unwrap()
  let target = region
    .query_type_owned((ctx, _unit : Unit) => {
      ctx.read(input.view()).map(value => LocalStep::{ value, })
    })
    .unwrap()
  let downstream = region
    .query((ctx, _unit : Unit) => {
      ctx.read(target.at(())).map(value => value.value)
    })
    .unwrap()

  assert_eq(store.read(downstream.at(())), Ok(10))
  ignore(store.transaction(tx => tx.set(input, 11)).unwrap())
  assert_eq(store.read(downstream.at(())), Ok(10))
  ignore(store.transaction(tx => tx.set(input, 12)).unwrap())
  assert_eq(store.read(downstream.at(())), Ok(10))
  assert_eq(store.read(target.at(())).unwrap().value, 12)
  region.close().unwrap()
}
```

## Untracked mutable state

Reading a `Ref` directly in a Query callback records no dependency. Even an
unrelated publication cannot tell the Query that the `Ref` changed, so its
memo remains the old value.

```mbt check
///|
test "incr next expected divergence: untracked Ref remains stale" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let external = Ref(5)
  let unrelated = region.source(0).unwrap()
  let query = region.query((_ctx, _unit : Unit) => Ok(external.val)).unwrap()
  let view = query.at(())

  assert_eq(store.read(view), Ok(5))
  external.val = 9
  ignore(store.transaction(tx => tx.set(unrelated, 1)).unwrap())
  assert_eq(store.read(view), Ok(5))
  region.close().unwrap()
}
```

The admissible replacements are immutable values, explicit copies, tracked
Sources, and sound `Eq`/`CutoffEq` relations. Reclassify a surprising result as
a kernel defect only after the caller contract is satisfied.
