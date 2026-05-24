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

///|
test "Derived::is_disposed forwards to inner Memo" {
  let rt = Runtime::Runtime()
  let derived = Derived::Derived(rt, () => 1)
  inspect(derived.is_disposed(), content="false")
  derived.inner.dispose()
  inspect(derived.is_disposed(), content="true")
}

///|
test "Derived::changed_at forwards to inner Memo" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, 0)
  let derived = Derived::Derived(rt, () => input.get() * 2)
  let _ = derived.read_or_abort()
  let rev0 = derived.changed_at()
  // Same input value → backdating keeps changed_at stable.
  input.set(0)
  let _ = derived.read_or_abort()
  inspect(derived.changed_at() == rev0, content="true")
  // Different value advances changed_at.
  input.set(5)
  let _ = derived.read_or_abort()
  inspect(derived.changed_at() == rev0, content="false")
}

///|
test "Derived::accumulated forwards through compute closure" {
  let rt = Runtime::Runtime()
  let acc : Accumulator[Int] = Accumulator::new(rt~, label="diags")
  let producer = Derived::Derived(rt, () => {
    acc.push(7)
    acc.push(8)
    42
  })
  // Force `producer` to run once so it pushes into `acc`.
  let _ = producer.read_or_abort()
  // Read `producer.accumulated(acc)` from inside another Derived's compute,
  // matching Memo::accumulated's "tracked inside a compute frame" contract.
  let reader = Derived::Derived(rt, () => producer.accumulated(acc).length())
  inspect(reader.read_or_abort(), content="2")
}

///|
test "Derived::accumulated_peek forwards (untracked, defensive copy)" {
  let rt = Runtime::Runtime()
  let acc : Accumulator[Int] = Accumulator::new(rt~)
  let producer = Derived::Derived(rt, () => {
    acc.push(1)
    acc.push(2)
    acc.push(3)
    0
  })
  let _ = producer.read_or_abort()
  inspect(producer.accumulated_peek(acc).length(), content="3")
  // Disposal makes peek permissive: returns [].
  producer.inner.dispose()
  inspect(producer.accumulated_peek(acc).length(), content="0")
}
