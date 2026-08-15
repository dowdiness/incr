///|
test "initial Cycle installs no memo and cleans active state" {
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
  assert_true(query.core.memo.is_empty())
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(captured.val.unwrap().session.active_stack.is_empty())
}

///|
test "active check precedes a same-epoch memo hit" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let target = region.query((_ctx, key : Int) => Ok(key)).unwrap()
  assert_eq(store.read(target.at(7)), Ok(7))
  let before = target.core.memo.get(7).unwrap()
  let before_cache_hits = target.core.cache_hit_count.val
  let captured = Ref(None)
  let driver : Query[Unit, Int] = region
    .query((ctx, _unit : Unit) => {
      captured.val = Some(ctx)
      let start = ctx.session.active_stack.length()
      target.core.active.set(7, start)
      ctx.session.active_stack.push(target.core.id)
      let result = ctx.read(target.at(7))
      ignore(ctx.session.active_stack.pop())
      target.core.active.remove(7)
      match result {
        Ok(_) => Err(ReadError::ExpiredQueryContext)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  assert_true(store.read(driver.at(())) is Err(ReadError::Cycle(_)))
  let after = target.core.memo.get(7).unwrap()
  assert_eq(target.core.cache_hit_count.val, before_cache_hits)
  assert_eq(after.value, before.value)
  assert_eq(after.memo_id, before.memo_id)
  assert_eq(after.verified_at, before.verified_at)
  assert_eq(after.changed_at, before.changed_at)
  assert_eq(after.trace.length(), before.trace.length())
  assert_true(target.core.active.is_empty())
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(captured.val.unwrap().session.active_stack.is_empty())
}

///|
test "a Cycle preserves successful memo authority and recovers without caching" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(0).unwrap()
  let query_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let captured = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      captured.val = Some(ctx)
      match ctx.read(source.view()) {
        Ok(value) =>
          if value == 1 {
            ctx.read(query_ref.val.unwrap().at(()))
          } else {
            Ok(value)
          }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  query_ref.val = Some(query)
  let view = query.at(())
  assert_eq(store.read(view), Ok(0))
  let before = query.core.memo.get(()).unwrap()
  let before_value = before.value
  let before_id = before.memo_id
  let before_verified_at = before.verified_at
  let before_changed_at = before.changed_at
  let before_trace_length = before.trace.length()
  let before_trace_kinds = before.trace.map(dep => dep.kind)
  ignore(store.transaction(tx => tx.set(source, 1)))
  let first_cycle_epoch = store.change_epoch.val
  assert_true(store.read(view) is Err(ReadError::Cycle(_)))
  let after_cycle = query.core.memo.get(()).unwrap()
  assert_eq(after_cycle.value, before_value)
  assert_eq(after_cycle.memo_id, before_id)
  assert_eq(after_cycle.verified_at, before_verified_at)
  assert_eq(after_cycle.changed_at, before_changed_at)
  assert_eq(after_cycle.trace.length(), before_trace_length)
  assert_eq(after_cycle.trace.map(dep => dep.kind), before_trace_kinds)
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(query.core.active.is_empty())
  assert_true(captured.val.unwrap().session.active_stack.is_empty())
  let computes_after_first_cycle = query.core.compute_count.val
  assert_true(store.read(view) is Err(ReadError::Cycle(_)))
  assert_eq(query.core.compute_count.val, computes_after_first_cycle + 1)
  assert_eq(query.core.cache_hit_count.val, 0)
  let still_cycle = query.core.memo.get(()).unwrap()
  assert_eq(still_cycle.memo_id, before_id)
  assert_eq(still_cycle.value, before_value)
  assert_eq(still_cycle.verified_at, before_verified_at)
  assert_eq(still_cycle.changed_at, before_changed_at)
  ignore(store.transaction(tx => tx.set(source, 2)))
  let recovery_epoch = store.change_epoch.val
  assert_eq(store.read(view), Ok(2))
  let recovered = query.core.memo.get(()).unwrap()
  assert_eq(recovered.memo_id, before_id)
  assert_eq(recovered.value, 2)
  assert_eq(recovered.trace.map(dep => dep.kind), [Source])
  assert_eq(recovered.verified_at, recovery_epoch)
  assert_eq(recovered.changed_at, recovery_epoch)
  assert_true(recovery_epoch > first_cycle_epoch)
}

///|
test "a Cycle during old-trace verification requests recomputation" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(0).unwrap()
  let a_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let b_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let a = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(source.view()) {
        Ok(value) =>
          if value == 0 {
            Ok(0)
          } else {
            ctx.read(b_ref.val.unwrap().at(()))
          }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let b = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(source.view()) {
        Ok(value) =>
          if value == 0 {
            ctx.read(a_ref.val.unwrap().at(()))
          } else {
            Ok(value)
          }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  a_ref.val = Some(a)
  b_ref.val = Some(b)
  assert_eq(store.read(b.at(())), Ok(0))
  ignore(store.transaction(tx => tx.set(source, 1)))
  assert_eq(store.read(a.at(())), Ok(1))
  assert_true(b.core.unavailable_count.val > 0)
  assert_true(a.core.unavailable_count.val == 0)
  assert_true(a.core.active.is_empty())
  assert_true(b.core.active.is_empty())
}

///|
test "current-recompute Cycle alone reaches the root" {
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
  assert_eq(query.core.unavailable_count.val, 0)
  assert_true(query.core.active.is_empty())
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(captured.val.unwrap().session.active_stack.is_empty())
}

///|
test "Cycle and structural failure leave no active or temporary state" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region().unwrap()
  let foreign_region = foreign_store.region().unwrap()
  let foreign = foreign_region.source(9).unwrap()
  let cycle_captured = Ref(None)
  let cycle_ref : Ref[Query[Unit, Int]?] = Ref(None)
  let cycle_query = region
    .query((ctx, _unit : Unit) => {
      cycle_captured.val = Some(ctx)
      ctx.read(cycle_ref.val.unwrap().at(()))
    })
    .unwrap()
  cycle_ref.val = Some(cycle_query)
  assert_true(store.read(cycle_query.at(())) is Err(ReadError::Cycle(_)))
  assert_true(cycle_query.core.active.is_empty())
  assert_true(cycle_captured.val.unwrap().frame.val is None)
  assert_true(cycle_captured.val.unwrap().session.active_stack.is_empty())
  let error_captured = Ref(None)
  let error_query = region
    .query((ctx, _unit : Unit) => {
      error_captured.val = Some(ctx)
      ctx.read(foreign.view())
    })
    .unwrap()
  assert_true(store.read(error_query.at(())) is Err(ReadError::CrossStore(..)))
  assert_true(error_query.core.active.is_empty())
  assert_true(error_query.core.memo.is_empty())
  assert_true(error_captured.val.unwrap().frame.val is None)
  assert_true(error_captured.val.unwrap().session.active_stack.is_empty())
  ignore(foreign_region.close())
  ignore(region.close())
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
