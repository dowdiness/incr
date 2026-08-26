///|
fn cycle_diagnostic(error : Result[Int, ReadError]) -> Diagnostic {
  match error {
    Err(ReadError::Cycle(diagnostic)) => diagnostic
    _ => abort("expected Cycle")
  }
}

///|
test "direct self-cycle returns an actionable diagnostic" {
  let store = Store::Store()
  let region = store.region()
  let query_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let query = region.query((ctx, _unit : Unit) => {
    ctx.get(query_ref.val.unwrap().view(()))
  })

  query_ref.val = Some(query)
  let diagnostic = cycle_diagnostic(
    Ok(store.get(query.view(()))) catch {
      error => Err(error)
    },
  )
  assert_true(diagnostic.message().contains("cycle_test.mbt"))
  assert_true(diagnostic.help() is Some(_))
}

///|
test "mutual cycle returns the invocation path" {
  let store = Store::Store()
  let region = store.region()
  let a_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let b_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let a = region.query((ctx, _unit : Unit) => {
    ctx.get(b_ref.val.unwrap().view(()))
  })

  let b = region.query((ctx, _unit : Unit) => {
    ctx.get(a_ref.val.unwrap().view(()))
  })

  a_ref.val = Some(a)
  b_ref.val = Some(b)
  let diagnostic = cycle_diagnostic(
    Ok(store.get(a.view(()))) catch {
      error => Err(error)
    },
  )
  assert_true(diagnostic.message().length() > 0)
}

///|
test "same Query key cycle uses Query equality" {
  let store = Store::Store()
  let region = store.region()
  let query_ref : Ref[Query[Int, Int]?] = Ref(None)
  let query = region.query((ctx, key : Int) => {
    let next = if key == 0 { 1 } else { 0 }
    ctx.get(query_ref.val.unwrap().view(next))
  })

  query_ref.val = Some(query)
  let diagnostic = cycle_diagnostic(
    Ok(store.get(query.view(0))) catch {
      error => Err(error)
    },
  )
  assert_true(diagnostic.message().length() > 0)
}

///|
test "finite keyed recursion succeeds" {
  let store = Store::Store()
  let region = store.region()
  let query_ref : Ref[Query[Int, Int]?] = Ref(None)
  let query = region.query((ctx, key : Int) => {
    if key == 0 {
      0
    } else {
      ctx.get(query_ref.val.unwrap().view(key - 1))
    }
  })

  query_ref.val = Some(query)
  assert_eq(Ok(store.get(query.view(3))) catch { error => Err(error) }, Ok(0))
}

///|
test "unequal-key cross Query recursion succeeds" {
  let store = Store::Store()
  let region = store.region()
  let a_ref : Ref[Query[Int, Int]?] = Ref(None)
  let b_ref : Ref[Query[Int, Int]?] = Ref(None)
  let a = region.query((ctx, key : Int) => {
    if key == 0 {
      ctx.get(b_ref.val.unwrap().view(0))
    } else {
      key
    }
  })

  let b = region.query((ctx, key : Int) => {
    if key == 0 {
      ctx.get(a_ref.val.unwrap().view(1))
    } else {
      key
    }
  })

  a_ref.val = Some(a)
  b_ref.val = Some(b)
  assert_eq(Ok(store.get(a.view(0))) catch { error => Err(error) }, Ok(1))
}

///|
test "dead cycle branch succeeds without entering the cycle" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(0)
  let query_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let query = region.query((ctx, _unit : Unit) => {
    let value = ctx.get(source.view())
    if value == 0 {
      value
    } else {
      ctx.get(query_ref.val.unwrap().view(()))
    }
  })

  query_ref.val = Some(query)
  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(0))
}

///|
test "sequential duplicate read does not form a cycle" {
  let store = Store::Store()
  let region = store.region()
  let child = region.query((_ctx, _unit : Unit) => 0)
  let child_view = child.view(())
  let parent = region.query((ctx, _unit : Unit) => {
    ctx.get(child_view) + ctx.get(child_view)
  })

  assert_eq(Ok(store.get(parent.view(()))) catch { error => Err(error) }, Ok(0))
}
