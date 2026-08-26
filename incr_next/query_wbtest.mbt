///|
test "a shared diamond has one inner kernel computation" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(0)
  let shared = region.query((ctx, _key : (Int, Int)) => ctx.get(source.view()))

  let left = region.query((ctx, _unit : Unit) => {
    ctx.get(shared.view((0, 0))) + 1
  })

  let right = region.query((ctx, _unit : Unit) => {
    ctx.get(shared.view((0, 0))) + 2
  })

  let root = region.query((ctx, _unit : Unit) => {
    ctx.get(left.view(())) + ctx.get(right.view(()))
  })

  assert_eq(Ok(store.get(root.view(()))) catch { error => Err(error) }, Ok(3))
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
  assert_eq(Ok(store.get(root.view(()))) catch { error => Err(error) }, Ok(3))
  assert_eq(root.core.compute_count.val, 1)
  assert_eq(shared.core.compute_count.val, 1)
  assert_eq(shared.core.cache_hit_count.val, 1)
}

///|
test "memo hits, identity, and epoch stamps are white-box observable" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(2)
  let query = region.query((ctx, _key : Int) => ctx.get(source.view()))

  assert_eq(Ok(store.get(query.view(7))) catch { error => Err(error) }, Ok(2))
  assert_eq(query.core.memo.length(), 1)
  assert_eq(query.core.compute_count.val, 1)
  assert_eq(query.core.cache_hit_count.val, 0)
  let before = query.core.memo.get(7).unwrap()
  assert_eq(before.verified_at, store.change_epoch.val)
  assert_eq(before.changed_at, store.change_epoch.val)
  assert_eq(Ok(store.get(query.view(7))) catch { error => Err(error) }, Ok(2))
  assert_eq(query.core.compute_count.val, 1)
  assert_eq(query.core.cache_hit_count.val, 1)
  let memo_id = query.core.memo.get(7).unwrap().memo_id
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 3)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let current_epoch = store.change_epoch.val
  assert_eq(Ok(store.get(query.view(7))) catch { error => Err(error) }, Ok(3))
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
test "successful memos own direct Source and Query traces" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(1)
  let source_query = region.query((ctx, _unit : Unit) => ctx.get(source.view()))
  let child_query = region.query((ctx, _unit : Unit) => {
    ctx.get(source_query.view(()))
  })
  let root_query = region.query((ctx, _unit : Unit) => {
    ctx.get(child_query.view(()))
  })

  assert_eq(
    Ok(store.get(source_query.view(()))) catch {
      error => Err(error)
    },
    Ok(1),
  )
  assert_eq(
    Ok(store.get(child_query.view(()))) catch {
      error => Err(error)
    },
    Ok(1),
  )
  assert_eq(
    Ok(store.get(root_query.view(()))) catch {
      error => Err(error)
    },
    Ok(1),
  )
  assert_eq(
    source_query.core.memo.get(()).unwrap().trace.map(dep => dep.kind),
    [Source],
  )
  assert_eq(child_query.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [
    Query,
  ])
  assert_eq(root_query.core.memo.get(()).unwrap().trace.map(dep => dep.kind), [
    Query,
  ])
}

///|
test "initial failure releases its temporary trace" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(1)
  let foreign = Store::Store().region().source(9)
  let captured = Ref(None)
  let query : Query[Unit, Int] = region.query((ctx, _unit : Unit) => {
    captured.val = Some(ctx)
    ignore(ctx.get(source.view()))
    ctx.get(foreign.view())
  })

  assert_true(
    (Ok(store.get(query.view(()))) catch { error => Err(error) })
    is Err(ReadError::CrossStore(_)),
  )
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(query.core.memo.is_empty())
}

///|
test "initial structural failure installs no memo, then recovery installs first ID" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region()
  let foreign_region = foreign_store.region()
  let source = region.source(1)
  let foreign = foreign_region.source(9)
  let fail_now = Ref(true)
  let captured = Ref(None)
  let query = region.query((ctx, _unit : Unit) => {
    captured.val = Some(ctx)
    let value = ctx.get(source.view())
    if fail_now.val {
      ignore(ctx.get(foreign.view()))
    }
    value
  })

  let view = query.view(())
  assert_true(
    (Ok(store.get(view)) catch { error => Err(error) }) is Err(CrossStore(_)),
  )
  assert_true(captured.val.unwrap().frame.val is None)
  assert_true(query.core.memo.is_empty())
  // The callback is changed only after the failed frame has been released.
  fail_now.val = false
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(1))
  assert_eq(query.core.memo.get(()).unwrap().memo_id.value, 0)
  foreign_region.close()
  region.close()
}

///|
test "failed recompute returns current error and preserves successful authority" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region()
  let foreign_region = foreign_store.region()
  let source = region.source(0)
  let foreign = foreign_region.source(9)
  let captured = Ref(None)
  let query = region.query((ctx, _unit : Unit) => {
    captured.val = Some(ctx)
    let value = ctx.get(source.view())
    if value == 1 {
      ctx.get(foreign.view())
    } else {
      value
    }
  })

  let view = query.view(())
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(0))
  let before = query.core.memo.get(()).unwrap()
  let before_kinds = before.trace.map(dep => dep.kind)
  let before_id = before.memo_id
  let before_value = before.value
  let before_verified_at = before.verified_at
  let before_changed_at = before.changed_at
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_true(
    (Ok(store.get(view)) catch { error => Err(error) }) is Err(CrossStore(_)),
  )
  assert_true(captured.val.unwrap().frame.val is None)
  let after = query.core.memo.get(()).unwrap()
  assert_eq(after.memo_id, before_id)
  assert_eq(after.value, before_value)
  assert_eq(after.trace.length(), before.trace.length())
  assert_eq(after.trace.map(dep => dep.kind), before_kinds)
  assert_eq(after.verified_at, before_verified_at)
  assert_eq(after.changed_at, before_changed_at)
  foreign_region.close()
  region.close()
}

///|
test "failed recompute recovers with the same memo identity" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region()
  let foreign_region = foreign_store.region()
  let source = region.source(0)
  let foreign = foreign_region.source(9)
  let captured = Ref(None)
  let query = region.query((ctx, _unit : Unit) => {
    captured.val = Some(ctx)
    let value = ctx.get(source.view())
    if value == 1 {
      ctx.get(foreign.view())
    } else {
      value
    }
  })

  let view = query.view(())
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(0))
  let memo_id = query.core.memo.get(()).unwrap().memo_id
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_true(
    (Ok(store.get(view)) catch { error => Err(error) }) is Err(CrossStore(_)),
  )
  assert_true(captured.val.unwrap().frame.val is None)
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 2)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let current_epoch = store.change_epoch.val
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(2))
  let after = query.core.memo.get(()).unwrap()
  assert_eq(after.memo_id, memo_id)
  assert_eq(after.value, 2)
  assert_eq(after.trace.length(), 1)
  assert_eq(after.trace.map(dep => dep.kind), [Source])
  assert_eq(after.verified_at, current_epoch)
  assert_eq(after.changed_at, current_epoch)
  foreign_region.close()
  region.close()
}

///|
test "successful child recompute remains installed when parent fails" {
  let store = Store::Store()
  let foreign_store = Store::Store()
  let region = store.region()
  let foreign_region = foreign_store.region()
  let source = region.source(0)
  let foreign = foreign_region.source(9)
  let child = region.query((ctx, _unit : Unit) => ctx.get(source.view()))

  let captured = Ref(None)
  let parent = region.query((ctx, _unit : Unit) => {
    captured.val = Some(ctx)
    let value = ctx.get(child.view(()))
    if value == 1 {
      ctx.get(foreign.view())
    } else {
      value + 10
    }
  })

  let view = parent.view(())
  assert_eq(Ok(store.get(view)) catch { error => Err(error) }, Ok(10))
  let before = parent.core.memo.get(()).unwrap()
  let before_id = before.memo_id
  let before_value = before.value
  let before_verified_at = before.verified_at
  let before_changed_at = before.changed_at
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_true(
    (Ok(store.get(view)) catch { error => Err(error) }) is Err(CrossStore(_)),
  )
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
  foreign_region.close()
  region.close()
}

///|
test "unrelated publication green-verifies without recompute" {
  let store = Store::Store()
  let region = store.region()
  let selected = region.source(2)
  let unrelated = region.source(9)
  let query = region.query((ctx, _unit : Unit) => ctx.get(selected.view()))

  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(2))
  let before = query.core.memo.get(()).unwrap()
  ignore(
    (
      store.transaction(tx => {
        tx.set(unrelated, 10)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let current = store.change_epoch.val
  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(2))
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
  let region = store.region()
  let source = region.source(2)
  let query = region.query((ctx, _unit : Unit) => ctx.get(source.view()))

  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(2))
  let before = query.core.memo.get(()).unwrap()
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 7)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let current = store.change_epoch.val
  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(7))
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
  let region = store.region()
  let source = region.source(0)
  let unrelated = region.source(5)
  let shared = region.query((ctx, _key : Unit) => ctx.get(source.view()))

  let left = region.query((ctx, _unit : Unit) => ctx.get(shared.view(())) + 1)

  let right = region.query((ctx, _unit : Unit) => ctx.get(shared.view(())) + 2)

  let root = region.query((ctx, _unit : Unit) => {
    ctx.get(left.view(())) + ctx.get(right.view(()))
  })

  assert_eq(Ok(store.get(root.view(()))) catch { error => Err(error) }, Ok(3))
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 4)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(Ok(store.get(root.view(()))) catch { error => Err(error) }, Ok(11))
  assert_eq(shared.core.compute_count.val, 2)
  assert_eq(shared.core.verification_count.val, 1)
  assert_eq(shared.core.green_count.val, 0)
  assert_eq(shared.core.red_count.val, 1)
  assert_eq(shared.core.dependency_check_count.val, 1)
  assert_eq(left.core.compute_count.val, 2)
  assert_eq(right.core.compute_count.val, 2)
  assert_eq(root.core.compute_count.val, 2)
  assert_eq(shared.core.cache_hit_count.val, 4)
  ignore(
    (
      store.transaction(tx => {
        tx.set(unrelated, 6)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(Ok(store.get(root.view(()))) catch { error => Err(error) }, Ok(11))
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
  let region = store.region()
  let source = region.source(1)
  let unrelated = region.source(2)
  let child = region.query((ctx, _unit : Unit) => ctx.get(source.view()))

  let parent = region.query((ctx, _unit : Unit) => ctx.get(child.view(())))

  assert_eq(Ok(store.get(parent.view(()))) catch { error => Err(error) }, Ok(1))
  ignore(
    (
      store.transaction(tx => {
        tx.set(unrelated, 8)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(Ok(store.get(parent.view(()))) catch { error => Err(error) }, Ok(1))
  assert_eq(child.core.memo.get(()).unwrap().trace.length(), 1)
  assert_eq(parent.core.memo.get(()).unwrap().trace.length(), 1)
  assert_eq(child.core.verification_count.val, 1)
  assert_eq(parent.core.verification_count.val, 1)
}

///|
test "dynamic trace replacement drops the old branch" {
  let store = Store::Store()
  let region = store.region()
  let branch = region.source(0)
  let old_branch = region.source(4)
  let query = region.query((ctx, _unit : Unit) => {
    let flag = ctx.get(branch.view())
    if flag == 0 {
      ctx.get(old_branch.view())
    } else {
      flag
    }
  })

  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(4))
  assert_eq(query.core.memo.get(()).unwrap().trace.length(), 2)
  ignore(
    (
      store.transaction(tx => {
        tx.set(branch, 9)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(9))
  assert_eq(query.core.memo.get(()).unwrap().trace.length(), 1)
  ignore(
    (
      store.transaction(tx => {
        tx.set(old_branch, 12)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(9))
  assert_eq(query.core.compute_count.val, 2)
  assert_eq(query.core.verification_count.val, 2)
  assert_eq(query.core.green_count.val, 1)
  assert_eq(query.core.red_count.val, 1)
  assert_eq(query.core.dependency_check_count.val, 3)
  assert_eq(query.core.unavailable_count.val, 0)
}

///|
test "all dependencies are checked when a closed cross Region branch is avoided" {
  let store = Store::Store()
  let live = store.region()
  let old = store.region()
  let selector = live.source(0)
  let old_source = old.source(4)
  let query = live.query((ctx, _unit : Unit) => {
    if ctx.get(selector.view()) == 0 {
      ctx.get(old_source.view())
    } else {
      9
    }
  })

  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(4))
  old.close()
  ignore(
    (
      store.transaction(tx => {
        tx.set(selector, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(Ok(store.get(query.view(()))) catch { error => Err(error) }, Ok(9))
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
  let region = store.region()
  let source = region.source(4)
  let query = region.query((ctx, _key : Int) => ctx.get(source.view()))

  assert_eq(Ok(store.get(query.view(4))) catch { error => Err(error) }, Ok(4))
  assert_eq(query.core.memo.length(), 1)
  assert_eq(query.core.memo.get(4).unwrap().trace.length(), 1)
  assert_true(query.core.compute.val is Some(_))
  region.close()
  assert_true(query.core.memo.is_empty())
  assert_true(query.core.compute.val is None)
}
