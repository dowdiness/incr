///|
test "a shared diamond has one inner kernel computation" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(0).unwrap()
  let shared = region
    .query((ctx, _key : (Int, Int)) => ctx.read(source.view()))
    .unwrap()
  let left = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(shared.at((0, 0))) {
        Ok(value) => Ok(value + 1)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let right = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(shared.at((0, 0))) {
        Ok(value) => Ok(value + 2)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let root = region
    .query((ctx, _unit : Unit) => {
      match (ctx.read(left.at(())), ctx.read(right.at(()))) {
        (Ok(a), Ok(b)) => Ok(a + b)
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(root.at(())), Ok(3))
  assert_eq(root.core.compute_count.val, 1)
  assert_eq(left.core.compute_count.val, 1)
  assert_eq(right.core.compute_count.val, 1)
  assert_eq(shared.core.compute_count.val, 1)
  assert_eq(shared.core.cache_hit_count.val, 1)
  assert_eq(shared.core.memo.length(), 1)
  assert_eq(shared.core.memo.get((0, 0)).unwrap().trace.map(dep => dep.kind), [
    Source,
  ])
  assert_eq(left.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [Query])
  assert_eq(right.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [Query])
  assert_eq(root.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [
    Query,
    Query,
  ])
  assert_eq(store.read(root.at(())), Ok(3))
  assert_eq(root.core.compute_count.val, 1)
  assert_eq(shared.core.compute_count.val, 1)
  assert_eq(shared.core.cache_hit_count.val, 1)
}

///|
test "memo hits, identity, and epoch stamps are white-box observable" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(2).unwrap()
  let query = region
    .query((ctx, _key : Int) => ctx.read(source.view()))
    .unwrap()
  assert_eq(store.read(query.at(7)), Ok(2))
  assert_eq(query.core.memo.length(), 1)
  assert_eq(query.core.compute_count.val, 1)
  assert_eq(query.core.cache_hit_count.val, 0)
  let before = query.core.memo.get(7).unwrap()
  assert_eq(before.verified_at, store.change_epoch.val)
  assert_eq(before.changed_at, store.change_epoch.val)
  assert_eq(store.read(query.at(7)), Ok(2))
  assert_eq(query.core.compute_count.val, 1)
  assert_eq(query.core.cache_hit_count.val, 1)
  let memo_id = query.core.memo.get(7).unwrap().memo_id
  ignore(store.transaction(tx => tx.set(source, 3)))
  let current_epoch = store.change_epoch.val
  assert_eq(store.read(query.at(7)), Ok(3))
  let after = query.core.memo.get(7).unwrap()
  assert_eq(query.core.compute_count.val, 2)
  assert_eq(query.core.cache_hit_count.val, 1)
  assert_eq(after.memo_id, memo_id)
  assert_true(after.verified_at > before.verified_at)
  assert_true(after.changed_at > before.changed_at)
  assert_eq(after.verified_at, current_epoch)
  assert_eq(after.changed_at, current_epoch)
}

///|
test "successful memos own direct Source Query and Revision traces" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(1).unwrap()
  let source_query = region
    .query((ctx, _unit : Unit) => ctx.read(source.view()))
    .unwrap()
  let revision_query = region
    .query((ctx, _unit : Unit) => {
      match ctx.revision() {
        Ok(_) => Ok(2)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let child_query = region
    .query((ctx, _unit : Unit) => ctx.read(source_query.at(())))
    .unwrap()
  let root_query = region
    .query((ctx, _unit : Unit) => {
      match (ctx.read(child_query.at(())), ctx.read(revision_query.at(()))) {
        (Ok(left), Ok(right)) => Ok(left + right)
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(source_query.at(())), Ok(1))
  assert_eq(store.read(revision_query.at(())), Ok(2))
  assert_eq(store.read(child_query.at(())), Ok(1))
  assert_eq(store.read(root_query.at(())), Ok(3))
  assert_eq(
    source_query.core.memo.get(()).unwrap().trace.map(dep => dep.kind),
    [Source],
  )
  assert_eq(
    revision_query.core.memo.get(()).unwrap().trace.map(dep => dep.kind),
    [Revision],
  )
  assert_eq(child_query.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [
    Query,
  ])
  assert_eq(root_query.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [
    Query,
    Query,
  ])
}

///|
test "initial failure releases its temporary trace" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(1).unwrap()
  let captured = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      captured.val = Some(ctx)
      let outcome : Result[Unit, ReadError] = match ctx.read(source.view()) {
        Ok(_) => Err(ReadError::ExpiredQueryContext)
        Err(error) => Err(error)
      }
      outcome
    })
    .unwrap()
  assert_eq(store.read(query.at(())), Err(ReadError::ExpiredQueryContext))
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(query.core.memo.is_empty())
}

///|
test "initial structural failure installs no memo, then recovery installs first ID" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region().unwrap()
  let foreign_region = foreign_store.region().unwrap()
  let source = region.source(1).unwrap()
  let foreign = foreign_region.source(9).unwrap()
  let fail_now = Ref(true)
  let captured = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      captured.val = Some(ctx)
      match ctx.read(source.view()) {
        Ok(value) =>
          if fail_now.val {
            match ctx.read(foreign.view()) {
              Ok(_) => Ok(value)
              Err(error) => Err(error)
            }
          } else {
            Ok(value)
          }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = query.at(())
  assert_true(store.read(view) is Err(CrossStore(..)))
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(query.core.memo.is_empty())
  // The callback is changed only after the failed frame has been released.
  fail_now.val = false
  assert_eq(store.read(view), Ok(1))
  assert_eq(query.core.memo.get(()).unwrap().memo_id.value, 0)
  ignore(foreign_region.close())
  ignore(region.close())
}

///|
test "failed recompute returns current error and preserves successful authority" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region().unwrap()
  let foreign_region = foreign_store.region().unwrap()
  let source = region.source(0).unwrap()
  let foreign = foreign_region.source(9).unwrap()
  let captured = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      captured.val = Some(ctx)
      match ctx.read(source.view()) {
        Ok(value) if value == 1 => ctx.read(foreign.view())
        Ok(value) => Ok(value)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = query.at(())
  assert_eq(store.read(view), Ok(0))
  let before = query.core.memo.get(()).unwrap()
  let before_kinds = before.trace.map(dep => dep.kind)
  let before_id = before.memo_id
  let before_value = before.value
  let before_verified_at = before.verified_at
  let before_changed_at = before.changed_at
  ignore(store.transaction(tx => tx.set(source, 1)))
  assert_true(store.read(view) is Err(CrossStore(..)))
  assert_true(captured.val.unwrap().frame.val is None)
  let after = query.core.memo.get(()).unwrap()
  assert_eq(after.memo_id, before_id)
  assert_eq(after.value, before_value)
  assert_eq(after.trace.length(), before.trace.length())
  assert_eq(after.trace.map(dep => dep.kind), before_kinds)
  assert_eq(after.verified_at, before_verified_at)
  assert_eq(after.changed_at, before_changed_at)
  ignore(foreign_region.close())
  ignore(region.close())
}

///|
test "failed recompute recovers with the same memo identity" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region().unwrap()
  let foreign_region = foreign_store.region().unwrap()
  let source = region.source(0).unwrap()
  let foreign = foreign_region.source(9).unwrap()
  let captured = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      captured.val = Some(ctx)
      match ctx.read(source.view()) {
        Ok(value) if value == 1 => ctx.read(foreign.view())
        Ok(value) => Ok(value)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = query.at(())
  assert_eq(store.read(view), Ok(0))
  let memo_id = query.core.memo.get(()).unwrap().memo_id
  ignore(store.transaction(tx => tx.set(source, 1)))
  assert_true(store.read(view) is Err(CrossStore(..)))
  assert_true(captured.val.unwrap().frame.val is None)
  ignore(store.transaction(tx => tx.set(source, 2)))
  let current_epoch = store.change_epoch.val
  assert_eq(store.read(view), Ok(2))
  let after = query.core.memo.get(()).unwrap()
  assert_eq(after.memo_id, memo_id)
  assert_eq(after.value, 2)
  assert_eq(after.trace.length(), 1)
  assert_eq(after.trace.map(dep => dep.kind), [Source])
  assert_eq(after.verified_at, current_epoch)
  assert_eq(after.changed_at, current_epoch)
  ignore(foreign_region.close())
  ignore(region.close())
}

///|
test "successful child recompute remains installed when parent fails" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region().unwrap()
  let foreign_region = foreign_store.region().unwrap()
  let source = region.source(0).unwrap()
  let foreign = foreign_region.source(9).unwrap()
  let child = region
    .query((ctx, _unit : Unit) => ctx.read(source.view()))
    .unwrap()
  let captured = Ref(None)
  let parent = region
    .query((ctx, _unit : Unit) => {
      captured.val = Some(ctx)
      match ctx.read(child.at(())) {
        Ok(value) if value == 1 => ctx.read(foreign.view())
        Ok(value) => Ok(value + 10)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = parent.at(())
  assert_eq(store.read(view), Ok(10))
  let before = parent.core.memo.get(()).unwrap()
  let before_id = before.memo_id
  let before_value = before.value
  let before_verified_at = before.verified_at
  let before_changed_at = before.changed_at
  ignore(store.transaction(tx => tx.set(source, 1)))
  assert_true(store.read(view) is Err(CrossStore(..)))
  assert_true(captured.val.unwrap().frame.val is None)
  let child_after = child.core.memo.get(()).unwrap()
  assert_eq(child_after.value, 1)
  assert_eq(child.core.compute_count.val, 2)
  let parent_after = parent.core.memo.get(()).unwrap()
  assert_eq(parent_after.memo_id, before_id)
  assert_eq(parent_after.value, before_value)
  assert_eq(parent_after.trace.length(), 1)
  assert_eq(parent_after.trace.map(dep => dep.kind), [Query])
  assert_eq(parent_after.verified_at, before_verified_at)
  assert_eq(parent_after.changed_at, before_changed_at)
  ignore(foreign_region.close())
  ignore(region.close())
}

///|
test "unrelated publication green-verifies without recompute" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let selected = region.source(2).unwrap()
  let unrelated = region.source(9).unwrap()
  let query = region
    .query((ctx, _unit : Unit) => ctx.read(selected.view()))
    .unwrap()
  assert_eq(store.read(query.at(())), Ok(2))
  let before = query.core.memo.get(()).unwrap()
  ignore(store.transaction(tx => tx.set(unrelated, 10)))
  let current = store.change_epoch.val
  assert_eq(store.read(query.at(())), Ok(2))
  let after = query.core.memo.get(()).unwrap()
  assert_eq(query.core.compute_count.val, 1)
  assert_eq(query.core.verification_count.val, 1)
  assert_eq(query.core.green_count.val, 1)
  assert_eq(query.core.red_count.val, 0)
  assert_eq(query.core.dependency_check_count.val, 1)
  assert_eq(query.core.unavailable_count.val, 0)
  assert_eq(after.memo_id, before.memo_id)
  assert_eq(after.value, before.value)
  assert_eq(after.trace.length(), 1)
  assert_eq(after.verified_at, current)
  assert_eq(after.changed_at, before.changed_at)
}

///|
test "selected publication red-recomputes and replaces the value" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(2).unwrap()
  let query = region
    .query((ctx, _unit : Unit) => ctx.read(source.view()))
    .unwrap()
  assert_eq(store.read(query.at(())), Ok(2))
  let before = query.core.memo.get(()).unwrap()
  ignore(store.transaction(tx => tx.set(source, 7)))
  let current = store.change_epoch.val
  assert_eq(store.read(query.at(())), Ok(7))
  let after = query.core.memo.get(()).unwrap()
  assert_eq(query.core.compute_count.val, 2)
  assert_eq(query.core.verification_count.val, 1)
  assert_eq(query.core.green_count.val, 0)
  assert_eq(query.core.red_count.val, 1)
  assert_eq(query.core.dependency_check_count.val, 1)
  assert_eq(query.core.unavailable_count.val, 0)
  assert_eq(after.memo_id, before.memo_id)
  assert_eq(after.value, 7)
  assert_eq(after.trace.length(), 1)
  assert_eq(after.verified_at, current)
  assert_eq(after.changed_at, current)
}

///|
test "a selected diamond child verifies or computes once per epoch" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(0).unwrap()
  let unrelated = region.source(5).unwrap()
  let shared = region
    .query((ctx, _key : Unit) => ctx.read(source.view()))
    .unwrap()
  let left = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(shared.at(())) {
        Ok(value) => Ok(value + 1)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let right = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(shared.at(())) {
        Ok(value) => Ok(value + 2)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let root = region
    .query((ctx, _unit : Unit) => {
      match (ctx.read(left.at(())), ctx.read(right.at(()))) {
        (Ok(a), Ok(b)) => Ok(a + b)
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(root.at(())), Ok(3))
  ignore(store.transaction(tx => tx.set(source, 4)))
  assert_eq(store.read(root.at(())), Ok(11))
  assert_eq(shared.core.compute_count.val, 2)
  assert_eq(shared.core.verification_count.val, 1)
  assert_eq(shared.core.green_count.val, 0)
  assert_eq(shared.core.red_count.val, 1)
  assert_eq(shared.core.dependency_check_count.val, 1)
  assert_eq(left.core.compute_count.val, 2)
  assert_eq(right.core.compute_count.val, 2)
  assert_eq(root.core.compute_count.val, 2)
  assert_eq(shared.core.cache_hit_count.val, 4)
  ignore(store.transaction(tx => tx.set(unrelated, 6)))
  assert_eq(store.read(root.at(())), Ok(11))
  assert_eq(shared.core.verification_count.val, 2)
  assert_eq(shared.core.green_count.val, 1)
  assert_eq(shared.core.red_count.val, 1)
  assert_eq(shared.core.dependency_check_count.val, 2)
  assert_eq(shared.core.compute_count.val, 2)
  assert_eq(shared.core.cache_hit_count.val, 5)
}

///|
test "child verification does not append an old trace to its parent" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(1).unwrap()
  let unrelated = region.source(2).unwrap()
  let child = region
    .query((ctx, _unit : Unit) => ctx.read(source.view()))
    .unwrap()
  let parent = region
    .query((ctx, _unit : Unit) => ctx.read(child.at(())))
    .unwrap()
  assert_eq(store.read(parent.at(())), Ok(1))
  ignore(store.transaction(tx => tx.set(unrelated, 8)))
  assert_eq(store.read(parent.at(())), Ok(1))
  assert_eq(child.core.memo.get(()).unwrap().trace.length(), 1)
  assert_eq(parent.core.memo.get(()).unwrap().trace.length(), 1)
  assert_eq(child.core.verification_count.val, 1)
  assert_eq(parent.core.verification_count.val, 1)
}

///|
test "dynamic trace replacement drops the old branch" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let branch = region.source(0).unwrap()
  let old_branch = region.source(4).unwrap()
  let query = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(branch.view()) {
        Ok(flag) =>
          if flag == 0 {
            ctx.read(old_branch.view())
          } else {
            Ok(flag)
          }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(query.at(())), Ok(4))
  assert_eq(query.core.memo.get(()).unwrap().trace.length(), 2)
  ignore(store.transaction(tx => tx.set(branch, 9)))
  assert_eq(store.read(query.at(())), Ok(9))
  assert_eq(query.core.memo.get(()).unwrap().trace.length(), 1)
  ignore(store.transaction(tx => tx.set(old_branch, 12)))
  assert_eq(store.read(query.at(())), Ok(9))
  assert_eq(query.core.compute_count.val, 2)
  assert_eq(query.core.verification_count.val, 2)
  assert_eq(query.core.green_count.val, 1)
  assert_eq(query.core.red_count.val, 1)
  assert_eq(query.core.dependency_check_count.val, 3)
  assert_eq(query.core.unavailable_count.val, 0)
}

///|
test "Revision-only Query is green across another Region close" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let other = store.region().unwrap()
  let source = region.source(8).unwrap()
  let query = region
    .query((ctx, _unit : Unit) => {
      match ctx.revision() {
        Ok(_) => Ok(3)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(query.at(())), Ok(3))
  let before_revision = store.revision()
  ignore(other.close())
  assert_eq(store.revision(), before_revision)
  assert_eq(store.read(query.at(())), Ok(3))
  assert_eq(query.core.compute_count.val, 1)
  assert_eq(query.core.verification_count.val, 1)
  assert_eq(query.core.green_count.val, 1)
  ignore(store.transaction(tx => tx.set(source, 8)))
  assert_eq(store.read(query.at(())), Ok(3))
  assert_eq(query.core.compute_count.val, 2)
  assert_eq(query.core.red_count.val, 1)
}

///|
test "all dependencies are checked when a closed cross Region branch is avoided" {
  let store = Store::Store()
  let live = store.region().unwrap()
  let old = store.region().unwrap()
  let selector = live.source(0).unwrap()
  let old_source = old.source(4).unwrap()
  let query = live
    .query((ctx, _unit : Unit) => {
      match ctx.read(selector.view()) {
        Ok(flag) => if flag == 0 { ctx.read(old_source.view()) } else { Ok(9) }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  assert_eq(store.read(query.at(())), Ok(4))
  ignore(old.close())
  ignore(store.transaction(tx => tx.set(selector, 1)))
  assert_eq(store.read(query.at(())), Ok(9))
  assert_eq(query.core.compute_count.val, 2)
  assert_eq(query.core.verification_count.val, 1)
  assert_eq(query.core.red_count.val, 1)
  assert_eq(query.core.dependency_check_count.val, 2)
  assert_eq(query.core.unavailable_count.val, 1)
  assert_eq(query.core.memo.get(()).unwrap().trace.length(), 1)
}

///|
test "Region close clears Query memo state" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(4).unwrap()
  let query = region
    .query((ctx, _key : Int) => ctx.read(source.view()))
    .unwrap()
  assert_eq(store.read(query.at(4)), Ok(4))
  assert_eq(query.core.memo.length(), 1)
  assert_eq(query.core.memo.get(4).unwrap().trace.length(), 1)
  assert_true(query.core.compute.val is Some(_))
  ignore(region.close())
  assert_true(query.core.memo.is_empty())
  assert_true(query.core.compute.val is None)
}
