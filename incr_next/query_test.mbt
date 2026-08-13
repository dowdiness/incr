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
      match ctx.revision() {
        Ok(_) => Ok(1)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(query.at(())), Ok(1))
  let expired = captured.val.unwrap().read(query.at(()))
  assert_true(expired is Err(ReadError::ExpiredQueryContext))
  assert_true(
    captured.val.unwrap().revision() is Err(ReadError::ExpiredQueryContext),
  )
}

///|
test "nested Query gets an invocation lease without expiring its outer callback" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let inner_context = Ref(None)
  let inner = region
    .query((ctx, _unit : Unit) => {
      inner_context.val = Some(ctx)
      Ok(4)
    })
    .unwrap()
  let outer = region
    .query((ctx, _unit : Unit) => {
      let inner_value = ctx.read(inner.at(()))
      let inner_expired = inner_context.val.unwrap().revision()
      match (inner_expired, ctx.revision()) {
        (Err(ReadError::ExpiredQueryContext), Ok(_)) => inner_value
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
        _ => Err(ReadError::ExpiredQueryContext)
      }
    })
    .unwrap()
  assert_eq(store.read(outer.at(())), Ok(4))
}

///|
test "each root captures one committed revision snapshot" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(2).unwrap()
  let captured = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      match ctx.revision() {
        Ok(revision) => {
          captured.val = Some(revision)
          ctx.read(source.view())
        }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(query.at(())), Ok(2))
  let first = captured.val.unwrap()
  assert_eq(first, store.revision())
  ignore(store.transaction(tx => tx.set(source, 3)))
  assert_eq(store.read(query.at(())), Ok(3))
  assert_true(captured.val.unwrap() != first)
}
