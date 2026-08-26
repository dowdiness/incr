# Expected caller-contract divergence

**Reader:** Reviewers and advanced consumers who need concrete counterexamples
to the Incr Next caller contract.

**Decision:** Keep caller-contract violations executable and isolated from the
successful guide and independent Fresh conformance.

**Keep until:** Superseded by accepted caller-contract documentation.

**Disposition:** Retained at K2 closure as executable caller-contract warnings.

These tests intentionally violate public caller obligations. Their deterministic
results demonstrate aliasing, hidden structural failure, missing tracking, or
an unsound propagation relation. They are not promised kernel semantics.

## Mutable Query-key meaning

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
  let region = store.region()
  let key = MutableMeaningKey::{ identity: 42, meaning: Ref(10) }
  let query = region.query((_ctx, key : MutableMeaningKey) => key.meaning.val)
  let view = query.view(key)

  assert_eq(store.get(view), 10)
  key.meaning.val = 99
  assert_eq(key.meaning.val, 99)
  assert_eq(store.get(view), 10)
  region.close()
}
```

## Mutable Source payload alias

```mbt check
///|
test "incr next expected divergence: Source payload aliases committed state" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let payload = [4]
  let source = region.source(payload)

  assert_eq(store.get(source.view())[0], 4)
  payload[0] = 8
  assert_eq(store.get(source.view())[0], 8)
  region.close()
}
```

## Mutable memo-result alias

```mbt check
///|
test "incr next expected divergence: returned memo Array aliases cache" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let result = region.derived(_ctx => [6])
  let returned = store.get(result)

  returned[0] = 12
  assert_eq(store.get(result)[0], 12)
  region.close()
}
```

## Untracked mutable state

```mbt check
///|
test "incr next expected divergence: untracked Ref remains stale" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let external = Ref(5)
  let unrelated = region.source(0)
  let value = region.derived(_ctx => external.val)

  assert_eq(store.get(value), 5)
  external.val = 9
  ignore((store.transaction(tx => {
    tx.set(unrelated, 1)
    Ok(())
  }) : Result[Unit, Unit]))
  assert_eq(store.get(value), 5)
  region.close()
}
```

The admissible replacements are immutable values, explicit copies, tracked
Sources, and `Eq` implementations whose equality preserves every downstream observation.
