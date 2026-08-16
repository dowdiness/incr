///|
test "proof loss failure recovery gets a new memo identity" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region().unwrap()
  let foreign_region = foreign_store.region().unwrap()
  let source = region.source(0).unwrap()
  let foreign = foreign_region.source(9).unwrap()
  let fail = Ref(false)
  let captured = Ref(None)
  let query = region
    .query((ctx, _key : Unit) => {
      captured.val = Some(ctx)
      match ctx.read(source.view()) {
        Ok(_value) if fail.val => ctx.read(foreign.view())
        Ok(value) => Ok(value)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = query.at(())
  assert_eq(store.read(view), Ok(0))
  let first = query.core.memo.get(()).unwrap().memo_id
  assert_eq(query.drop_memo_evidence(()), Ok(()))
  fail.val = true
  assert_true(store.read(view) is Err(CrossStore(..)))
  assert_true(query.core.memo.is_empty())
  assert_true(query.core.active.is_empty())
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(captured.val.unwrap().session.active_stack.is_empty())
  fail.val = false
  assert_eq(store.read(view), Ok(0))
  assert_true(query.core.memo.get(()).unwrap().memo_id != first)
  ignore(foreign_region.close())
  ignore(region.close())
}
