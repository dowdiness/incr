///|
test "heterogeneous multi-region transaction commits atomically" {
  let store = Store::Store()
  let left = store.region().unwrap()
  let right = store.region().unwrap()
  let a = left.source(1).unwrap()
  let b = right.source(2).unwrap()
  let blocked = Ref(false)
  let outcome = store.transaction(tx => {
    ignore(tx.set(a, 10))
    blocked.val = store.read(a.view())
      is Err(ReadError::ReadDuringTransaction(..))
    ignore(tx.set(b, 20))
    Ok(())
  })
  assert_eq(outcome, Ok(store.revision()))
  assert_true(blocked.val)
  assert_eq(store.read(a.view()), Ok(10))
  assert_eq(store.read(b.view()), Ok(20))
  assert_eq(store.revision().value(), 1)
}

///|
test "empty and equal transactions have the specified clock deltas" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(4).unwrap()
  let empty = store.transaction(_tx => Ok(()))
  assert_eq(empty, Ok(store.revision()))
  assert_eq(store.revision().value(), 0)
  let equal = store.transaction(tx => tx.set(source, 4))
  assert_eq(equal, Ok(store.revision()))
  assert_eq(store.revision().value(), 1)
}

///|
test "ignored invalid set poisons and rolls back all writes" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(5).unwrap()
  let other = Store::Store()
  let other_region = other.region().unwrap()
  let foreign = other_region.source(8).unwrap()
  let result = store.transaction(tx => {
    ignore(tx.set(source, 9))
    ignore(tx.set(foreign, 10))
    Ok(())
  })
  assert_true(result is Err(TransactionError::CrossStore(..)))
  assert_eq(store.read(source.view()), Ok(5))
  assert_eq(store.revision().value(), 0)
}

///|
test "sticky poison takes precedence over a callback error" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(5).unwrap()
  let other = Store::Store()
  let other_region = other.region().unwrap()
  let foreign = other_region.source(8).unwrap()
  let result = store.transaction(tx => {
    ignore(tx.set(source, 9))
    ignore(tx.set(foreign, 10))
    Err(TransactionError::CallbackRejected)
  })
  assert_true(result is Err(TransactionError::CrossStore(..)))
  assert_eq(store.read(source.view()), Ok(5))
  assert_eq(store.revision().value(), 0)
}

///|
test "callback failure and transaction capability expiry restore Idle" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(5).unwrap()
  let captured = Ref(None)
  let result = store.transaction(tx => {
    captured.val = Some(tx)
    ignore(tx.set(source, 9))
    Err(TransactionError::CallbackRejected)
  })
  assert_true(result is Err(TransactionError::CallbackRejected))
  assert_eq(store.read(source.view()), Ok(5))
  assert_true(
    captured.val.unwrap().set(source, 10)
    is Err(TransactionError::ExpiredTransaction),
  )
}

///|
test "closed Region set is sticky poison and rolls back the callback" {
  let store = Store::Store()
  let closed = store.region().unwrap()
  let live = store.region().unwrap()
  let closed_source = closed.source(1).unwrap()
  let live_source = live.source(2).unwrap()
  ignore(closed.close())
  let result = store.transaction(tx => {
    ignore(tx.set(live_source, 9))
    ignore(tx.set(closed_source, 8))
    Ok(())
  })
  assert_true(result is Err(TransactionError::ClosedRegion(..)))
  assert_eq(store.read(live_source.view()), Ok(2))
}

///|
test "repeated same-source staging keeps only the last write" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(1).unwrap()
  assert_eq(
    store.transaction(tx => {
      ignore(tx.set(source, 2))
      tx.set(source, 3)
    }),
    Ok(store.revision()),
  )
  assert_eq(store.read(source.view()), Ok(3))
}
