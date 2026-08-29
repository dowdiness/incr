///|
fn evaluation_limit_fixture(
  store : Store,
) -> (Source[Int], Query[Unit, Int], Query[Unit, Int], Query[Unit, Int]) raise {
  let region = store.region()
  let source = region.source(1)
  let first = region.query((ctx, _unit : Unit) => ctx.get(source.view()) + 1)
  let second = region.query((ctx, _unit : Unit) => ctx.get(first.view(())) + 1)
  let third = region.query((ctx, _unit : Unit) => ctx.get(second.view(())) + 1)
  (source, first, second, third)
}

///|
test "Store evaluation limit accepts its exact active Query bound" {
  let store = Store::Store(max_active_queries=2U)
  let (_, _, second, _) = evaluation_limit_fixture(store)

  assert_eq(store.get(second.view(())), 3)
}

///|
test "Store evaluation limit rejects the next nested Query and cleans up" {
  let store = Store::Store(max_active_queries=2U)
  let (source, first, second, third) = evaluation_limit_fixture(store)

  assert_true(
    (Ok(store.get(third.view(()))) catch { error => Err(error) })
    is Err(ReadError::EvaluationLimitExceeded(_)),
  )
  assert_true(first.core.active.is_empty())
  assert_true(second.core.active.is_empty())
  assert_true(third.core.active.is_empty())
  assert_true(first.core.memo.is_empty())
  assert_true(second.core.memo.is_empty())
  assert_true(third.core.memo.is_empty())
  assert_eq(store.get(source.view()), 1)
  assert_eq(store.get(second.view(())), 3)
}

///|
test "zero active Queries still permits Source roots" {
  let store = Store::Store(max_active_queries=0U)
  let (source, first, _, _) = evaluation_limit_fixture(store)

  assert_eq(store.get(source.view()), 1)
  assert_true(
    (Ok(store.get(first.view(()))) catch { error => Err(error) })
    is Err(ReadError::EvaluationLimitExceeded(_)),
  )
}

///|
test "Cycle detection takes precedence over the evaluation limit" {
  let store = Store::Store(max_active_queries=1U)
  let region = store.region()
  let recursive : Ref[View[Int]?] = Ref(None)
  let query = region.query((ctx, _unit : Unit) => {
    ctx.get(recursive.val.unwrap())
  })
  recursive.val = Some(query.view(()))

  assert_true(
    (Ok(store.get(query.view(()))) catch { error => Err(error) })
    is Err(ReadError::Cycle(_)),
  )
  assert_true(query.core.active.is_empty())
  assert_true(query.core.memo.is_empty())
}
