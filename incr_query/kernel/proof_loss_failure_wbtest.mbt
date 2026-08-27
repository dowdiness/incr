///|
test "proof loss failure recovery gets a new memo identity" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region()
  let foreign_region = foreign_store.region()
  let source = region.source(0)
  let foreign = foreign_region.source(9)
  let fail = Ref(false)
  let captured = Ref(None)
  let query = region.query((ctx, _key : Unit) => {
    captured.val = Some(ctx)
    let value = ctx.get(source.view())
    if fail.val {
      ctx.get(foreign.view())
    } else {
      value
    }
  })

  let view = query.view(())
  assert_eq(store.get(view), 0)
  let first = query.core.memo.get(()).unwrap().memo_id
  assert_true(query.drop_memo_evidence(()) is Ok(_))
  fail.val = true
  assert_true(
    (Ok(store.get(view)) catch { error => Err(error) }) is Err(CrossStore(_)),
  )
  assert_true(query.core.memo.is_empty())
  assert_true(query.core.active.is_empty())
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(captured.val.unwrap().session.active_stack.is_empty())
  fail.val = false
  assert_eq(store.get(view), 0)
  assert_true(query.core.memo.get(()).unwrap().memo_id != first)
  foreign_region.close()
  region.close()
}
