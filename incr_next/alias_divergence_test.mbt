// Query keys must keep stable Hash/Eq behavior while their Views can be read.
// The K1.2 memo retains each key; mutable-key behavior is therefore a caller
// contract, not an executable post-mutation expectation.

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
