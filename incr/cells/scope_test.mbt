///|
test "scope: new creates empty scope" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  inspect(scope.is_disposed(), content="false")
}

///|
test "scope: dispose marks scope as disposed" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  scope.dispose()
  inspect(scope.is_disposed(), content="true")
}

///|
test "scope: dispose is idempotent" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  scope.dispose()
  // Second dispose should not abort
  scope.dispose()
  inspect(scope.is_disposed(), content="true")
}

///|
test "scope: child creates nested scope" {
  let rt = Runtime::Runtime()
  let parent = Scope::new(rt)
  let child = parent.child()
  inspect(child.is_disposed(), content="false")
  inspect(parent.is_disposed(), content="false")
}

///|
test "scope: disposing parent disposes children" {
  let rt = Runtime::Runtime()
  let parent = Scope::new(rt)
  let child1 = parent.child()
  let child2 = parent.child()
  parent.dispose()
  inspect(child1.is_disposed(), content="true")
  inspect(child2.is_disposed(), content="true")
  inspect(parent.is_disposed(), content="true")
}

///|
test "scope: nested children disposed bottom-up" {
  let rt = Runtime::Runtime()
  let root = Scope::new(rt)
  let mid = root.child()
  let leaf = mid.child()
  root.dispose()
  inspect(leaf.is_disposed(), content="true")
  inspect(mid.is_disposed(), content="true")
  inspect(root.is_disposed(), content="true")
}

///|
test "panic scope: child of disposed scope aborts" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  scope.dispose()
  let _ = scope.child()
}

///|
test "scope: input creates cell and registers for disposal" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  let sig = scope.input(42)
  inspect(sig.get(), content="42")
  scope.dispose()
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: memo creates cell and registers for disposal" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  let sig = scope.input(10)
  let m = scope.derived(fn() { sig.get() * 2 })
  inspect(m.read_or_abort(), content="20")
  scope.dispose()
  inspect(m.is_disposed(), content="true")
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: hybrid_memo creates cell and registers for disposal" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  let sig = scope.input(5)
  let hm = scope.reachable_derived(fn() { sig.get() + 1 })
  inspect(hm.read_or_abort(), content="6")
  scope.dispose()
  inspect(hm.is_disposed(), content="true")
}

///|
test "scope: effect creates cell and registers for disposal" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  let ran : Ref[Int] = { val: 0 }
  let sig = scope.input(1)
  let eff = scope.effect(fn() { ran.val = ran.val + sig.get() })
  inspect(ran.val, content="1")
  scope.dispose()
  inspect(eff.is_disposed(), content="true")
}

///|
test "scope: reactive creates cell and registers for disposal" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  let sig = scope.input(3)
  let r : Reactive[Int] = scope.reactive(fn() { sig.get() * 3 })
  inspect(read_reactive_for_test(r), content="9")
  scope.dispose()
  inspect(r.is_disposed(), content="true")
}

///|
test "scope: mixed cells all disposed together" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  let s1 = scope.input(1)
  let s2 = scope.input(2)
  let m = scope.derived(fn() { s1.get() + s2.get() })
  let hm = scope.reachable_derived(fn() { m.get_or_abort() * 10 })
  let _ = hm.read_or_abort()
  scope.dispose()
  inspect(s1.is_disposed(), content="true")
  inspect(s2.is_disposed(), content="true")
  inspect(m.is_disposed(), content="true")
  inspect(hm.is_disposed(), content="true")
}

///|
test "panic scope: input on disposed scope aborts" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  scope.dispose()
  let _ = scope.input(1)
}

///|
test "panic scope: memo on disposed scope aborts" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  scope.dispose()
  let _ = scope.derived(fn() { 1 })
}

///|
test "scope: add_observer disposes observer on scope dispose" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 10)
  let d = Derived::Derived(rt, fn() { sig.get() * 2 })
  let scope = Scope::new(rt)
  let obs = scope.add_observer(d.observe())
  inspect(obs.get(), content="20")
  inspect(obs.is_disposed(), content="false")
  scope.dispose()
  inspect(obs.is_disposed(), content="true")
}

///|
test "scope: manual observer dispose before scope dispose is safe" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let d = Derived::Derived(rt, fn() { sig.get() })
  let scope = Scope::new(rt)
  let obs = scope.add_observer(d.observe())
  obs.dispose()
  inspect(obs.is_disposed(), content="true")
  scope.dispose()
}

///|
test "scope: observer disposed before owned cells" {
  let rt = Runtime::Runtime()
  let scope = Scope::new(rt)
  let sig = scope.input(10)
  let m = scope.derived(fn() { sig.get() * 2 })
  let obs = scope.add_observer(m.observe())
  ignore(obs.get())
  scope.dispose()
  inspect(obs.is_disposed(), content="true")
  assert_true(m.is_disposed())
}

///|
test "panic scope: add_observer on disposed scope aborts" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let d = Derived::Derived(rt, fn() { sig.get() })
  let scope = Scope::new(rt)
  scope.dispose()
  ignore(scope.add_observer(d.observe()))
}
