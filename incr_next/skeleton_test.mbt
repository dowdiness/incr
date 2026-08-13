///|
test "store and region identity skeleton" {
  let store = Store::Store()
  let region = store.region().unwrap()
  assert_true(region.id().store_id() == store.id())
  assert_eq(region.generation().epoch(), 0)
  assert_eq(store.revision().value(), 0)
}
