///|
test "first hit and green verification never call cutoff" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(1).unwrap()
  let unrelated = region.source(2).unwrap()
  let query = region
    .query_eq((ctx, _unit : Unit) => ctx.read(source.view()))
    .unwrap()
  let view = query.at(())
  assert_eq(store.read(view), Ok(1))
  assert_eq(query.core.cutoff_count.val, 0)
  assert_eq(store.read(view), Ok(1))
  assert_eq(query.core.cutoff_count.val, 0)
  ignore(store.transaction(tx => tx.set(unrelated, 3)))
  assert_eq(store.read(view), Ok(1))
  assert_eq(query.core.cutoff_count.val, 0)
  assert_eq(query.core.green_count.val, 1)
  ignore(region.close())
  assert_true(query.core.cutoff.val is AlwaysChanged)
}

///|
test "an initial current Cycle has no target memo or cutoff" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let view_ref : Ref[View[Int]?] = Ref(None)
  let query = region
    .query_eq((ctx, _unit : Unit) => ctx.read(view_ref.val.unwrap()))
    .unwrap()
  let view = query.at(())
  view_ref.val = Some(view)
  assert_true(store.read(view) is Err(Cycle(_)))
  assert_eq(query.core.cutoff_count.val, 0)
  assert_true(query.core.memo.is_empty())
}
