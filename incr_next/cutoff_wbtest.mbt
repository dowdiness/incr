///|
test "default and Eq cutoff preserve memo identity and stamps" {
  let store = Store::Store()
  let region = store.region()
  let trigger = region.source(0)
  let always_runs = Ref(0)
  let always = region.query((ctx, _unit : Unit) => {
    always_runs.val = always_runs.val + 1
    ignore(ctx.get(trigger.view()))
    7
  })

  assert_eq(store.get(always.view(())), 7)
  let always_id = always.core.memo.get(()).unwrap().memo_id
  ignore(
    (
      store.transaction(tx => {
        tx.set(trigger, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(store.get(always.view(())), 7)
  assert_eq(always_runs.val, 2)
  assert_eq(always.core.cutoff_count.val, 1)
  assert_eq(always.core.memo.get(()).unwrap().memo_id, always_id)
  assert_eq(
    always.core.memo.get(()).unwrap().changed_at,
    store.change_epoch.val,
  )

  let eq = region.query(
    (ctx, _unit : Unit) => {
      ignore(ctx.get(trigger.view()))
      7
    },
    cutoff=Cutoff::equal(),
  )

  assert_eq(
    (Ok(store.get(eq.view(()))) catch { error => Err(error) }).unwrap(),
    7,
  )
  let eq_before = eq.core.memo.get(()).unwrap()
  ignore(
    (
      store.transaction(tx => {
        tx.set(trigger, 2)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(
    (Ok(store.get(eq.view(()))) catch { error => Err(error) }).unwrap(),
    7,
  )
  let eq_after = eq.core.memo.get(()).unwrap()
  assert_eq(eq.core.cutoff_count.val, 1)
  assert_eq(eq_after.value, 7)
  assert_eq(eq_after.memo_id, eq_before.memo_id)
  assert_eq(eq_after.changed_at, eq_before.changed_at)
  assert_eq(eq_after.verified_at, store.change_epoch.val)

  region.close()
}

///|
test "equivalent cutoff keeps newest trace and skips a downstream query" {
  let store = Store::Store()
  let region = store.region()
  let branch = region.source(0)
  let old_branch = region.source(4)
  let new_branch = region.source(4)
  let root = region.query(
    (ctx, _unit : Unit) => {
      if ctx.get(branch.view()) == 0 {
        ctx.get(old_branch.view())
      } else {
        ctx.get(new_branch.view())
      }
    },
    cutoff=Cutoff::equal(),
  )

  let downstream_runs = Ref(0)
  let downstream = region.query((ctx, _unit : Unit) => {
    downstream_runs.val = downstream_runs.val + 1
    ctx.get(root.view(())) + 1
  })

  assert_eq(store.get(downstream.view(())), 5)
  assert_eq(root.core.compute_count.val, 1)
  assert_eq(downstream.core.compute_count.val, 1)
  let old_changed_at = root.core.memo.get(()).unwrap().changed_at
  ignore(
    (
      store.transaction(tx => {
        tx.set(branch, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(store.get(downstream.view(())), 5)
  assert_eq(root.core.compute_count.val, 2)
  assert_eq(root.core.cutoff_count.val, 1)
  assert_eq(root.core.memo.get(()).unwrap().changed_at, old_changed_at)
  assert_eq(downstream.core.compute_count.val, 1)
  ignore(
    (
      store.transaction(tx => {
        tx.set(old_branch, 12)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(store.get(downstream.view(())), 5)
  assert_eq(root.core.compute_count.val, 2)
  assert_eq(root.core.verification_count.val, 2)
  assert_eq(root.core.green_count.val, 1)
  assert_eq(root.core.cutoff_count.val, 1)
  assert_eq(downstream.core.compute_count.val, 1)
  ignore(
    (
      store.transaction(tx => {
        tx.set(branch, 0)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(store.get(downstream.view(())), 13)
  assert_eq(root.core.compute_count.val, 3)
  assert_eq(root.core.cutoff_count.val, 2)
  assert_eq(downstream.core.compute_count.val, 2)
  assert_eq(downstream_runs.val, 2)
}
