///|
fn cycle_path(error : Result[Int, ReadError]) -> Array[Int] {
  match error {
    Err(ReadError::Cycle(witness)) => witness.path()
    _ => abort("expected Cycle")
  }
}

///|
test "direct self-cycle returns a copied witness" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let query_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => ctx.read(query_ref.val.unwrap().at(())))
    .unwrap()
  query_ref.val = Some(query)
  let error = store.read(query.at(()))
  match error {
    Err(ReadError::Cycle(witness)) => {
      let path = witness.path()
      path[0] = -1
      assert_eq(witness.path()[0], witness.path()[1])
    }
    _ => abort("expected Cycle")
  }
  let path = cycle_path(error)
  assert_eq(path.length(), 2)
  assert_eq(path[0], path[1])
}

///|
test "mutual cycle returns the invocation path" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let a_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let b_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let a = region
    .query((ctx, _unit : Unit) => ctx.read(b_ref.val.unwrap().at(())))
    .unwrap()
  let b = region
    .query((ctx, _unit : Unit) => ctx.read(a_ref.val.unwrap().at(())))
    .unwrap()
  a_ref.val = Some(a)
  b_ref.val = Some(b)
  let path = cycle_path(store.read(a.at(())))
  assert_eq(path.length(), 3)
  assert_true(path[0] != path[1])
  assert_eq(path[0], path[2])
}

///|
test "same Query key cycle uses Query equality" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let query_ref : Ref[Query[Int, Int]?] = Ref(None)
  let query = region
    .query((ctx, key : Int) => {
      let next = if key == 0 { 1 } else { 0 }
      ctx.read(query_ref.val.unwrap().at(next))
    })
    .unwrap()
  query_ref.val = Some(query)
  let path = cycle_path(store.read(query.at(0)))
  assert_eq(path.length(), 3)
  assert_eq(path[0], path[1])
  assert_eq(path[1], path[2])
}

///|
test "finite keyed recursion succeeds" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let query_ref : Ref[Query[Int, Int]?] = Ref(None)
  let query = region
    .query((ctx, key : Int) => {
      if key == 0 {
        Ok(0)
      } else {
        ctx.read(query_ref.val.unwrap().at(key - 1))
      }
    })
    .unwrap()
  query_ref.val = Some(query)
  assert_eq(store.read(query.at(3)), Ok(0))
}

///|
test "unequal-key cross Query recursion succeeds" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let a_ref : Ref[Query[Int, Int]?] = Ref(None)
  let b_ref : Ref[Query[Int, Int]?] = Ref(None)
  let a = region
    .query((ctx, key : Int) => {
      if key == 0 {
        ctx.read(b_ref.val.unwrap().at(0))
      } else {
        Ok(key)
      }
    })
    .unwrap()
  let b = region
    .query((ctx, key : Int) => {
      if key == 0 {
        ctx.read(a_ref.val.unwrap().at(1))
      } else {
        Ok(key)
      }
    })
    .unwrap()
  a_ref.val = Some(a)
  b_ref.val = Some(b)
  assert_eq(store.read(a.at(0)), Ok(1))
}

///|
test "dead cycle branch succeeds without entering the cycle" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(0).unwrap()
  let query_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(source.view()) {
        Ok(value) =>
          if value == 0 {
            Ok(value)
          } else {
            ctx.read(query_ref.val.unwrap().at(()))
          }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  query_ref.val = Some(query)
  assert_eq(store.read(query.at(())), Ok(0))
}

///|
test "sequential duplicate read does not form a cycle" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let child = region.query((_ctx, _unit : Unit) => Ok(0)).unwrap()
  let child_view = child.at(())
  let parent = region
    .query((ctx, _unit : Unit) => {
      match (ctx.read(child_view), ctx.read(child_view)) {
        (Ok(left), Ok(right)) => Ok(left + right)
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(parent.at(())), Ok(0))
}
