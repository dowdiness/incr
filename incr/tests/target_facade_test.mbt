///|
fn[T : @incr.Freshness] is_fresh_for_test(node : T) -> Bool {
  node.is_fresh()
}

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
test "facade input: derive creates derived tracking input" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 10)
  let derived = input.derived(fn(v) { v * 2 })

  inspect(derived.read_or_abort(), content="20")
  input.set(20)
  inspect(derived.read_or_abort(), content="40")
}

///|
test "facade input: derive backdates equal output" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 21)
  let normalized = input.derived(fn(v) { v / 10 })
  let mut downstream_runs = 0
  let downstream = @incr.Derived(rt, () => {
    downstream_runs = downstream_runs + 1
    normalized.get_or_abort()
  })

  inspect(downstream.read_or_abort(), content="2")
  input.set(29)
  inspect(downstream.read_or_abort(), content="2")
  inspect(downstream_runs, content="1")
  input.set(31)
  inspect(downstream.read_or_abort(), content="3")
  inspect(downstream_runs, content="2")
}

///|
test "facade input: derive propagates label" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 21)
  let derived = input.derived(fn(v) { v / 10 }, label="derived")

  guard rt.cell_info(derived.id()) is Some(info) else {
    fail("expected derived cell info")
  }
  debug_inspect(info.label, content="Some(\"derived\")")
}

///|
test "facade input: derived_no_backdate accepts non-Eq output" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 3)
  let derived = input.derived_no_backdate(fn(v) { (x : Int) => x + v })

  inspect(derived.read_or_abort()(10), content="13")
  input.set(4)
  inspect(derived.read_or_abort()(10), content="14")
}

///|
test "facade input: derived_no_backdate propagates equal output" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 21)
  let normalized = input.derived_no_backdate(fn(v) { v / 10 })
  let mut downstream_runs = 0
  let downstream = @incr.Derived(rt, () => {
    downstream_runs = downstream_runs + 1
    normalized.get_or_abort()
  })

  inspect(downstream.read_or_abort(), content="2")
  // Same mapped output (2) but no backdate — downstream MUST rerun
  input.set(29)
  inspect(downstream.read_or_abort(), content="2")
  inspect(downstream_runs, content="2")
}

///|
test "facade input: derived_no_backdate propagates label" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 21)
  let derived = input.derived_no_backdate(
    fn(v) { v / 10 },
    label="derived-no-bd",
  )

  guard rt.cell_info(derived.id()) is Some(info) else {
    fail("expected derived cell info")
  }
  debug_inspect(info.label, content="Some(\"derived-no-bd\")")
}

///|
test "facade input_field: get peek set force_set and tracking" {
  let rt = @incr.Runtime()
  let field = @incr.InputField(rt, 2, label="field")
  let mut view_runs = 0
  let view = @incr.Derived(rt, () => {
    view_runs = view_runs + 1
    field.get() + 1
  })

  inspect(field.get(), content="2")
  inspect(field.peek(), content="2")
  inspect(view.read_or_abort(), content="3")
  inspect(view_runs, content="1")
  field.set(3)
  inspect(view.read_or_abort(), content="4")
  inspect(view_runs, content="2")
  field.set(3)
  inspect(view.read_or_abort(), content="4")
  inspect(view_runs, content="2")
  field.force_set(3)
  inspect(view.read_or_abort(), content="4")
  inspect(view_runs, content="3")
  inspect(field.id() == field.as_tracked_cell().id(), content="true")
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
test "facade derived: map transforms and tracks source" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 10)
  let source = @incr.Derived(rt, () => input.get() + 1)
  let mapped = source.map_no_backdate(v => v * 2, label="mapped.double")

  inspect(mapped.read_or_abort(), content="22")
  guard rt.cell_info(mapped.id()) is Some(info) else {
    fail("expected mapped cell info")
  }
  debug_inspect(info.label, content="Some(\"mapped.double\")")
  input.set(20)
  inspect(mapped.read_or_abort(), content="42")
}

///|
test "facade derived: map accepts non-Eq output" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 3)
  let source = @incr.Derived(rt, () => input.get())
  let mapped = source.map_no_backdate(v => (x : Int) => x + v)

  inspect(mapped.read_or_abort()(10), content="13")
  input.set(4)
  inspect(mapped.read_or_abort()(10), content="14")
}

///|
test "facade derived: map_eq backdates equal mapped output" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 21)
  let source = @incr.Derived(rt, () => input.get())
  let normalized = source.map(v => v / 10)
  let mut downstream_runs = 0
  let downstream = @incr.Derived(rt, () => {
    downstream_runs = downstream_runs + 1
    normalized.get_or_abort()
  })

  inspect(downstream.read_or_abort(), content="2")
  input.set(29)
  inspect(downstream.read_or_abort(), content="2")
  inspect(downstream_runs, content="1")
}

///|
test "facade derived: map_eq invalidates when mapped output changes" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 21)
  let source = @incr.Derived(rt, () => input.get())
  let normalized = source.map(v => v / 10)
  let mut downstream_runs = 0
  let downstream = @incr.Derived(rt, () => {
    downstream_runs = downstream_runs + 1
    normalized.get_or_abort()
  })

  inspect(downstream.read_or_abort(), content="2")
  input.set(31)
  inspect(downstream.read_or_abort(), content="3")
  inspect(downstream_runs, content="2")
}

///|
test "facade derived: map_eq propagates label" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 21)
  let source = @incr.Derived(rt, () => input.get())
  let normalized = source.map(v => v / 10, label="normalized")

  guard rt.cell_info(normalized.id()) is Some(info) else {
    fail("expected mapped cell info")
  }
  debug_inspect(info.label, content="Some(\"normalized\")")
}

///|
test "facade derived: map2 reacts to left and right sources" {
  let rt = @incr.Runtime()
  let left_input = @incr.Input(rt, 2)
  let right_input = @incr.Input(rt, 3)
  let left = @incr.Derived(rt, () => left_input.get())
  let right = @incr.Derived(rt, () => right_input.get())
  let total = left.map2_no_backdate(right, (a, b) => a + b, label="total")

  inspect(total.read_or_abort(), content="5")
  left_input.set(4)
  inspect(total.read_or_abort(), content="7")
  right_input.set(5)
  inspect(total.read_or_abort(), content="9")
  guard rt.cell_info(total.id()) is Some(info) else {
    fail("expected combined cell info")
  }
  debug_inspect(info.label, content="Some(\"total\")")
}

///|
test "facade derived: map2 accepts non-Eq output" {
  let rt = @incr.Runtime()
  let left_input = @incr.Input(rt, 2)
  let right_input = @incr.Input(rt, 3)
  let left = @incr.Derived(rt, () => left_input.get())
  let right = @incr.Derived(rt, () => right_input.get())
  let total = left.map2_no_backdate(right, (a, b) => (x : Int) => x + a + b)

  inspect(total.read_or_abort()(10), content="15")
  right_input.set(4)
  inspect(total.read_or_abort()(10), content="16")
}

///|
test "facade derived: map2_eq backdates equal mapped output" {
  let rt = @incr.Runtime()
  let left_input = @incr.Input(rt, 12)
  let right_input = @incr.Input(rt, 9)
  let left = @incr.Derived(rt, () => left_input.get())
  let right = @incr.Derived(rt, () => right_input.get())
  let bucket = left.map2(right, (a, b) => (a + b) / 10)
  let mut downstream_runs = 0
  let downstream = @incr.Derived(rt, () => {
    downstream_runs = downstream_runs + 1
    bucket.get_or_abort()
  })

  inspect(downstream.read_or_abort(), content="2")
  left_input.set(19)
  inspect(downstream.read_or_abort(), content="2")
  inspect(downstream_runs, content="1")
  right_input.set(11)
  inspect(downstream.read_or_abort(), content="3")
  inspect(downstream_runs, content="2")
}

///|
test "panic facade derived: map2 rejects cross-runtime input" {
  let rt1 = @incr.Runtime()
  let rt2 = @incr.Runtime()
  let left = @incr.Derived(rt1, () => 1)
  let right = @incr.Derived(rt2, () => 2)

  ignore(left.map2_no_backdate(right, (a, b) => a + b))
}

///|
test "panic facade derived: map2_eq rejects cross-runtime input" {
  let rt1 = @incr.Runtime()
  let rt2 = @incr.Runtime()
  let left = @incr.Derived(rt1, () => 1)
  let right = @incr.Derived(rt2, () => 2)

  ignore(left.map2(right, (a, b) => a + b))
}

///|
test "facade derived: map3 reacts to all sources" {
  let rt = @incr.Runtime()
  let first_input = @incr.Input(rt, 1)
  let second_input = @incr.Input(rt, 2)
  let third_input = @incr.Input(rt, 3)
  let first = @incr.Derived(rt, () => first_input.get())
  let second = @incr.Derived(rt, () => second_input.get())
  let third = @incr.Derived(rt, () => third_input.get())
  let total = first.map3_no_backdate(
    second,
    third,
    (a, b, c) => a + b + c,
    label="total3",
  )

  inspect(total.read_or_abort(), content="6")
  first_input.set(10)
  inspect(total.read_or_abort(), content="15")
  second_input.set(20)
  inspect(total.read_or_abort(), content="33")
  third_input.set(30)
  inspect(total.read_or_abort(), content="60")
  guard rt.cell_info(total.id()) is Some(info) else {
    fail("expected combined cell info")
  }
  debug_inspect(info.label, content="Some(\"total3\")")
}

///|
test "facade derived: map3 accepts non-Eq output" {
  let rt = @incr.Runtime()
  let first_input = @incr.Input(rt, 1)
  let second_input = @incr.Input(rt, 2)
  let third_input = @incr.Input(rt, 3)
  let first = @incr.Derived(rt, () => first_input.get())
  let second = @incr.Derived(rt, () => second_input.get())
  let third = @incr.Derived(rt, () => third_input.get())
  let total = first.map3_no_backdate(second, third, (a, b, c) => {
    (x : Int) => x + a + b + c
  })

  inspect(total.read_or_abort()(10), content="16")
  third_input.set(4)
  inspect(total.read_or_abort()(10), content="17")
}

///|
test "facade derived: map3_eq backdates equal mapped output" {
  let rt = @incr.Runtime()
  let first_input = @incr.Input(rt, 12)
  let second_input = @incr.Input(rt, 5)
  let third_input = @incr.Input(rt, 4)
  let first = @incr.Derived(rt, () => first_input.get())
  let second = @incr.Derived(rt, () => second_input.get())
  let third = @incr.Derived(rt, () => third_input.get())
  let bucket = first.map3(second, third, (a, b, c) => (a + b + c) / 10)
  let mut downstream_runs = 0
  let downstream = @incr.Derived(rt, () => {
    downstream_runs = downstream_runs + 1
    bucket.get_or_abort()
  })

  inspect(downstream.read_or_abort(), content="2")
  second_input.set(7)
  inspect(downstream.read_or_abort(), content="2")
  inspect(downstream_runs, content="1")
  third_input.set(11)
  inspect(downstream.read_or_abort(), content="3")
  inspect(downstream_runs, content="2")
}

///|
test "panic facade derived: map3 rejects cross-runtime input" {
  let rt1 = @incr.Runtime()
  let rt2 = @incr.Runtime()
  let first = @incr.Derived(rt1, () => 1)
  let second = @incr.Derived(rt1, () => 2)
  let third = @incr.Derived(rt2, () => 3)

  ignore(first.map3_no_backdate(second, third, (a, b, c) => a + b + c))
}

///|
test "panic facade derived: map3 rejects cross-runtime second input" {
  let rt1 = @incr.Runtime()
  let rt2 = @incr.Runtime()
  let first = @incr.Derived(rt1, () => 1)
  let second = @incr.Derived(rt2, () => 2)
  let third = @incr.Derived(rt1, () => 3)

  ignore(first.map3_no_backdate(second, third, (a, b, c) => a + b + c))
}

///|
test "panic facade derived: map3_eq rejects cross-runtime input" {
  let rt1 = @incr.Runtime()
  let rt2 = @incr.Runtime()
  let first = @incr.Derived(rt1, () => 1)
  let second = @incr.Derived(rt1, () => 2)
  let third = @incr.Derived(rt2, () => 3)

  ignore(first.map3(second, third, (a, b, c) => a + b + c))
}

///|
test "panic facade derived: map3_eq rejects cross-runtime second input" {
  let rt1 = @incr.Runtime()
  let rt2 = @incr.Runtime()
  let first = @incr.Derived(rt1, () => 1)
  let second = @incr.Derived(rt2, () => 2)
  let third = @incr.Derived(rt1, () => 3)

  ignore(first.map3(second, third, (a, b, c) => a + b + c))
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
test "facade derived: watch reads outside graph and keeps target alive" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1)
  let derived = @incr.Derived(rt, () => input.get() + 1)
  let watch : @incr.Watch[Int] = derived.watch()

  inspect(watch.read_or_abort(), content="2")
  rt.gc()
  input.set(2)
  inspect(watch.read_or_abort(), content="3")
  watch.dispose()
  inspect(watch.is_disposed(), content="true")
}

///|
test "panic facade derived: watch read after dispose aborts" {
  let rt = @incr.Runtime()
  let derived = @incr.Derived(rt, () => 1)
  let watch = derived.watch()

  watch.dispose()
  ignore(watch.read())
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
test "facade reachable derived: watch reads outside graph" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 2)
  let reachable = @incr.ReachableDerived(rt, () => input.get() * 4)
  let watch = reachable.watch()

  inspect(watch.read_or_abort(), content="8")
  rt.gc()
  input.set(3)
  inspect(watch.read_or_abort(), content="12")
  watch.dispose()
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
test "facade eager derived: watch reads outside graph" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 4)
  let eager = @incr.EagerDerived(rt, () => input.get() * 5)
  let watch = eager.watch()

  inspect(watch.read_or_abort(), content="20")
  rt.gc()
  input.set(6)
  inspect(watch.read_or_abort(), content="30")
  watch.dispose()
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
test "facade freshness: target handles expose is_fresh" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1)
  let field = @incr.InputField(rt, 2)
  let derived = @incr.Derived(rt, () => input.get() + field.get())
  let reachable = @incr.ReachableDerived(rt, () => field.get() * 2)

  inspect(input.is_fresh(), content="true")
  inspect(is_fresh_for_test(field), content="true")
  inspect(derived.is_fresh(), content="false")
  inspect(reachable.is_fresh(), content="false")

  inspect(derived.read_or_abort(), content="3")
  inspect(reachable.read_or_abort(), content="4")
  inspect(derived.is_fresh(), content="true")
  inspect(is_fresh_for_test(reachable), content="true")

  input.set(3)
  inspect(input.is_fresh(), content="true")
  inspect(derived.is_fresh(), content="false")
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
  inspect(by_key.read_or_else(2, (_ : @incr.ReadError) => -2), content="12")
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

///|
test "facade map_relation: insert get iter and delta_iter" {
  let rt = @incr.Runtime()
  let map : @incr.MapRelation[String, Int] = @incr.MapRelation(rt)

  inspect(map.insert("a", 1), content="true")
  inspect(map.insert("b", 2), content="true")
  debug_inspect(map.get("a"), content="None")
  inspect(
    map.delta_iter().fold(init=0, fn(acc, _entry) { acc + 1 }),
    content="2",
  )
  inspect(map.iter().fold(init=0, fn(acc, _entry) { acc + 1 }), content="0")

  rt.fixpoint()
  debug_inspect(map.get("a"), content="Some(1)")
  inspect(map.iter().fold(init=0, fn(acc, _entry) { acc + 1 }), content="2")
}

///|
test "facade map_relation: id participates in rules" {
  let rt = @incr.Runtime()
  let edges : @incr.Relation[(Int, Int)] = @incr.Relation(rt)
  let weights : @incr.MapRelation[(Int, Int), Int] = @incr.MapRelation(rt)

  ignore(edges.insert((1, 2)))
  ignore(
    rt.new_rule([edges.id()], [weights.id()], fn() {
      for edge in edges.delta_iter() {
        ignore(weights.insert(edge, 1))
      }
    }),
  )
  rt.fixpoint()
  debug_inspect(weights.get((1, 2)), content="Some(1)")
}

///|
test "facade map_relation: dispose marks relation disposed" {
  let rt = @incr.Runtime()
  let map : @incr.MapRelation[String, Int] = @incr.MapRelation(rt)

  inspect(map.is_disposed(), content="false")
  map.dispose()
  inspect(map.is_disposed(), content="true")
}

///|
test "panic facade map_relation: get after dispose aborts" {
  let rt = @incr.Runtime()
  let map : @incr.MapRelation[String, Int] = @incr.MapRelation(rt)

  map.dispose()
  ignore(map.get("a"))
}

///|
struct FacadeContext {
  rt : @incr.Runtime
}

///|
struct FacadeInputFields {
  path : @incr.InputField[String]
  version : @incr.InputField[Int]
}

///|
fn FacadeContext::FacadeContext() -> FacadeContext {
  { rt: @incr.Runtime() }
}

///|
impl @incr.RuntimeContext for FacadeContext with fn runtime(self) {
  self.rt
}

///|
impl @incr.InputFieldOwner for FacadeInputFields with fn cell_ids(self) {
  [self.path.id(), self.version.id()]
}

///|
test "facade runtime context: creates target handles" {
  let ctx = FacadeContext()
  let input = @incr.create_input(ctx, 3)
  let field = @incr.create_input_field(ctx, 4)
  let derived = @incr.create_derived(ctx, () => input.get() + field.get())
  let reachable = @incr.create_reachable_derived(ctx, () => {
    derived.read_or_abort() + 1
  })
  let eager = @incr.create_eager_derived(ctx, () => input.get() * 10)
  let by_key = @incr.create_derived_map(ctx, (key : Int) => input.get() + key)

  inspect(field.get(), content="4")
  inspect(derived.read_or_abort(), content="7")
  inspect(reachable.read_or_abort(), content="8")
  inspect(eager.read(), content="30")
  inspect(by_key.read_or_abort(2), content="5")
}

///|
test "facade scope: creates target handles" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let input = scope.input(2)
  let field = scope.input_field(5)
  let derived = scope.derived(() => input.get() + field.get())
  let reachable = scope.reachable_derived(() => derived.read_or_abort() + 1)
  let eager = scope.eager_derived(() => input.get() * 10)
  let by_key = scope.derived_map((key : Int) => input.get() + key)

  inspect(field.get(), content="5")
  inspect(derived.read_or_abort(), content="7")
  inspect(reachable.read_or_abort(), content="8")
  inspect(eager.read(), content="20")
  inspect(by_key.read_or_abort(5), content="7")
  inspect(by_key.cache_len(), content="1")
  scope.dispose()
  inspect(field.is_disposed(), content="true")
}

///|
test "facade scope: add_watch disposes target watch" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let input = @incr.Input(rt, 2)
  let derived = @incr.Derived(rt, () => input.get() + 1)
  let watch = scope.add_watch(derived.watch())

  inspect(watch.read_or_abort(), content="3")
  inspect(watch.is_disposed(), content="false")
  scope.dispose()
  inspect(watch.is_disposed(), content="true")
}

///|
test "panic facade scope: add_watch on disposed scope aborts" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let derived = @incr.Derived(rt, () => 1)
  let watch = derived.watch()

  scope.dispose()
  ignore(scope.add_watch(watch))
}

///|
test "facade input_field_owner: add_input_fields registers fields" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let fields : FacadeInputFields = {
    path: @incr.InputField(rt, "src/main.mbt", label="path"),
    version: @incr.InputField(rt, 1, label="version"),
  }

  @incr.add_input_fields(scope, fields)
  inspect(fields.path.get(), content="src/main.mbt")
  inspect(fields.version.get(), content="1")
  scope.dispose()
  inspect(fields.path.is_disposed(), content="true")
  inspect(fields.version.is_disposed(), content="true")
}

///|
test "facade scope: derived_map read after dispose returns Err" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let by_key = scope.derived_map((key : Int) => key * 2)

  inspect(by_key.read_or_abort(5), content="10")
  scope.dispose()
  guard by_key.read(5) is Err(e) else {
    fail("expected Err after derived_map scope disposal")
  }
  inspect(e.is_disposed(), content="true")
}

///|
test "facade id(): single-cell facades expose stable cell ids scoped to the runtime" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1)
  let reachable = @incr.ReachableDerived(rt, () => input.get())
  let eager = @incr.EagerDerived(rt, () => input.get())

  // id() is stable across calls.
  inspect(input.id() == input.id(), content="true")
  inspect(reachable.id() == reachable.id(), content="true")
  inspect(eager.id() == eager.id(), content="true")

  // Distinct cells have distinct ids.
  inspect(input.id() == reachable.id(), content="false")
  inspect(reachable.id() == eager.id(), content="false")

  // Every cell's runtime component is its owning runtime's identity — no
  // probe cell needed to reach it.
  inspect(input.id().runtime_id == rt.id(), content="true")
  inspect(reachable.id().runtime_id == rt.id(), content="true")
  inspect(eager.id().runtime_id == rt.id(), content="true")
}

///|
test "Runtime::id(): distinct runtimes have distinct ids; same runtime is stable" {
  let rt1 = @incr.Runtime()
  let rt2 = @incr.Runtime()

  // Stable within a runtime, distinct across runtimes — this is the
  // "are these two runtimes the same?" check, no probe cell required.
  inspect(rt1.id() == rt1.id(), content="true")
  inspect(rt1.id() == rt2.id(), content="false")

  // Cells inherit their owning runtime's identity.
  let a = @incr.Input(rt1, 0)
  let b = @incr.Input(rt2, 0)
  inspect(a.id().runtime_id == rt1.id(), content="true")
  inspect(b.id().runtime_id == rt2.id(), content="true")
  inspect(a.id().runtime_id == b.id().runtime_id, content="false")

  // RuntimeId Show prints the bare allocation number, keeping error text and
  // graph-visualization output readable (no "RuntimeId(..)" wrapper).
  inspect(rt1.id().to_string().contains("RuntimeId"), content="false")
}

///|
test "facade derived: derived_no_backdate accepts non-Eq output" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 3)
  let derived = @incr.Derived::derived_no_backdate(rt, fn() {
    (x : Int) => x + input.get()
  })

  inspect(derived.read_or_abort()(10), content="13")
  input.set(4)
  inspect(derived.read_or_abort()(10), content="14")
}

///|
test "facade derived: derived_no_backdate propagates equal output" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 21)
  let normalized = @incr.Derived::derived_no_backdate(rt, fn() {
    input.get() / 10
  })
  let mut downstream_runs = 0
  let downstream = @incr.Derived(rt, () => {
    downstream_runs = downstream_runs + 1
    normalized.get_or_abort()
  })

  inspect(downstream.read_or_abort(), content="2")
  input.set(29)
  inspect(downstream.read_or_abort(), content="2")
  inspect(downstream_runs, content="2")
}

///|
test "facade derived: derived_no_backdate propagates label" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 21)
  let derived = @incr.Derived::derived_no_backdate(
    rt,
    fn() { input.get() / 10 },
    label="derived-no-bd",
  )

  guard rt.cell_info(derived.id()) is Some(info) else {
    fail("expected derived cell info")
  }
  debug_inspect(info.label, content="Some(\"derived-no-bd\")")
}
