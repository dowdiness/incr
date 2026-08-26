///|
test "heterogeneous multi-region transaction commits atomically" {
  let store = Store::Store()
  let left = store.region()
  let right = store.region()
  let a = left.source(1)
  let b = right.source(2)
  let blocked = Ref(false)
  let outcome : Result[String, String] = store.transaction(tx => {
    tx.set(a, 10)
    blocked.val = (Ok(store.get(a.view())) catch { error => Err(error) })
      is Err(ReadError::GetDuringTransaction(_))
    tx.set(b, 20)
    Ok("committed")
  })
  assert_eq(outcome, Ok("committed"))
  assert_true(blocked.val)
  assert_eq(store.get(a.view()), 10)
  assert_eq(store.get(b.view()), 20)
}

///|
test "empty and equal transactions commit normally" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(4)
  let empty : Result[Unit, Unit] = store.transaction(_tx => Ok(()))
  assert_eq(empty, Ok(()))
  let equal : Result[Unit, Unit] = store.transaction(tx => {
    tx.set(source, 4)
    Ok(())
  })
  assert_eq(equal, Ok(()))
  assert_eq(store.get(source.view()), 4)
}

///|
test "invalid set raises and rolls back all writes" {
  let store = Store::Store()
  let source = store.region().source(5)
  let other = Store::Store()
  let foreign = other.region().source(8)
  let result : Result[Result[Unit, String], TransactionError] = Ok(
    store.transaction(tx => {
      tx.set(source, 9)
      tx.set(foreign, 10)
      Ok(())
    }),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(TransactionError::CrossStore(_)))
  assert_eq(store.get(source.view()), 5)
}

///|
test "sticky poison takes precedence over caught set failure" {
  let store = Store::Store()
  let source = store.region().source(5)
  let other = Store::Store()
  let foreign = other.region().source(8)
  let result : Result[Result[Unit, String], TransactionError] = Ok(
    store.transaction(tx => {
      tx.set(source, 9)
      ignore(Ok(tx.set(foreign, 10)) catch { error => Err(error) })
      Err("domain rejection")
    }),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(TransactionError::CrossStore(_)))
  assert_eq(store.get(source.view()), 5)
}

///|
test "domain rejection rolls back and transaction capability expires" {
  let store = Store::Store()
  let source = store.region().source(5)
  let captured = Ref(None)
  let result : Result[Unit, String] = store.transaction(tx => {
    captured.val = Some(tx)
    tx.set(source, 9)
    Err("domain rejection")
  })
  assert_eq(result, Err("domain rejection"))
  assert_eq(store.get(source.view()), 5)
  let expired : Result[Unit, TransactionError] = Ok(
    captured.val.unwrap().set(source, 10),
  ) catch {
    error => Err(error)
  }
  assert_true(expired is Err(TransactionError::ExpiredTransaction(_)))
}

///|
test "closed Region set raises and rolls back the callback" {
  let store = Store::Store()
  let closed = store.region()
  let live = store.region()
  let closed_source = closed.source(1)
  let live_source = live.source(2)
  closed.close()
  let result : Result[Result[Unit, String], TransactionError] = Ok(
    store.transaction(tx => {
      tx.set(live_source, 9)
      tx.set(closed_source, 8)
      Ok(())
    }),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(TransactionError::ClosedRegion(_)))
  assert_eq(store.get(live_source.view()), 2)
}

///|
test "repeated same-source staging keeps only the last write" {
  let store = Store::Store()
  let source = store.region().source(1)
  let result : Result[Unit, Unit] = store.transaction(tx => {
    tx.set(source, 2)
    tx.set(source, 3)
    Ok(())
  })
  assert_eq(result, Ok(()))
  assert_eq(store.get(source.view()), 3)
}
