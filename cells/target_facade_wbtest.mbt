///|
test "facade derived: get returns cycle error in tracked context" {
  let rt = Runtime::Runtime()
  let derived = Derived::Derived(rt, () => 1)
  let cell_id = derived.inner.id()
  let meta = rt.get_memo_data(cell_id)
  meta.in_progress = true
  rt.push_tracking(cell_id)

  let got_cycle = match derived.get() {
    Ok(_) => false
    Err(err) => err.cell() == cell_id
  }
  meta.in_progress = false
  ignore(rt.pop_tracking())
  inspect(got_cycle, content="true")
}

///|
test "facade derived: read returns cycle error" {
  let rt = Runtime::Runtime()
  let derived = Derived::Derived(rt, () => 1)
  let cell_id = derived.inner.id()
  let meta = rt.get_memo_data(cell_id)
  meta.in_progress = true

  let got_cycle = match derived.read() {
    Ok(_) => false
    Err(err) => err.cell() == cell_id
  }
  meta.in_progress = false
  inspect(got_cycle, content="true")
}

///|
test "facade derived: watch read returns cycle error" {
  let rt = Runtime::Runtime()
  let derived = Derived::Derived(rt, () => 1)
  let cell_id = derived.inner.id()
  let meta = rt.get_memo_data(cell_id)
  let watch = derived.watch()
  meta.in_progress = true

  let got_cycle = match watch.read() {
    Ok(_) => false
    Err(err) => err.cell() == cell_id
  }
  meta.in_progress = false
  watch.dispose()
  inspect(got_cycle, content="true")
}

///|
test "facade reachable derived: read returns cycle error" {
  let rt = Runtime::Runtime()
  let reachable = ReachableDerived::ReachableDerived(rt, () => 1)
  let cell_id = reachable.inner.id()
  let meta = rt.get_memo_data(cell_id)
  meta.in_progress = true

  let got_cycle = match reachable.read() {
    Ok(_) => false
    Err(err) => err.cell() == cell_id
  }
  meta.in_progress = false
  inspect(got_cycle, content="true")
}

///|
test "facade derived_map: read returns cycle error" {
  let rt = Runtime::Runtime()
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => key * 10)
  let memo = by_key.inner.get_or_create_memo(1)
  let cell_id = memo.id()
  let meta = rt.get_memo_data(cell_id)
  meta.in_progress = true

  let got_cycle = match by_key.read(1) {
    Ok(_) => false
    Err(err) => err.cell() == cell_id
  }
  meta.in_progress = false
  inspect(got_cycle, content="true")
}

///|
test "facade derived_map: read_or fallbacks only on cycle" {
  let rt = Runtime::Runtime()
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => key * 10)

  inspect(by_key.read_or(1, -1), content="10")

  let memo = by_key.inner.get_or_create_memo(2)
  let cell_id = memo.id()
  let meta = rt.get_memo_data(cell_id)
  meta.in_progress = true

  inspect(by_key.read_or(2, -1), content="-1")
  inspect(
    by_key.read_or_else(2, (err : CycleError) => {
      if err.cell() == cell_id {
        -2
      } else {
        -3
      }
    }),
    content="-2",
  )
  meta.in_progress = false
}

///|
test "facade scope: target handles are disposed with scope" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  let input = scope.input(1)
  let derived = scope.derived(() => input.get() + 1)
  let reachable = scope.reachable_derived(() => derived.read_or_abort() + 1)
  let eager = scope.eager_derived(() => input.get() * 10)
  let by_key = scope.derived_map((key : Int) => input.get() + key)

  inspect(derived.read_or_abort(), content="2")
  inspect(reachable.read_or_abort(), content="3")
  inspect(eager.read(), content="10")
  inspect(by_key.read_or_abort(4), content="5")
  inspect(by_key.cache_len(), content="1")

  scope.dispose()

  inspect(input.inner.is_disposed(), content="true")
  inspect(derived.inner.is_disposed(), content="true")
  inspect(reachable.inner.is_disposed(), content="true")
  inspect(eager.inner.is_disposed(), content="true")
  inspect(by_key.disposed.val, content="true")
  inspect(by_key.inner.length(), content="0")
}
