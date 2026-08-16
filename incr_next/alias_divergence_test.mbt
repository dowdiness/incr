// Query keys must keep stable Hash/Eq behavior while their Views can be read.
// The K1.2 memo retains each key; mutable-key behavior is therefore a caller
// contract, not an executable post-mutation expectation.

///|
priv struct MutableKey {
  value : Ref[Int]
}

///|
impl Eq for MutableKey with fn equal(self, other) {
  self.value.val == other.value.val
}

///|
impl Hash for MutableKey with fn hash(self) {
  self.value.val.hash()
}

///|
impl Hash for MutableKey with fn hash_combine(self, hasher) {
  self.value.val.hash_combine(hasher)
}

///|
test "expected divergence: mutable Query keys are excluded after mutation" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let key = MutableKey::{ value: Ref(1) }
  let query = region
    .query((_ctx, key : MutableKey) => Ok(key.value.val))
    .unwrap()
  let view = query.at(key)
  assert_eq(store.read(view), Ok(1))
  key.value.val = 2
  // No post-mutation read is asserted: stable Hash/Eq is the caller contract.
  assert_eq(key.value.val, 2)
  ignore(region.close())
}

///|
test "expected divergence: Source payload aliases are caller-owned" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let payload = [1]
  let source = region.source(payload).unwrap()
  let view = source.view()
  assert_eq(store.read(view).unwrap()[0], 1)
  payload[0] = 2
  assert_eq(store.read(view).unwrap()[0], 2)
}

///|
test "expected divergence: Query results are not defensively copied" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let result = Ref([1])
  let query = region.query((_ctx, _unit : Unit) => Ok(result.val)).unwrap()
  let view = query.at(())
  let returned = store.read(view).unwrap()
  returned[0] = 3
  assert_eq(store.read(view).unwrap()[0], 3)
}
