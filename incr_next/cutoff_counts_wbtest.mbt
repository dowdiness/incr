///|
test "first hit and green verification never call cutoff" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(1)
  let unrelated = region.source(2)
  let query = region.query(
    (ctx, _unit : Unit) => ctx.get(source.view()),
    cutoff=Cutoff::equal(),
  )

  let view = query.view(())
  assert_eq(store.get(view), 1)
  assert_eq(query.core.cutoff_count.val, 0)
  assert_eq(store.get(view), 1)
  assert_eq(query.core.cutoff_count.val, 0)
  ignore(
    (
      store.transaction(tx => {
        tx.set(unrelated, 3)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(store.get(view), 1)
  assert_eq(query.core.cutoff_count.val, 0)
  assert_eq(query.core.green_count.val, 1)
  region.close()
  assert_true(query.core.cutoff.val.mode is AlwaysChanged)
}

///|
test "an initial current Cycle has no target memo or cutoff" {
  let store = Store::Store()
  let region = store.region()
  let view_ref : Ref[View[Int]?] = Ref(None)
  let query = region.query(
    (ctx, _unit : Unit) => ctx.get(view_ref.val.unwrap()),
    cutoff=Cutoff::equal(),
  )

  let view = query.view(())
  view_ref.val = Some(view)
  assert_true(
    (Ok(store.get(view)) catch { error => Err(error) }) is Err(Cycle(_)),
  )
  assert_eq(query.core.cutoff_count.val, 0)
  assert_true(query.core.memo.is_empty())
}
