///|
test "store and region start with a zero committed revision" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(1).unwrap()
  assert_eq(store.revision().value(), 0)
  assert_eq(store.read(source.view()), Ok(1))
}
