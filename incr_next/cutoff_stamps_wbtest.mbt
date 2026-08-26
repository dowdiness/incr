///|
priv struct SemanticStamp {
  value : Int
  marker : Int
}

///|
impl CutoffEq for SemanticStamp with fn cutoff_equal(self, other) {
  self.value == other.value
}

///|
test "Eq changed preserves identity and advances both stamps" {
  let store = Store::Store()
  let region = store.region()
  let trigger = region.source(0)
  let query = region.query(
    (ctx, _unit : Unit) => ctx.get(trigger.view()),
    cutoff=Cutoff::equal(),
  )

  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(0))
  let before = query.core.memo.get(()).unwrap()
  ignore(
    (
      store.transaction(tx => {
        tx.set(trigger, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let current = store.change_epoch.val
  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(1))
  let after = query.core.memo.get(()).unwrap()
  assert_eq(after.memo_id, before.memo_id)
  assert_eq(after.value, 1)
  assert_eq(after.verified_at, current)
  assert_eq(after.changed_at, current)
  assert_eq(query.core.cutoff_count.val, 1)
  region.close()
}

///|
test "type-owned equivalent keeps semantic value and changed stamp but refreshes marker" {
  let store = Store::Store()
  let region = store.region()
  let trigger = region.source(0)
  let computes = Ref(0)
  let query = region.query(
    (ctx, _unit : Unit) => {
      computes.val = computes.val + 1
      let marker = ctx.get(trigger.view())
      SemanticStamp::{ value: 7, marker }
    },
    cutoff=Cutoff::type_owned(),
  )

  assert_eq(
    (Ok(store.get(query.view(()))) catch { error => Err(error) }).unwrap().marker,
    0,
  )
  let before = query.core.memo.get(()).unwrap()
  ignore(
    (
      store.transaction(tx => {
        tx.set(trigger, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let current = store.change_epoch.val
  let direct = (Ok(store.get(query.view(()))) catch { error => Err(error) }).unwrap()
  let after = query.core.memo.get(()).unwrap()
  assert_eq(direct.marker, 1)
  assert_eq(after.value.marker, 1)
  assert_eq(after.memo_id, before.memo_id)
  assert_eq(after.verified_at, current)
  assert_eq(after.changed_at, before.changed_at)
  assert_eq(query.core.cutoff_count.val, 1)
  assert_eq(computes.val, 2)
  region.close()
}

///|
test "type-owned changed advances identity stamps while retaining memo id" {
  let store = Store::Store()
  let region = store.region()
  let trigger = region.source(0)
  let query = region.query(
    (ctx, _unit : Unit) => {
      let value = ctx.get(trigger.view())
      SemanticStamp::{ value, marker: value }
    },
    cutoff=Cutoff::type_owned(),
  )

  assert_eq(
    (Ok(store.get(query.view(()))) catch { error => Err(error) }).unwrap().value,
    0,
  )
  let before = query.core.memo.get(()).unwrap()
  ignore(
    (
      store.transaction(tx => {
        tx.set(trigger, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let current = store.change_epoch.val
  assert_eq(
    (Ok(store.get(query.view(()))) catch { error => Err(error) }).unwrap().value,
    1,
  )
  let after = query.core.memo.get(()).unwrap()
  assert_eq(after.memo_id, before.memo_id)
  assert_eq(after.verified_at, current)
  assert_eq(after.changed_at, current)
  assert_eq(query.core.cutoff_count.val, 1)
  region.close()
}
