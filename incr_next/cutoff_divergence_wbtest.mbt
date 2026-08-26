///|
priv struct GenerationValue {
  semantic : Int
  generation : Int
}

///|
impl Eq for GenerationValue with fn equal(self, other) {
  self.semantic == other.semantic
}

///|
priv struct NearValue {
  value : Int
}

///|
impl CutoffEq for NearValue with fn cutoff_equal(self, other) {
  let distance = self.value - other.value
  distance >= -1 && distance <= 1
}

///|
test "custom Eq can leave a downstream generation stale" {
  let store = Store::Store()
  let region = store.region()
  let trigger = region.source(0)
  let target = region.query(
    (ctx, _unit : Unit) => {
      let generation = ctx.get(trigger.view())
      GenerationValue::{ semantic: 7, generation }
    },
    cutoff=Cutoff::equal(),
  )

  let downstream = region.query((ctx, _unit : Unit) => {
    ctx.get(target.view(())).generation
  })

  assert_eq(
    (Ok(store.get(target.view(()))) catch { error => Err(error) }).unwrap().generation,
    0,
  )
  assert_eq(
    Ok(store.get(downstream.view(()))) catch {
      error => Err(error)
    },
    Ok(0),
  )
  let old_changed_at = target.core.memo.get(()).unwrap().changed_at
  ignore(
    (
      store.transaction(tx => {
        tx.set(trigger, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(
    Ok(store.get(downstream.view(()))) catch {
      error => Err(error)
    },
    Ok(0),
  )
  let direct = (Ok(store.get(target.view(()))) catch { error => Err(error) }).unwrap()
  assert_eq(direct.generation, 1)
  assert_eq(target.core.memo.get(()).unwrap().changed_at, old_changed_at)
  assert_eq(target.core.cutoff_count.val, 1)
  assert_eq(downstream.core.compute_count.val, 1)
  region.close()
}

///|
test "non-transitive local nearness leaves downstream at zero" {
  let store = Store::Store()
  let region = store.region()
  let trigger = region.source(0)
  let target = region.query(
    (ctx, _unit : Unit) => NearValue::{ value: ctx.get(trigger.view()) },
    cutoff=Cutoff::type_owned(),
  )

  let downstream = region.query((ctx, _unit : Unit) => {
    ctx.get(target.view(())).value
  })

  assert_eq(
    Ok(store.get(downstream.view(()))) catch {
      error => Err(error)
    },
    Ok(0),
  )
  ignore(
    (
      store.transaction(tx => {
        tx.set(trigger, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(
    Ok(store.get(downstream.view(()))) catch {
      error => Err(error)
    },
    Ok(0),
  )
  ignore(
    (
      store.transaction(tx => {
        tx.set(trigger, 2)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(
    Ok(store.get(downstream.view(()))) catch {
      error => Err(error)
    },
    Ok(0),
  )
  assert_eq(
    (Ok(store.get(target.view(()))) catch { error => Err(error) }).unwrap().value,
    2,
  )
  assert_eq(target.core.cutoff_count.val, 2)
  assert_eq(downstream.core.compute_count.val, 1)
  region.close()
}
