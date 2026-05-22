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
