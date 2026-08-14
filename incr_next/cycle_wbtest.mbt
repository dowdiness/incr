///|
test "active entries and the root stack are empty after a Cycle" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let captured = Ref(None)
  let query_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      captured.val = Some(ctx)
      ctx.read(query_ref.val.unwrap().at(()))
    })
    .unwrap()
  query_ref.val = Some(query)
  assert_true(store.read(query.at(())) is Err(ReadError::Cycle(_)))
  assert_true(query.core.active.is_empty())
  assert_true(captured.val.unwrap().session.active_stack.is_empty())
}

///|
test "active entries and the root stack are empty after finite success" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let captured = Ref(None)
  let query_ref : Ref[Query[Int, Int]?] = Ref(None)
  let query = region
    .query((ctx, key : Int) => {
      captured.val = Some(ctx)
      if key == 0 {
        Ok(0)
      } else {
        ctx.read(query_ref.val.unwrap().at(key - 1))
      }
    })
    .unwrap()
  query_ref.val = Some(query)
  assert_eq(store.read(query.at(3)), Ok(0))
  assert_true(query.core.active.is_empty())
  assert_true(captured.val.unwrap().session.active_stack.is_empty())
}

///|
test "Region close clears active invocation state" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let query = region.query((_ctx, key : Int) => Ok(key)).unwrap()
  query.core.active.set(7, 0)
  assert_true(region.close() is Ok(_))
  assert_true(query.core.active.is_empty())
  assert_true(query.core.memo.is_empty())
  assert_true(query.core.compute.val is None)
}

///|
priv struct ProbeKey {
  value : Int
  hashes : Ref[Int]
  equals : Ref[Int]
}

///|
impl Eq for ProbeKey with fn equal(self, other) -> Bool {
  self.equals.val = self.equals.val + 1
  self.value == other.value
}

///|
impl Hash for ProbeKey with fn hash(self) {
  self.hashes.val = self.hashes.val + 1
  self.value.hash()
}

///|
impl Hash for ProbeKey with fn hash_combine(self, hasher) {
  self.hashes.val = self.hashes.val + 1
  self.value.hash_combine(hasher)
}

///|
test "closed metadata rejects before caller key Hash or Eq" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let key = ProbeKey::{ value: 3, hashes: Ref(0), equals: Ref(0) }
  let query = region.query((_ctx, key : ProbeKey) => Ok(key.value)).unwrap()
  let view = query.at(key)
  ignore(region.close())
  assert_true(store.read(view) is Err(ReadError::ClosedRegion(..)))
  assert_eq(key.hashes.val, 0)
  assert_eq(key.equals.val, 0)
}
