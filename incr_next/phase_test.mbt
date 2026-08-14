///|
test "evaluation phase rejects root reads and Region mutation globally" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let other = Store::Store()
  let other_region = other.region().unwrap()
  let other_source = other_region.source(9).unwrap()
  let root_error = Ref(None)
  let region_error = Ref(None)
  let transaction_error = Ref(None)
  let close_error = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      root_error.val = Some(other.read(other_source.view()))
      region_error.val = Some(other.region())
      transaction_error.val = Some(other.transaction(_tx => Ok(())))
      close_error.val = Some(other_region.close())
      match ctx.revision() {
        Ok(_) => Ok(1)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(query.at(())), Ok(1))
  assert_true(root_error.val.unwrap() is Err(ReadError::ReentrantRootRead(..)))
  assert_true(
    region_error.val.unwrap() is Err(RegionError::MutationDuringEvaluation(..)),
  )
  assert_true(
    transaction_error.val.unwrap()
    is Err(TransactionError::TransactionDuringEvaluation(..)),
  )
  assert_true(
    close_error.val.unwrap() is Err(RegionError::MutationDuringEvaluation(..)),
  )
  assert_true(other_region.close() is Ok(_))
}

///|
test "Query callback Err restores Idle for root Region and transaction" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(1).unwrap()
  let other = Store::Store()
  let other_region = other.region().unwrap()
  let query : Query[Unit, Unit] = region
    .query((_ctx, _unit : Unit) => Err(ReadError::ExpiredQueryContext))
    .unwrap()
  assert_true(store.read(query.at(())) is Err(ReadError::ExpiredQueryContext))
  assert_eq(other.read(other_region.source(2).unwrap().view()), Ok(2))
  assert_true(other.region() is Ok(_))
  assert_true(other.transaction(_tx => Ok(())) is Ok(_))
  ignore(source)
}

///|
test "phase is restored after catchable root rejection" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(3).unwrap()
  let query = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(source.view()) {
        Ok(value) => Ok(value)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let first = store.read(query.at(()))
  let second = store.read(source.view())
  assert_eq(first, Ok(3))
  assert_eq(second, Ok(3))
}
