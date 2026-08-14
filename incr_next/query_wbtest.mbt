///|
test "Region close clears Query memo state" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let query = region.query((_ctx, key : Int) => Ok(key + 1)).unwrap()
  assert_eq(store.read(query.at(4)), Ok(5))
  assert_eq(query.core.memo.length(), 1)
  assert_true(query.core.compute.val is Some(_))
  ignore(region.close())
  assert_true(query.core.memo.is_empty())
  assert_true(query.core.compute.val is None)
}
