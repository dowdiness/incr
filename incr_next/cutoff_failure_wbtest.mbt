///|
test "target failures and cycles do not invoke cutoff" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(0)
  let foreign_store = Store::Store()
  let foreign_region = foreign_store.region()
  let foreign = foreign_region.source(9)
  let fail = Ref(false)
  let query = region.query(
    (ctx, _unit : Unit) => {
      let value = ctx.get(source.view())
      if fail.val {
        ctx.get(foreign.view())
      } else {
        value
      }
    },
    cutoff=Cutoff::equal(),
  )

  let view = query.view(())
  assert_eq(store.get(view), 0)
  assert_eq(query.core.cutoff_count.val, 0)
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  fail.val = true
  assert_true(
    (Ok(store.get(view)) catch { error => Err(error) }) is Err(CrossStore(_)),
  )
  assert_eq(query.core.cutoff_count.val, 0)
  let memo = query.core.memo.get(()).unwrap()
  assert_eq(memo.value, 0)
  fail.val = false
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 2)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(store.get(view), 2)
  assert_eq(query.core.cutoff_count.val, 1)
  foreign_region.close()
  region.close()
}

///|
test "an existing-memo self Cycle has zero cutoff and equivalent recovery backdates" {
  let store = Store::Store()
  let region = store.region()
  let trigger = region.source(0)
  let cycle = Ref(false)
  let self_view : Ref[View[Int]?] = Ref(None)
  let query = region.query(
    (ctx, _unit : Unit) => {
      ignore(ctx.get(trigger.view()))
      if cycle.val {
        ctx.get(self_view.val.unwrap())
      } else {
        7
      }
    },
    cutoff=Cutoff::equal(),
  )

  let view = query.view(())
  self_view.val = Some(view)
  assert_eq(store.get(view), 7)
  let before = query.core.memo.get(()).unwrap()
  cycle.val = true
  ignore(
    (
      store.transaction(tx => {
        tx.set(trigger, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_true(
    (Ok(store.get(view)) catch { error => Err(error) }) is Err(Cycle(_)),
  )
  let after_cycle = query.core.memo.get(()).unwrap()
  assert_eq(query.core.cutoff_count.val, 0)
  assert_eq(after_cycle.memo_id, before.memo_id)
  assert_eq(after_cycle.value, before.value)
  assert_eq(after_cycle.verified_at, before.verified_at)
  assert_eq(after_cycle.changed_at, before.changed_at)
  cycle.val = false
  ignore(
    (
      store.transaction(tx => {
        tx.set(trigger, 2)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let current = store.change_epoch.val
  assert_eq(store.get(view), 7)
  let recovered = query.core.memo.get(()).unwrap()
  assert_eq(query.core.cutoff_count.val, 1)
  assert_eq(recovered.memo_id, before.memo_id)
  assert_eq(recovered.value, 7)
  assert_eq(recovered.trace.length(), 1)
  assert_eq(recovered.verified_at, current)
  assert_eq(recovered.changed_at, before.changed_at)
  region.close()
}

///|
test "a successful equivalent child commits cutoff before a failing parent" {
  let store = Store::Store()
  let region = store.region()
  let source = region.source(0)
  let foreign_store = Store::Store()
  let foreign_region = foreign_store.region()
  let foreign = foreign_region.source(9)
  let child = region.query(
    (ctx, _unit : Unit) => {
      ignore(ctx.get(source.view()))
      1
    },
    cutoff=Cutoff::equal(),
  )

  let fail = Ref(false)
  let parent_trigger = region.source(0)
  let parent = region.query((ctx, _unit : Unit) => {
    ignore(ctx.get(parent_trigger.view()))
    let value = ctx.get(child.view(()))
    if fail.val {
      ctx.get(foreign.view())
    } else {
      value
    }
  })

  let view = parent.view(())
  assert_eq(store.get(view), 1)
  let child_id = child.core.memo.get(()).unwrap().memo_id
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 2)
        tx.set(parent_trigger, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  fail.val = true
  assert_true(
    (Ok(store.get(view)) catch { error => Err(error) }) is Err(CrossStore(_)),
  )
  assert_eq(child.core.cutoff_count.val, 1)
  assert_eq(parent.core.cutoff_count.val, 0)
  assert_eq(child.core.memo.get(()).unwrap().memo_id, child_id)
  assert_eq(child.core.memo.get(()).unwrap().value, 1)
  fail.val = false
  ignore(
    (
      store.transaction(tx => {
        tx.set(source, 3)
        tx.set(parent_trigger, 2)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(store.get(view), 1)
  assert_eq(child.core.cutoff_count.val, 2)
  assert_eq(parent.core.cutoff_count.val, 1)
  foreign_region.close()
  region.close()
}

///|
test "an equivalent descendant commits before an ancestor Cycle" {
  let store = Store::Store()
  let region = store.region()
  let child_source = region.source(0)
  let ancestor_trigger = region.source(0)
  let cycle = Ref(false)
  let self_view : Ref[View[Int]?] = Ref(None)
  let child = region.query(
    (ctx, _unit : Unit) => {
      ignore(ctx.get(child_source.view()))
      1
    },
    cutoff=Cutoff::equal(),
  )

  let parent = region.query((ctx, _unit : Unit) => {
    ignore(ctx.get(ancestor_trigger.view()))
    let value = ctx.get(child.view(()))
    if cycle.val {
      ctx.get(self_view.val.unwrap())
    } else {
      value
    }
  })

  let view = parent.view(())
  self_view.val = Some(view)
  assert_eq(store.get(view), 1)
  let child_before = child.core.memo.get(()).unwrap()
  let parent_before = parent.core.memo.get(()).unwrap()
  cycle.val = true
  ignore(
    (
      store.transaction(tx => {
        tx.set(child_source, 1)
        tx.set(ancestor_trigger, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_true(
    (Ok(store.get(view)) catch { error => Err(error) }) is Err(Cycle(_)),
  )
  let child_after = child.core.memo.get(()).unwrap()
  let parent_after = parent.core.memo.get(()).unwrap()
  assert_eq(child.core.cutoff_count.val, 1)
  assert_eq(parent.core.cutoff_count.val, 0)
  assert_eq(child_after.memo_id, child_before.memo_id)
  assert_eq(child_after.value, 1)
  assert_eq(child_after.verified_at, store.change_epoch.val)
  assert_eq(child_after.changed_at, child_before.changed_at)
  assert_eq(parent_after.memo_id, parent_before.memo_id)
  assert_eq(parent_after.value, parent_before.value)
  assert_eq(parent_after.trace.length(), parent_before.trace.length())
  assert_eq(parent_after.verified_at, parent_before.verified_at)
  assert_eq(parent_after.changed_at, parent_before.changed_at)
  region.close()
}
