///|
test "panic scope: collect during non-idle phase aborts" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  rt.enter_phase(InFixpoint)
  scope.collect()
}

///|
test "scope: maintenance visits owned subtree once per collection" {
  let rt = Runtime()
  let root = Scope::new(rt)
  let child = root.child()
  let independent = Scope::new(rt)
  let root_map = root.derived_map((key : Int) => key)
  let child_map = child.derived_map((key : Int) => key)
  let independent_map = independent.derived_map((key : Int) => key)
  inspect(root.maintenance_hooks.length(), content="1")
  inspect(child.maintenance_hooks.length(), content="1")
  inspect(independent.maintenance_hooks.length(), content="1")

  let root_visits = Ref(0)
  let child_visits = Ref(0)
  let independent_visits = Ref(0)
  root.maintenance_hooks.push(() => root_visits.val = root_visits.val + 1)
  child.maintenance_hooks.push(() => child_visits.val = child_visits.val + 1)
  independent.maintenance_hooks.push(() => {
    independent_visits.val = independent_visits.val + 1
  })

  let input = root.input(1)
  let terminal = root.derived(() => input.get() + 1)
  let watch = root.watch(terminal)
  input.set(2)
  inspect(watch.read_or_abort(), content="3")
  ignore(root_map.read_or_abort(1))
  ignore(child_map.read_or_abort(1))
  ignore(independent_map.read_or_abort(1))
  inspect(root_visits.val, content="0")
  inspect(child_visits.val, content="0")
  inspect(independent_visits.val, content="0")

  root.collect()
  inspect(root_visits.val, content="1")
  inspect(child_visits.val, content="1")
  inspect(independent_visits.val, content="0")

  root.collect()
  inspect(root_visits.val, content="2")
  inspect(child_visits.val, content="2")
  inspect(independent_visits.val, content="0")
  root.dispose()
  independent.dispose()
}

///|
test "scope: disposal clears map maintenance ownership" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  let _map = scope.derived_map((key : Int) => key)
  inspect(scope.maintenance_hooks.length(), content="1")
  scope.dispose()
  inspect(scope.maintenance_hooks.length(), content="0")
}

///|
test "scope: collect releases disposed child ownership" {
  let rt = Runtime()
  let root = Scope::new(rt)
  let disposed_child = root.child()
  let live_child = root.child()
  disposed_child.dispose()
  inspect(root.children.length(), content="2")

  root.collect()

  inspect(root.children.length(), content="1")
  inspect(root.children[0].is_disposed(), content="false")
  live_child.dispose()
  root.dispose()
}
