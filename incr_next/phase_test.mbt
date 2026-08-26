///|
test "evaluation phase rejects root reads and Region mutation globally" {
  let store = Store::Store()
  let region = store.region()
  let other = Store::Store()
  let other_region = other.region()
  let other_source = other_region.source(9)
  let root_error = Ref(None)
  let region_error = Ref(None)
  let transaction_error = Ref(None)
  let close_error = Ref(None)
  let query = region.query((ctx, _unit : Unit) => {
    root_error.val = Some(
      Ok(other.get(other_source.view())) catch {
        error => Err(error)
      },
    )
    region_error.val = Some(Ok(other.region()) catch { error => Err(error) })
    transaction_error.val = Some(
      Ok((other.transaction(_tx => Ok(())) : Result[Unit, Unit])) catch {
        error => Err(error)
      },
    )
    close_error.val = Some(
      Ok(other_region.close()) catch {
        error => Err(error)
      },
    )
    ignore(ctx)
    1
  })

  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(1))
  assert_true(root_error.val.unwrap() is Err(ReadError::ReentrantRootGet(_)))
  assert_true(
    region_error.val.unwrap() is Err(RegionError::MutationDuringEvaluation(_)),
  )
  assert_true(
    transaction_error.val.unwrap()
    is Err(TransactionError::TransactionDuringEvaluation(_)),
  )
  assert_true(
    close_error.val.unwrap() is Err(RegionError::MutationDuringEvaluation(_)),
  )
  other_region.close()
}

///|
test "Query structural failure restores Idle for root Region and transaction" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(1)
  let other = Store::Store()
  let other_region = other.region()
  let foreign = other_region.source(2)
  let query = region.query((ctx, _unit : Unit) => ctx.get(foreign.view()))

  assert_true(
    (Ok(store.get(query.view(()))) catch { error => Err(error) })
    is Err(ReadError::CrossStore(_)),
  )
  assert_eq(Ok(other.get(foreign.view())) catch { error => Err(error) }, Ok(2))
  ignore(other.region())
  assert_eq((other.transaction(_tx => Ok(())) : Result[Unit, Unit]), Ok(()))
  ignore(source)
}

///|
test "phase is restored after catchable root rejection" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(3)
  let query = region.query((ctx, _unit : Unit) => ctx.get(source.view()))

  let first = Ok(store.get(query.view(()))) catch { error => Err(error) }
  let second = Ok(store.get(source.view())) catch { error => Err(error) }
  assert_eq(first, Ok(3))
  assert_eq(second, Ok(3))
}
