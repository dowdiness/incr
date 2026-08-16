///|
test "target failures and cycles do not invoke cutoff" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(0).unwrap()
  let foreign_store = Store::Store()
  let foreign_region = foreign_store.region().unwrap()
  let foreign = foreign_region.source(9).unwrap()
  let fail = Ref(false)
  let query = region
    .query_eq((ctx, _unit : Unit) => {
      match ctx.read(source.view()) {
        Ok(value) => if fail.val { ctx.read(foreign.view()) } else { Ok(value) }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = query.at(())
  assert_eq(store.read(view), Ok(0))
  assert_eq(query.core.cutoff_count.val, 0)
  ignore(store.transaction(tx => tx.set(source, 1)))
  fail.val = true
  assert_true(store.read(view) is Err(CrossStore(..)))
  assert_eq(query.core.cutoff_count.val, 0)
  let memo = query.core.memo.get(()).unwrap()
  assert_eq(memo.value, 0)
  fail.val = false
  ignore(store.transaction(tx => tx.set(source, 2)))
  assert_eq(store.read(view), Ok(2))
  assert_eq(query.core.cutoff_count.val, 1)
  ignore(foreign_region.close())
  ignore(region.close())
}

///|
test "an existing-memo self Cycle has zero cutoff and equivalent recovery backdates" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let trigger = region.source(0).unwrap()
  let cycle = Ref(false)
  let self_view : Ref[View[Int]?] = Ref(None)
  let query = region
    .query_eq((ctx, _unit : Unit) => {
      match ctx.read(trigger.view()) {
        Ok(_) =>
          if cycle.val {
            ctx.read(self_view.val.unwrap())
          } else {
            Ok(7)
          }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = query.at(())
  self_view.val = Some(view)
  assert_eq(store.read(view), Ok(7))
  let before = query.core.memo.get(()).unwrap()
  cycle.val = true
  ignore(store.transaction(tx => tx.set(trigger, 1)))
  assert_true(store.read(view) is Err(Cycle(_)))
  let after_cycle = query.core.memo.get(()).unwrap()
  assert_eq(query.core.cutoff_count.val, 0)
  assert_eq(after_cycle.memo_id, before.memo_id)
  assert_eq(after_cycle.value, before.value)
  assert_eq(after_cycle.verified_at, before.verified_at)
  assert_eq(after_cycle.changed_at, before.changed_at)
  cycle.val = false
  ignore(store.transaction(tx => tx.set(trigger, 2)))
  let current = store.change_epoch.val
  assert_eq(store.read(view), Ok(7))
  let recovered = query.core.memo.get(()).unwrap()
  assert_eq(query.core.cutoff_count.val, 1)
  assert_eq(recovered.memo_id, before.memo_id)
  assert_eq(recovered.value, 7)
  assert_eq(recovered.trace.length(), 1)
  assert_eq(recovered.verified_at, current)
  assert_eq(recovered.changed_at, before.changed_at)
  ignore(region.close())
}

///|
test "a successful equivalent child commits cutoff before a failing parent" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let source = region.source(0).unwrap()
  let foreign_store = Store::Store()
  let foreign_region = foreign_store.region().unwrap()
  let foreign = foreign_region.source(9).unwrap()
  let child = region
    .query_eq((ctx, _unit : Unit) => {
      match ctx.read(source.view()) {
        Ok(_) => Ok(1)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let fail = Ref(false)
  let parent_trigger = region.source(0).unwrap()
  let parent = region
    .query((ctx, _unit : Unit) => {
      match (ctx.read(parent_trigger.view()), ctx.read(child.at(()))) {
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
        (Ok(_), Ok(value)) =>
          if fail.val {
            ctx.read(foreign.view())
          } else {
            Ok(value)
          }
      }
    })
    .unwrap()
  let view = parent.at(())
  assert_eq(store.read(view), Ok(1))
  let child_id = child.core.memo.get(()).unwrap().memo_id
  ignore(
    store.transaction(tx => {
      ignore(tx.set(source, 2))
      tx.set(parent_trigger, 1)
    }),
  )
  fail.val = true
  assert_true(store.read(view) is Err(CrossStore(..)))
  assert_eq(child.core.cutoff_count.val, 1)
  assert_eq(parent.core.cutoff_count.val, 0)
  assert_eq(child.core.memo.get(()).unwrap().memo_id, child_id)
  assert_eq(child.core.memo.get(()).unwrap().value, 1)
  fail.val = false
  ignore(
    store.transaction(tx => {
      ignore(tx.set(source, 3))
      tx.set(parent_trigger, 2)
    }),
  )
  assert_eq(store.read(view), Ok(1))
  assert_eq(child.core.cutoff_count.val, 2)
  assert_eq(parent.core.cutoff_count.val, 1)
  ignore(foreign_region.close())
  ignore(region.close())
}

///|
test "an equivalent descendant commits before an ancestor Cycle" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let child_source = region.source(0).unwrap()
  let ancestor_trigger = region.source(0).unwrap()
  let cycle = Ref(false)
  let self_view : Ref[View[Int]?] = Ref(None)
  let child = region
    .query_eq((ctx, _unit : Unit) => {
      match ctx.read(child_source.view()) {
        Ok(_) => Ok(1)
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let parent = region
    .query((ctx, _unit : Unit) => {
      match (ctx.read(ancestor_trigger.view()), ctx.read(child.at(()))) {
        (Ok(_), Ok(value)) =>
          if cycle.val {
            ctx.read(self_view.val.unwrap())
          } else {
            Ok(value)
          }
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    })
    .unwrap()
  let view = parent.at(())
  self_view.val = Some(view)
  assert_eq(store.read(view), Ok(1))
  let child_before = child.core.memo.get(()).unwrap()
  let parent_before = parent.core.memo.get(()).unwrap()
  cycle.val = true
  ignore(
    store.transaction(tx => {
      ignore(tx.set(child_source, 1))
      tx.set(ancestor_trigger, 1)
    }),
  )
  assert_true(store.read(view) is Err(Cycle(_)))
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
  ignore(region.close())
}
