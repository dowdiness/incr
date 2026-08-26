///|
test "Region close changes only ChangeEpoch and invalidates surviving Views" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(11)
  let query = region.query((ctx, _unit : Unit) => ctx.get(source.view()))

  let source_view = source.view()
  let query_view = query.view(())
  assert_eq(Ok(store.get(query_view)) catch { error => Err(error) }, Ok(11))
  let close_epoch_before = store.change_epoch.val
  region.close()
  assert_eq(store.change_epoch.val, close_epoch_before + 1)
  assert_true(
    (Ok(store.get(source_view)) catch { error => Err(error) })
    is Err(ReadError::ClosedRegion(_)),
  )
  assert_true(
    (Ok(store.get(query_view)) catch { error => Err(error) })
    is Err(ReadError::ClosedRegion(_)),
  )
  region.close()
  assert_eq(store.change_epoch.val, close_epoch_before + 1)
}

///|
test "sibling Regions remain independent after one closes" {
  let store = Store::Store()
  let first = store.region()
  let second = store.region()
  let first_source = first.source(1)
  let second_source = second.source(2)
  let first_view = first_source.view()
  first.close()
  assert_true(
    (Ok(store.get(first_view)) catch { error => Err(error) })
    is Err(ReadError::ClosedRegion(_)),
  )
  assert_eq(
    Ok(store.get(second_source.view())) catch {
      error => Err(error)
    },
    Ok(2),
  )
  ignore(second.source(3))
}

///|
test "cross Region Source failure is visible to a surviving query View" {
  let store = Store::Store()
  let owner = store.region()
  let dependent = store.region()
  let source = owner.source(12)
  let view = source.view()
  let query = dependent.query((ctx, _unit : Unit) => ctx.get(view))
  let query_view = query.view(())
  assert_eq(Ok(store.get(query_view)) catch { error => Err(error) }, Ok(12))
  owner.close()
  assert_true(
    (Ok(store.get(query_view)) catch { error => Err(error) })
    is Err(ReadError::ClosedRegion(_)),
  )
  ignore(dependent.source(13))
}

///|
test "wrong-phase close is rejected without a ChangeEpoch delta" {
  let store = Store::Store()
  let owner = store.region()
  let other = store.region()
  let before = store.change_epoch.val
  let result = owner.query((ctx, _unit : Unit) => {
    ignore(ctx)
    ignore(Ok(other.close()) catch { error => Err(error) })
    1
  })

  assert_eq(Ok(store.get(result.view(()))) catch { error => Err(error) }, Ok(1))
  assert_eq(store.change_epoch.val, before)
  other.close()
  assert_eq(store.change_epoch.val, before + 1)
}

///|
test "a closed branch can be replaced by a live same-store branch" {
  let store = Store::Store()
  let owner = store.region()
  let dependent = store.region()
  let dead = owner.source(10)
  let flag = dependent.source(0)
  let live = dependent.source(20)
  let query = dependent.query((ctx, _unit : Unit) => {
    if ctx.get(flag.view()) == 0 {
      ctx.get(dead.view())
    } else {
      ctx.get(live.view())
    }
  })

  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(10))
  owner.close()
  ignore(
    (
      store.transaction(tx => {
        tx.set(flag, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(20))
}
