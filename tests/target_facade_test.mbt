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
impl @incr.RuntimeContext for FacadeContext with runtime(self) {
  self.rt
}

///|
impl @incr.InputFieldOwner for FacadeInputFields with cell_ids(self) {
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
test "panic facade scope: derived_map read after dispose aborts" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let by_key = scope.derived_map((key : Int) => key * 2)

  inspect(by_key.read_or_abort(5), content="10")
  scope.dispose()
  ignore(by_key.read(5))
}
