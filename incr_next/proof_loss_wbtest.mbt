///|
test "proof loss rematerializes a surviving View with a new identity" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(7)
  let query = region.query((ctx, _key : Int) => ctx.get(source.view()))

  let view = query.view(1)
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(7))
  let old = query.core.memo.get(1).unwrap()
  let epoch = store.change_epoch.val
  assert_eq(query.drop_memo_evidence(1), Ok(()))
  assert_true(query.core.memo.get(1) is None)
  assert_eq(store.change_epoch.val, epoch)
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(7))
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
  let region = store.region()
  let query = region.query((_ctx, key : EqualKey) => key.value)
  let first = query.view(EqualKey(3))
  let second = query.view(EqualKey(3))
  assert_eq(Ok(store.get(first)) catch { error => Err(error) }, Ok(3))
  let id = query.core.memo.get(EqualKey(3)).unwrap().memo_id
  assert_eq(query.drop_memo_evidence(EqualKey(99)), Ok(()))
  assert_eq(query.drop_memo_evidence(EqualKey(3)), Ok(()))
  assert_eq(query.drop_memo_evidence(EqualKey(3)), Ok(()))
  assert_true(query.core.memo.is_empty())
  assert_eq(Ok(store.get(second)) catch { error => Err(error) }, Ok(3))
  let new_id = query.core.memo.get(EqualKey(3)).unwrap().memo_id
  assert_true(new_id != id)
  assert_eq(query.drop_memo_evidence(EqualKey(3)), Ok(()))
  assert_eq(query.drop_memo_evidence(EqualKey(4)), Ok(()))
}

///|
test "proof loss preserves unequal-key memo isolation" {
  let store = Store::Store()
  let region = store.region()
  let query = region.query((_ctx, key : Int) => key * 2)
  assert_eq(Ok(store.get(query.view(1))) catch { error => Err(error) }, Ok(2))
  assert_eq(Ok(store.get(query.view(2))) catch { error => Err(error) }, Ok(4))
  let other = query.core.memo.get(2).unwrap().memo_id
  assert_eq(query.drop_memo_evidence(1), Ok(()))
  assert_true(query.core.memo.get(1) is None)
  assert_eq(query.core.memo.get(2).unwrap().memo_id, other)
  assert_eq(Ok(store.get(query.view(2))) catch { error => Err(error) }, Ok(4))
}

///|
test "proof loss rematerialization is initial success before later cutoff" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(2)
  let query = region.query(
    (ctx, _key : Unit) => ctx.get(source.view()),
    cutoff=Cutoff::equal(),
  )

  let view = query.view(())
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(2))
  assert_eq(query.drop_memo_evidence(()), Ok(()))
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(2))
  assert_eq(query.core.cutoff_count.val, 0)
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 2)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(2))
  assert_eq(query.core.cutoff_count.val, 1)
}

///|
test "proof loss rebuilds only the current dynamic child trace" {
  let store = Store::Store()
  let region = store.region()
  let selector = region.source(0)
  let old_source = region.source(10)
  let current_source = region.source(20)
  let child = region.query((ctx, _unit : Unit) => {
    if ctx.get(selector.view()) == 0 {
      ctx.get(old_source.view())
    } else {
      ctx.get(current_source.view())
    }
  })

  let parent = region.query((ctx, _unit : Unit) => ctx.get(child.view(())))

  let parent_view = parent.view(())
  assert_eq(Ok(store.get(parent_view)) catch { error => Err(error) }, Ok(10))
  let old_epoch = store.change_epoch.val
  assert_eq(child.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [
    Source,
    Source,
  ])
  ignore(
    (
      store.transaction(tx => {
        tx.set(selector, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(Ok(store.get(parent_view)) catch { error => Err(error) }, Ok(20))
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
  ignore(
    (
      store.transaction(tx => {
        tx.set(current_source, 21)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let current_publish_epoch = store.change_epoch.val
  assert_eq(Ok(store.get(parent_view)) catch { error => Err(error) }, Ok(21))
  let rebuilt = child.core.memo.get(()).unwrap()
  assert_eq(rebuilt.value, 21)
  assert_eq(rebuilt.verified_at, current_publish_epoch)
  assert_eq(rebuilt.changed_at, current_publish_epoch)
  assert_eq(rebuilt.trace.map(dep => dep.kind), [Source, Source])
  assert_eq(child.core.compute_count.val, child_compute_before_loss + 1)
  assert_eq(parent.core.compute_count.val, parent_compute_before_loss + 1)
  assert_eq(parent.core.red_count.val, parent_red_before_loss + 1)
  let parent_after_current = parent.core.compute_count.val
  match
    (
      store.transaction(tx => {
        tx.set(old_source, 11)
        Ok(())
      }) : Result[Unit, Unit]) {
    Ok(_) => ()
    Err(_) => abort("valid proof-loss publication failed unexpectedly")
  }
  assert_eq(Ok(store.get(parent_view)) catch { error => Err(error) }, Ok(21))
  assert_eq(child.core.compute_count.val, child_compute_before_loss + 1)
  assert_eq(parent.core.compute_count.val, parent_after_current)
  ignore(
    (
      store.transaction(tx => {
        tx.set(current_source, 22)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(Ok(store.get(parent_view)) catch { error => Err(error) }, Ok(22))
  assert_eq(child.core.compute_count.val, child_compute_before_loss + 2)
  assert_true(store.change_epoch.val > old_epoch)
}

///|
test "proof loss does not invalidate same-epoch parent but later epoch recomputes" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(1)
  let child = region.query((ctx, _key : Unit) => ctx.get(source.view()))

  let parent = region.query((ctx, _key : Unit) => ctx.get(child.view(())))

  let view = parent.view(())
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(1))
  assert_eq(child.drop_memo_evidence(()), Ok(()))
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(1))
  assert_true(child.core.memo.is_empty())
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(1))
  assert_eq(child.core.memo.length(), 1)
  assert_eq(parent.core.compute_count.val, 2)
}

///|
test "proof loss failure and cycle do not install stale fallback" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region()
  let foreign_region = foreign_store.region()
  let source = region.source(0)
  let foreign = foreign_region.source(9)
  let fail = Ref(false)
  let captured = Ref(None)
  let query = region.query((ctx, _key : Unit) => {
    captured.val = Some(ctx)
    let value = ctx.get(source.view())
    if fail.val {
      ctx.get(foreign.view())
    } else {
      value
    }
  })

  let view = query.view(())
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(0))
  assert_eq(query.drop_memo_evidence(()), Ok(()))
  fail.val = true
  assert_true(
    (Ok(store.get(view)) catch { error => Err(error) }) is Err(CrossStore(_)),
  )
  assert_true(query.core.memo.is_empty())
  assert_true(query.core.active.is_empty())
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(captured.val.unwrap().session.active_stack.is_empty())
  fail.val = false
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(0))
  assert_eq(query.core.memo.get(()).unwrap().memo_id.value, 1)
  foreign_region.close()
  region.close()
}

///|
test "proof loss current cycle cleans active state and recovers" {
  let store = Store::Store()
  let region = store.region()
  let recurse : Ref[View[Int]?] = Ref(None)
  let enabled = Ref(false)
  let captured = Ref(None)
  let query = region.query((ctx, _key : Unit) => {
    captured.val = Some(ctx)
    if enabled.val {
      ctx.get(recurse.val.unwrap())
    } else {
      4
    }
  })

  let view = query.view(())
  recurse.val = Some(view)
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(4))
  assert_eq(query.drop_memo_evidence(()), Ok(()))
  enabled.val = true
  assert_true(
    (Ok(store.get(view)) catch { error => Err(error) }) is Err(Cycle(_)),
  )
  assert_true(query.core.memo.is_empty())
  assert_true(query.core.active.is_empty())
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(captured.val.unwrap().session.active_stack.is_empty())
  enabled.val = false
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(4))
  assert_eq(query.core.memo.get(()).unwrap().memo_id.value, 1)
}

///|
test "proof loss rejects evaluation transaction and closed region" {
  let store = Store::Store()
  let region = store.region()
  let key = ProbeKey::{ value: 3, hashes: Ref(0), equals: Ref(0) }
  let target = region.query((_ctx, key : ProbeKey) => key.value)

  let target_view = target.view(key)
  assert_eq(Ok(store.get(target_view)) catch { error => Err(error) }, Ok(3))
  let before = target.core.memo.get(key).unwrap()
  let before_value = before.value
  let before_id = before.memo_id
  let before_verified_at = before.verified_at
  let before_changed_at = before.changed_at
  let before_trace = before.trace.map(dep => dep.kind)
  key.hashes.val = 0
  key.equals.val = 0
  let before_epoch = store.change_epoch.val
  let seen = Ref(None)
  let blocker = region.query((_ctx, _key : Unit) => {
    seen.val = Some(target.drop_memo_evidence(key))
  })

  assert_eq(
    Ok(store.get(blocker.view(()))) catch {
      error => Err(error)
    },
    Ok(()),
  )
  assert_true(seen.val.unwrap() is Err(MutationDuringEvaluation(_)))
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
  assert_eq(store.change_epoch.val, before_epoch)
  key.hashes.val = 0
  key.equals.val = 0
  seen.val = None
  assert_true(
    (
      store.transaction(_tx => {
        seen.val = Some(target.drop_memo_evidence(key))
        Ok(())
      }) : Result[Unit, Unit])
    is Ok(_),
  )
  assert_true(seen.val.unwrap() is Err(MutationDuringTransaction(_)))
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
  assert_eq(store.change_epoch.val, before_epoch)
  region.close()
  let closed_epoch = store.change_epoch.val
  // The already-closed target must reject before looking at the caller key.
  key.hashes.val = 0
  key.equals.val = 0
  assert_true(target.drop_memo_evidence(key) is Err(ClosedRegion(_)))
  assert_eq(key.hashes.val, 0)
  assert_eq(key.equals.val, 0)
  assert_eq(store.change_epoch.val, closed_epoch)
}
