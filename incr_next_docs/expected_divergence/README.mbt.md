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

## Structural failure converted to a successful fallback

Query callbacks must propagate Structural Failure transparently. Catching one
and returning a successful fallback can install a memo without the failed edge.

```mbt check
///|
test "incr next expected divergence: hidden structural failure severs recovery" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let cycle_enabled = region.source(false)
  let recursive : Ref[@incr_next.View[Int]?] = Ref(None)
  let unstable = region.derived(ctx => {
    if ctx.get(cycle_enabled.view()) {
      ctx.get(recursive.val.unwrap())
    } else {
      10
    }
  })
  recursive.val = Some(unstable)
  let hides_failure = region.derived(ctx => {
    ctx.get(unstable) catch { _error => 77 }
  })

  assert_eq(store.get(hides_failure), 10)
  ignore((store.transaction(tx => {
    tx.set(cycle_enabled, true)
    Ok(())
  }) : Result[Unit, Unit]))
  let cycle : Result[Int, @incr_next.ReadError] = Ok(store.get(unstable)) catch {
    error => Err(error)
  }
  assert_true(cycle is Err(@incr_next.ReadError::Cycle(_)))
  assert_eq(store.get(hides_failure), 77)
  ignore((store.transaction(tx => {
    tx.set(cycle_enabled, false)
    Ok(())
  }) : Result[Unit, Unit]))
  assert_eq(store.get(unstable), 10)
  assert_eq(store.get(hides_failure), 77)
  region.close()
}
```

## Unsound type-owned cutoff

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
  let region = store.region()
  let input = region.source(10)
  let target = region.derived(
    ctx => LocalStep::{ value: ctx.get(input.view()) },
    cutoff=@incr_next.Cutoff::type_owned(),
  )
  let downstream = region.derived(ctx => ctx.get(target).value)

  assert_eq(store.get(downstream), 10)
  ignore((store.transaction(tx => {
    tx.set(input, 11)
    Ok(())
  }) : Result[Unit, Unit]))
  assert_eq(store.get(downstream), 10)
  ignore((store.transaction(tx => {
    tx.set(input, 12)
    Ok(())
  }) : Result[Unit, Unit]))
  assert_eq(store.get(downstream), 10)
  assert_eq(store.get(target).value, 12)
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
Sources, and sound `Eq` or `CutoffEq` relations.
