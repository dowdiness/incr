///|
test "Eq changed preserves identity and advances both stamps" {
  let store = Store::Store()
  let region = store.region()
  let trigger = region.source(0)
  let query = region.query(
    (ctx, _unit : Unit) => ctx.get(trigger.view()),
    cutoff=Cutoff::equal(),
  )

  assert_eq(store.get(query.view(())), 0)
  let before = query.core.memo.get(()).unwrap()
  ignore(
    (
      store.transaction(tx => {
        tx.set(trigger, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let current = store.change_epoch.val
  assert_eq(store.get(query.view(())), 1)
  let after = query.core.memo.get(()).unwrap()
  assert_eq(after.memo_id, before.memo_id)
  assert_eq(after.value, 1)
  assert_eq(after.verified_at, current)
  assert_eq(after.changed_at, current)
  assert_eq(query.core.cutoff_count.val, 1)
  region.close()
}
