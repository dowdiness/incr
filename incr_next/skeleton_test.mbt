///|
test "a new Store reads its initial Source value" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(1)
  assert_eq(store.get(source.view()), 1)
}
