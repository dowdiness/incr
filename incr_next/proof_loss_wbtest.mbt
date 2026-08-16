///|
test "proof loss rematerializes a surviving View with a new identity" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(7).unwrap()
  let query = region
    .query((ctx, _key : Int) => ctx.read(source.view()))
    .unwrap()
  let view = query.at(1)
  assert_eq(store.read(view), Ok(7))
  let old = query.core.memo.get(1).unwrap()
  let revision = store.revision()
  let epoch = store.change_epoch.val
  assert_eq(query.drop_memo_evidence(1), Ok(()))
  assert_true(query.core.memo.get(1) is None)
  assert_eq(store.revision(), revision)
  assert_eq(store.change_epoch.val, epoch)
  assert_eq(store.read(view), Ok(7))
  let next = query.core.memo.get(1).unwrap()
  assert_true(next.memo_id != old.memo_id)
  assert_eq(next.verified_at, epoch)
  assert_eq(next.changed_at, epoch)
  assert_eq(query.core.cutoff_count.val, 0)
}

///|
struct EqualKey {
  value : Int
}

///|
fn EqualKey::EqualKey(value : Int) -> EqualKey {
  { value, }
}

///|
impl Eq for EqualKey with fn equal(self, other) -> Bool {
  self.value == other.value
}

///|
impl Hash for EqualKey with fn hash(self) {
  self.value.hash()
}

///|
impl Hash for EqualKey with fn hash_combine(self, hasher) {
  self.value.hash_combine(hasher)
}

///|
test "proof loss is equal-key shared, isolated, and absent-safe" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let query = region.query((_ctx, key : EqualKey) => Ok(key.value)).unwrap()
  let first = query.at(EqualKey(3))
  let second = query.at(EqualKey(3))
  assert_eq(store.read(first), Ok(3))
  let id = query.core.memo.get(EqualKey(3)).unwrap().memo_id
  assert_eq(query.drop_memo_evidence(EqualKey(99)), Ok(()))
  assert_eq(query.drop_memo_evidence(EqualKey(3)), Ok(()))
  assert_eq(query.drop_memo_evidence(EqualKey(3)), Ok(()))
  assert_true(query.core.memo.is_empty())
  assert_eq(store.read(second), Ok(3))
  let new_id = query.core.memo.get(EqualKey(3)).unwrap().memo_id
  assert_true(new_id != id)
  assert_eq(query.drop_memo_evidence(EqualKey(3)), Ok(()))
  assert_eq(query.drop_memo_evidence(EqualKey(4)), Ok(()))
}

///|
test "proof loss preserves unequal-key memo isolation" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let query = region.query((_ctx, key : Int) => Ok(key * 2)).unwrap()
  assert_eq(store.read(query.at(1)), Ok(2))
  assert_eq(store.read(query.at(2)), Ok(4))
  let other = query.core.memo.get(2).unwrap().memo_id
  assert_eq(query.drop_memo_evidence(1), Ok(()))
  assert_true(query.core.memo.get(1) is None)
  assert_eq(query.core.memo.get(2).unwrap().memo_id, other)
  assert_eq(store.read(query.at(2)), Ok(4))
}

///|
test "proof loss rematerialization is initial success before later cutoff" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(2).unwrap()
  let query = region
    .query_eq((ctx, _key : Unit) => ctx.read(source.view()))
    .unwrap()
  let view = query.at(())
  assert_eq(store.read(view), Ok(2))
  assert_eq(query.drop_memo_evidence(()), Ok(()))
  assert_eq(store.read(view), Ok(2))
  assert_eq(query.core.cutoff_count.val, 0)
  ignore(store.transaction(tx => tx.set(source, 2)))
  assert_eq(store.read(view), Ok(2))
  assert_eq(query.core.cutoff_count.val, 1)
}

///|
test "proof loss rebuilds only the current dynamic child trace" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let selector = region.source(0).unwrap()
  let old_source = region.source(10).unwrap()
  let current_source = region.source(20).unwrap()
  let child = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(selector.view()) {
        Ok(flag) =>
          if flag == 0 {
            ctx.read(old_source.view())
          } else {
            ctx.read(current_source.view())
          }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let parent = region
    .query((ctx, _unit : Unit) => ctx.read(child.at(())))
    .unwrap()
  let parent_view = parent.at(())
  assert_eq(store.read(parent_view), Ok(10))
  let old_epoch = store.change_epoch.val
  assert_eq(child.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [
    Source,
    Source,
  ])
  ignore(store.transaction(tx => tx.set(selector, 1)))
  assert_eq(store.read(parent_view), Ok(20))
  let new_epoch = store.change_epoch.val
  let current_child = child.core.memo.get(()).unwrap()
  assert_eq(current_child.value, 20)
  assert_eq(current_child.verified_at, new_epoch)
  assert_eq(current_child.changed_at, new_epoch)
  assert_eq(current_child.trace.map(dep => dep.kind), [Source, Source])
  let child_compute_before_loss = child.core.compute_count.val
  let parent_compute_before_loss = parent.core.compute_count.val
  let parent_red_before_loss = parent.core.red_count.val
  assert_eq(child.drop_memo_evidence(()), Ok(()))
  assert_true(child.core.memo.is_empty())
  ignore(store.transaction(tx => tx.set(current_source, 21)))
  let current_publish_epoch = store.change_epoch.val
  assert_eq(store.read(parent_view), Ok(21))
  let rebuilt = child.core.memo.get(()).unwrap()
  assert_eq(rebuilt.value, 21)
  assert_eq(rebuilt.verified_at, current_publish_epoch)
  assert_eq(rebuilt.changed_at, current_publish_epoch)
  assert_eq(rebuilt.trace.map(dep => dep.kind), [Source, Source])
  assert_eq(child.core.compute_count.val, child_compute_before_loss + 1)
  assert_eq(parent.core.compute_count.val, parent_compute_before_loss + 1)
  assert_eq(parent.core.red_count.val, parent_red_before_loss + 1)
  let parent_after_current = parent.core.compute_count.val
  match store.transaction(tx => tx.set(old_source, 11)) {
    Ok(_) => ()
    Err(_) => abort("valid proof-loss publication failed unexpectedly")
  }
  assert_eq(store.read(parent_view), Ok(21))
  assert_eq(child.core.compute_count.val, child_compute_before_loss + 1)
  assert_eq(parent.core.compute_count.val, parent_after_current)
  ignore(store.transaction(tx => tx.set(current_source, 22)))
  assert_eq(store.read(parent_view), Ok(22))
  assert_eq(child.core.compute_count.val, child_compute_before_loss + 2)
  assert_true(store.change_epoch.val > old_epoch)
}

///|
test "proof loss does not invalidate same-epoch parent but later epoch recomputes" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(1).unwrap()
  let child = region
    .query((ctx, _key : Unit) => ctx.read(source.view()))
    .unwrap()
  let parent = region
    .query((ctx, _key : Unit) => ctx.read(child.at(())))
    .unwrap()
  let view = parent.at(())
  assert_eq(store.read(view), Ok(1))
  assert_eq(child.drop_memo_evidence(()), Ok(()))
  assert_eq(store.read(view), Ok(1))
  assert_true(child.core.memo.is_empty())
  ignore(store.transaction(tx => tx.set(source, 1)))
  assert_eq(store.read(view), Ok(1))
  assert_eq(child.core.memo.length(), 1)
  assert_eq(parent.core.compute_count.val, 2)
}

///|
test "proof loss failure and cycle do not install stale fallback" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region().unwrap()
  let foreign_region = foreign_store.region().unwrap()
  let source = region.source(0).unwrap()
  let foreign = foreign_region.source(9).unwrap()
  let fail = Ref(false)
  let captured = Ref(None)
  let query = region
    .query((ctx, _key : Unit) => {
      captured.val = Some(ctx)
      match ctx.read(source.view()) {
        Ok(_value) if fail.val => ctx.read(foreign.view())
        Ok(value) => Ok(value)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = query.at(())
  assert_eq(store.read(view), Ok(0))
  assert_eq(query.drop_memo_evidence(()), Ok(()))
  fail.val = true
  assert_true(store.read(view) is Err(CrossStore(..)))
  assert_true(query.core.memo.is_empty())
  assert_true(query.core.active.is_empty())
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(captured.val.unwrap().session.active_stack.is_empty())
  fail.val = false
  assert_eq(store.read(view), Ok(0))
  assert_eq(query.core.memo.get(()).unwrap().memo_id.value, 1)
  ignore(foreign_region.close())
  ignore(region.close())
}

///|
test "proof loss current cycle cleans active state and recovers" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let recurse : Ref[View[Int]?] = Ref(None)
  let enabled = Ref(false)
  let captured = Ref(None)
  let query = region
    .query((ctx, _key : Unit) => {
      captured.val = Some(ctx)
      if enabled.val {
        ctx.read(recurse.val.unwrap())
      } else {
        Ok(4)
      }
    })
    .unwrap()
  let view = query.at(())
  recurse.val = Some(view)
  assert_eq(store.read(view), Ok(4))
  assert_eq(query.drop_memo_evidence(()), Ok(()))
  enabled.val = true
  assert_true(store.read(view) is Err(Cycle(_)))
  assert_true(query.core.memo.is_empty())
  assert_true(query.core.active.is_empty())
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(captured.val.unwrap().session.active_stack.is_empty())
  enabled.val = false
  assert_eq(store.read(view), Ok(4))
  assert_eq(query.core.memo.get(()).unwrap().memo_id.value, 1)
}

///|
test "proof loss rejects evaluation transaction and closed region" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let key = ProbeKey::{ value: 3, hashes: Ref(0), equals: Ref(0) }
  let target = region
    .query((ctx, key : ProbeKey) => {
      match ctx.revision() {
        Ok(_) => Ok(key.value)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let target_view = target.at(key)
  assert_eq(store.read(target_view), Ok(3))
  let before = target.core.memo.get(key).unwrap()
  let before_value = before.value
  let before_id = before.memo_id
  let before_verified_at = before.verified_at
  let before_changed_at = before.changed_at
  let before_trace = before.trace.map(dep => dep.kind)
  key.hashes.val = 0
  key.equals.val = 0
  let before_revision = store.revision()
  let before_epoch = store.change_epoch.val
  let seen = Ref(None)
  let blocker = region
    .query((_ctx, _key : Unit) => {
      seen.val = Some(target.drop_memo_evidence(key))
      Ok(())
    })
    .unwrap()
  assert_eq(store.read(blocker.at(())), Ok(()))
  assert_true(seen.val.unwrap() is Err(MutationDuringEvaluation(..)))
  assert_eq(key.hashes.val, 0)
  assert_eq(key.equals.val, 0)
  assert_eq(target.core.memo.get(key).unwrap().value, before_value)
  assert_eq(target.core.memo.get(key).unwrap().memo_id, before_id)
  assert_eq(target.core.memo.get(key).unwrap().verified_at, before_verified_at)
  assert_eq(target.core.memo.get(key).unwrap().changed_at, before_changed_at)
  assert_eq(
    target.core.memo.get(key).unwrap().trace.map(dep => dep.kind),
    before_trace,
  )
  assert_eq(store.revision(), before_revision)
  assert_eq(store.change_epoch.val, before_epoch)
  key.hashes.val = 0
  key.equals.val = 0
  seen.val = None
  assert_true(
    store.transaction(_tx => {
      seen.val = Some(target.drop_memo_evidence(key))
      Ok(())
    })
    is Ok(_),
  )
  assert_true(seen.val.unwrap() is Err(MutationDuringTransaction(..)))
  assert_eq(key.hashes.val, 0)
  assert_eq(key.equals.val, 0)
  assert_eq(target.core.memo.get(key).unwrap().value, before_value)
  assert_eq(target.core.memo.get(key).unwrap().memo_id, before_id)
  assert_eq(target.core.memo.get(key).unwrap().verified_at, before_verified_at)
  assert_eq(target.core.memo.get(key).unwrap().changed_at, before_changed_at)
  assert_eq(
    target.core.memo.get(key).unwrap().trace.map(dep => dep.kind),
    before_trace,
  )
  assert_eq(store.revision(), before_revision)
  assert_eq(store.change_epoch.val, before_epoch)
  ignore(region.close())
  let closed_revision = store.revision()
  let closed_epoch = store.change_epoch.val
  // The already-closed target must reject before looking at the caller key.
  key.hashes.val = 0
  key.equals.val = 0
  assert_true(target.drop_memo_evidence(key) is Err(ClosedRegion(..)))
  assert_eq(key.hashes.val, 0)
  assert_eq(key.equals.val, 0)
  assert_eq(store.revision(), closed_revision)
  assert_eq(store.change_epoch.val, closed_epoch)
}
