///|
test "scope: new creates empty scope" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  inspect(scope.is_disposed(), content="false")
}

///|
test "scope: dispose marks scope as disposed" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  scope.dispose()
  inspect(scope.is_disposed(), content="true")
}

///|
test "scope: dispose is idempotent" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  scope.dispose()
  // Second dispose should not abort
  scope.dispose()
  inspect(scope.is_disposed(), content="true")
}

///|
test "scope: child creates nested scope" {
  let rt = Runtime::new()
  let parent = Scope::new(rt)
  let child = parent.child()
  inspect(child.is_disposed(), content="false")
  inspect(parent.is_disposed(), content="false")
}

///|
test "scope: disposing parent disposes children" {
  let rt = Runtime::new()
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
  let rt = Runtime::new()
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
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  scope.dispose()
  let _ = scope.child()
}

///|
test "scope: signal creates cell and registers for disposal" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  let sig = scope.signal(42)
  inspect(sig.get(), content="42")
  scope.dispose()
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: memo creates cell and registers for disposal" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  let sig = scope.signal(10)
  let m = scope.memo(fn() { sig.get() * 2 })
  inspect(rt.read(m), content="20")
  scope.dispose()
  inspect(m.is_disposed(), content="true")
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: hybrid_memo creates cell and registers for disposal" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  let sig = scope.signal(5)
  let hm = scope.hybrid_memo(fn() { sig.get() + 1 })
  inspect(rt.read_hybrid(hm), content="6")
  scope.dispose()
  inspect(hm.is_disposed(), content="true")
}

///|
test "scope: effect creates cell and registers for disposal" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  let ran : Ref[Int] = { val: 0 }
  let sig = scope.signal(1)
  let eff = scope.effect(fn() { ran.val = ran.val + sig.get() })
  inspect(ran.val, content="1")
  scope.dispose()
  inspect(eff.is_disposed(), content="true")
}

///|
test "scope: reactive creates cell and registers for disposal" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  let sig = scope.signal(3)
  let r : Reactive[Int] = scope.reactive(fn() { sig.get() * 3 })
  inspect(rt.read_reactive(r), content="9")
  scope.dispose()
  inspect(r.is_disposed(), content="true")
}

///|
test "scope: mixed cells all disposed together" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  let s1 = scope.signal(1)
  let s2 = scope.signal(2)
  let m = scope.memo(fn() { s1.get() + s2.get() })
  let hm = scope.hybrid_memo(fn() { m.get() * 10 })
  let _ = rt.read_hybrid(hm)
  scope.dispose()
  inspect(s1.is_disposed(), content="true")
  inspect(s2.is_disposed(), content="true")
  inspect(m.is_disposed(), content="true")
  inspect(hm.is_disposed(), content="true")
}

///|
test "panic scope: signal on disposed scope aborts" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  scope.dispose()
  let _ = scope.signal(1)
}

///|
test "panic scope: memo on disposed scope aborts" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  scope.dispose()
  let _ = scope.memo(fn() { 1 })
}

///|
test "scope: add_observer disposes observer on scope dispose" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  let scope = Scope::new(rt)
  let obs = scope.add_observer(m.observe())
  inspect(obs.get(), content="20")
  inspect(obs.is_disposed(), content="false")
  scope.dispose()
  inspect(obs.is_disposed(), content="true")
}

///|
test "scope: manual observer dispose before scope dispose is safe" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let scope = Scope::new(rt)
  let obs = scope.add_observer(m.observe())
  obs.dispose()
  inspect(obs.is_disposed(), content="true")
  scope.dispose()
}

///|
test "scope: observer disposed before owned cells" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  let sig = scope.signal(10)
  let m = scope.memo(fn() { sig.get() * 2 })
  let obs = scope.add_observer(m.observe())
  ignore(obs.get())
  scope.dispose()
  inspect(obs.is_disposed(), content="true")
  assert_true(m.is_disposed())
}

///|
test "panic scope: add_observer on disposed scope aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let scope = Scope::new(rt)
  scope.dispose()
  ignore(scope.add_observer(m.observe()))
}
