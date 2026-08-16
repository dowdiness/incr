// Query keys must keep stable semantic meaning while their Views can be read.
// Hash/Eq below use only the immutable identity, so mutating `semantic` leaves
// the memo table valid while demonstrating stale same-epoch memo semantics.

///|
priv struct MutableSemanticKey {
  id : Int
  semantic : Ref[Int]
}

///|
impl Eq for MutableSemanticKey with fn equal(self, other) {
  self.id == other.id
}

///|
impl Hash for MutableSemanticKey with fn hash(self) {
  self.id.hash()
}

///|
impl Hash for MutableSemanticKey with fn hash_combine(self, hasher) {
  self.id.hash_combine(hasher)
}

///|
test "expected divergence: mutable Query-key meaning can outlive a memo" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let key = MutableSemanticKey::{ id: 7, semantic: Ref(1) }
  let query = region
    .query((_ctx, key : MutableSemanticKey) => Ok(key.semantic.val))
    .unwrap()
  let view = query.at(key)
  assert_eq(store.read(view), Ok(1))
  key.semantic.val = 2
  assert_eq(store.read(view), Ok(1))
  assert_eq(key.semantic.val, 2)
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
  ignore(region.close())
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
  ignore(region.close())
}
