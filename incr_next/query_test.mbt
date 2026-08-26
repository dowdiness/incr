///|
struct EqKey {
  value : Int
} derive(Eq, Hash)

///|
fn EqKey::EqKey(value : Int) -> EqKey {
  { value, }
}

///|
test "Store get returns a value and raises structural failure" {
  let store = Store::Store()
  let source = store.region().source(2)
  assert_eq(store.get(source.view()), 2)

  let other = Store::Store()
  let cross_store : Result[Int, ReadError] = Ok(other.get(source.view())) catch {
    error => Err(error)
  }
  assert_true(cross_store is Err(ReadError::CrossStore(_)))
}

///|
test "Region derived returns one tracked View" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(2)
  let runs = Ref(0)
  let doubled = region.derived(ctx => {
    runs.val = runs.val + 1
    ctx.get(source.view()) * 2
  })

  assert_eq(store.get(doubled), 4)
  assert_eq(store.get(doubled), 4)
  assert_eq(runs.val, 1)
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 3)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(store.get(doubled), 6)
  assert_eq(runs.val, 2)
}

///|
test "Derived Value cutoff is an optional policy" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(2)
  let parity = region.derived(
    ctx => ctx.get(source.view()) % 2,
    cutoff=Cutoff::equal(),
  )
  let downstream_runs = Ref(0)
  let downstream = region.derived(ctx => {
    downstream_runs.val = downstream_runs.val + 1
    ctx.get(parity) + 10
  })

  assert_eq(store.get(downstream), 10)
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 4)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(store.get(downstream), 10)
  assert_eq(downstream_runs.val, 1)
}

///|
test "canonical source view and memoized query" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(2)
  let source_view = source.view()
  let runs = Ref(0)
  let doubled = region.query((ctx, _unit : Unit) => {
    runs.val = runs.val + 1
    ctx.get(source_view) * 2
  })

  let view = doubled.view(())
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(4))
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(4))
  assert_eq(runs.val, 1)
}

///|
test "same store cross region reads and cross store rejection" {
  let store = Store::Store()
  let left = store.region()
  let right = store.region()
  let source = left.source(7)
  let query = right.query((ctx, _unit : Unit) => ctx.get(source.view()))

  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(7))

  let other = Store::Store()
  let error = Ok(other.get(source.view())) catch { error => Err(error) }
  assert_true(error is Err(ReadError::CrossStore(_)))
}

///|
test "query context expires after root callback" {
  let store = Store::Store()
  let region = store.region()
  let captured = Ref(None)
  let query = region.query((ctx, _unit : Unit) => {
    captured.val = Some(ctx)
    1
  })

  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(1))
  let expired : Result[Int, ReadError] = Ok(
    captured.val.unwrap().get(query.view(())),
  ) catch {
    error => Err(error)
  }
  assert_true(expired is Err(ReadError::ExpiredQueryContext(_)))
}

///|
test "nested Query gets an invocation lease without expiring its outer callback" {
  let store = Store::Store()
  let region = store.region()
  let inner_context = Ref(None)
  let inner = region.query((ctx, _unit : Unit) => {
    inner_context.val = Some(ctx)
    4
  })

  let outer = region.query((ctx, _unit : Unit) => {
    let inner_value = ctx.get(inner.view(()))
    let expired : Result[Int, ReadError] = Ok(
      inner_context.val.unwrap().get(inner.view(())),
    ) catch {
      error => Err(error)
    }
    match expired {
      Err(ReadError::ExpiredQueryContext(_)) => inner_value
      Err(error) => raise error
      Ok(_) => abort("inner QueryContext remained live")
    }
  })

  assert_eq(Ok(store.get(outer.view(()))) catch { error => Err(error) }, Ok(4))
}

///|
test "domain failure is a Query value, not a structural read error" {
  let store = Store::Store()
  let region = store.region()
  let query = region.query((_ctx, _unit : Unit) => {
    let value : Result[Int, String] = Err("domain")
    value
  })

  assert_eq(
    Ok(store.get(query.view(()))) catch {
      error => Err(error)
    },
    Ok(Err("domain")),
  )
}

///|
test "nested structural errors remain in the outer read channel" {
  let store = Store::Store()
  let region = store.region()
  let other = Store::Store()
  let other_region = other.region()
  let foreign = other_region.source(9)
  let query = region.query((ctx, _unit : Unit) => ctx.get(foreign.view()))

  assert_true(
    (Ok(store.get(query.view(()))) catch { error => Err(error) })
    is Err(ReadError::CrossStore(_)),
  )
}

///|
test "same ChangeEpoch reuses a Query memo" {
  let store = Store::Store()
  let region = store.region()
  let computes = Ref(0)
  let query = region.query((_ctx, key : Int) => {
    computes.val = computes.val + 1
    key + 10
  })

  assert_eq(Ok(store.get(query.view(1))) catch { error => Err(error) }, Ok(11))
  assert_eq(Ok(store.get(query.view(1))) catch { error => Err(error) }, Ok(11))
  assert_eq(computes.val, 1)
}

///|
test "Eq-equal Query keys share one memo" {
  let store = Store::Store()
  let region = store.region()
  let computes = Ref(0)
  let query = region.query((_ctx, key : EqKey) => {
    computes.val = computes.val + 1
    key.value
  })

  assert_eq(
    Ok(store.get(query.view(EqKey(7)))) catch {
      error => Err(error)
    },
    Ok(7),
  )
  assert_eq(
    Ok(store.get(query.view(EqKey(7)))) catch {
      error => Err(error)
    },
    Ok(7),
  )
  assert_eq(computes.val, 1)
}

///|
test "different QueryCores isolate equal keys" {
  let store = Store::Store()
  let region = store.region()
  let left_computes = Ref(0)
  let right_computes = Ref(0)
  let left = region.query((_ctx, key : Int) => {
    left_computes.val = left_computes.val + 1
    key + 1
  })

  let right = region.query((_ctx, key : Int) => {
    right_computes.val = right_computes.val + 1
    key + 2
  })

  assert_eq(Ok(store.get(left.view(3))) catch { error => Err(error) }, Ok(4))
  assert_eq(Ok(store.get(right.view(3))) catch { error => Err(error) }, Ok(5))
  assert_eq(Ok(store.get(left.view(3))) catch { error => Err(error) }, Ok(4))
  assert_eq(Ok(store.get(right.view(3))) catch { error => Err(error) }, Ok(5))
  assert_eq(left_computes.val, 1)
  assert_eq(right_computes.val, 1)
}

///|
test "a new ChangeEpoch recomputes a Query memo" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(2)
  let computes = Ref(0)
  let query = region.query((ctx, _unit : Unit) => {
    computes.val = computes.val + 1
    ctx.get(source.view())
  })

  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(2))
  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(2))
  assert_eq(computes.val, 1)
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 3)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(3))
  assert_eq(computes.val, 2)
}
