///|
test "facade input: get peek set and force_set" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1)

  inspect(input.get(), content="1")
  inspect(input.peek(), content="1")
  input.set(2)
  inspect(input.get(), content="2")
  input.force_set(2)
  inspect(input.peek(), content="2")
}

///|
test "facade input: get inside tracked context records dependency" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 10)
  let mut view_runs = 0
  let view = @incr.Derived(rt, () => {
    view_runs = view_runs + 1
    input.get() + 1
  })

  inspect(view.read_or_abort(), content="11")
  inspect(view_runs, content="1")
  input.set(20)
  inspect(view.read_or_abort(), content="21")
  inspect(view_runs, content="2")
}

///|
test "facade derived: read works outside tracked context" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 10)
  let derived = @incr.Derived(rt, () => input.get() * 2)

  match derived.read() {
    Ok(value) => inspect(value, content="20")
    Err(_) => abort("expected derived read to succeed")
  }
}

///|
test "facade derived: get works inside tracked context" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 10)
  let derived = @incr.Derived(rt, () => input.get() * 2)
  let view = @incr.Derived(rt, () => {
    match derived.get() {
      Ok(value) => value + 1
      Err(_) => -1
    }
  })

  inspect(view.read_or_abort(), content="21")
}

///|
test "facade derived: read inside tracked context records dependency" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 10)
  let derived = @incr.Derived(rt, () => input.get() * 2)
  let mut view_runs = 0
  let view = @incr.Derived(rt, () => {
    view_runs = view_runs + 1
    match derived.read() {
      Ok(value) => value + 1
      Err(_) => -1
    }
  })

  inspect(view.read_or_abort(), content="21")
  inspect(view_runs, content="1")
  input.set(11)
  inspect(view.read_or_abort(), content="23")
  inspect(view_runs, content="2")
}

///|
test "panic facade derived: get outside tracked context aborts" {
  let rt = @incr.Runtime()
  let derived = @incr.Derived(rt, () => 1)

  ignore(derived.get())
}

///|
test "facade reachable derived: read and tracked get work" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 3)
  let reachable = @incr.ReachableDerived(rt, () => input.get() * 2)
  let view = @incr.Derived(rt, () => {
    match reachable.get() {
      Ok(value) => value + 1
      Err(_) => -1
    }
  })

  match reachable.read() {
    Ok(value) => inspect(value, content="6")
    Err(_) => abort("expected reachable read to succeed")
  }
  input.set(4)
  inspect(view.read_or_abort(), content="9")
}

///|
test "panic facade reachable derived: get outside tracked context aborts" {
  let rt = @incr.Runtime()
  let reachable = @incr.ReachableDerived(rt, () => 1)

  ignore(reachable.get())
}

///|
test "facade eager derived: read outside and get inside tracked context" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 4)
  let eager = @incr.EagerDerived(rt, () => input.get() * 3)
  let view = @incr.Derived(rt, () => eager.get() + 1)

  inspect(eager.read(), content="12")
  input.set(5)
  inspect(eager.read(), content="15")
  inspect(view.read_or_abort(), content="16")
}

///|
test "facade eager derived: read inside tracked context records dependency" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 4)
  let eager = @incr.EagerDerived(rt, () => input.get() * 3)
  let mut view_runs = 0
  let view = @incr.Derived(rt, () => {
    view_runs = view_runs + 1
    eager.read() + 1
  })

  inspect(view.read_or_abort(), content="13")
  inspect(view_runs, content="1")
  input.set(5)
  inspect(view.read_or_abort(), content="16")
  inspect(view_runs, content="2")
}

///|
test "panic facade eager derived: get outside tracked context aborts" {
  let rt = @incr.Runtime()
  let eager = @incr.EagerDerived(rt, () => 1)

  ignore(eager.get())
}

///|
test "facade derived_map: read cache and fallback helpers" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 10)
  let by_key = @incr.DerivedMap(rt, (key : Int) => input.get() + key)

  inspect(by_key.has_cached(2), content="false")
  match by_key.read(2) {
    Ok(value) => inspect(value, content="12")
    Err(_) => abort("expected derived map read to succeed")
  }
  inspect(by_key.has_cached(2), content="true")
  inspect(by_key.cache_len(), content="1")
  inspect(by_key.read_or(2, -1), content="12")
  inspect(by_key.read_or_else(2, (_ : @incr.CycleError) => -2), content="12")
  inspect(by_key.sweep_cache(), content="0")
  by_key.clear_cache()
  inspect(by_key.cache_len(), content="0")
}

///|
test "facade derived_map: strict get works inside tracked context" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 10)
  let by_key = @incr.DerivedMap(rt, (key : Int) => input.get() + key)
  let view = @incr.Derived(rt, () => {
    match by_key.get(1) {
      Ok(value) => value * 2
      Err(_) => -1
    }
  })

  inspect(view.read_or_abort(), content="22")
  input.set(20)
  inspect(view.read_or_abort(), content="42")
}

///|
test "panic facade derived_map: get outside tracked context aborts" {
  let rt = @incr.Runtime()
  let by_key = @incr.DerivedMap(rt, (key : Int) => key * 10)

  ignore(by_key.get(1))
}
