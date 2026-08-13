///|
test "canonical source view and no memo query" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(2).unwrap()
  let source_view = source.view()
  let runs = Ref(0)
  let doubled = region
    .query((ctx, _unit : Unit) => {
      runs.val = runs.val + 1
      match ctx.read(source_view) {
        Ok(value) => Ok(value * 2)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = doubled.at(())
  assert_eq(store.read(view), Ok(4))
  assert_eq(store.read(view), Ok(4))
  assert_eq(runs.val, 2)
  assert_eq(store.revision().value(), 0)
}

///|
test "same store cross region reads and cross store rejection" {
  let store = Store::Store()
  let left = store.region().unwrap()
  let right = store.region().unwrap()
  let source = left.source(7).unwrap()
  let query = right
    .query((ctx, _unit : Unit) => ctx.read(source.view()))
    .unwrap()
  assert_eq(store.read(query.at(())), Ok(7))

  let other = Store::Store()
  let error = other.read(source.view())
  assert_true(error is Err(ReadError::CrossStore(..)))
}

///|
test "query context expires after root callback" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let captured = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      captured.val = Some(ctx)
      Ok(1)
    })
    .unwrap()
  assert_eq(store.read(query.at(())), Ok(1))
  let expired = captured.val.unwrap().read(query.at(()))
  assert_true(expired is Err(ReadError::ExpiredQueryContext))
}
