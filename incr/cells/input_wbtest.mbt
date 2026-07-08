///|
test "input: create and read" {
  let rt = Runtime()
  let sig = Input(rt, 42)
  inspect(sig.get(), content="42")
}

///|
test "input: write updates value" {
  let rt = Runtime()
  let sig = Input(rt, 10)
  sig.set(20)
  inspect(sig.get(), content="20")
}

///|
test "input: write bumps revision" {
  let rt = Runtime()
  let sig = Input(rt, 1)
  inspect(rt.core.revision.current_revision.value, content="0")
  sig.set(2)
  inspect(rt.core.revision.current_revision.value, content="1")
  sig.set(3)
  inspect(rt.core.revision.current_revision.value, content="2")
}

///|
test "input: same-value set is no-op" {
  let rt = Runtime()
  let sig = Input(rt, 42)
  sig.set(42)
  // Revision should not have bumped
  inspect(rt.core.revision.current_revision.value, content="0")
}

///|
test "input: force_set always bumps" {
  let rt = Runtime()
  let sig = Input(rt, 42)
  sig.force_set(42)
  // Revision bumps even though value is the same
  inspect(rt.core.revision.current_revision.value, content="1")
}

///|
test "input: multiple inputs independent" {
  let rt = Runtime()
  let a = Input(rt, "hello")
  let b = Input(rt, "world")
  inspect(a.get(), content="hello")
  inspect(b.get(), content="world")
  a.set("hi")
  inspect(a.get(), content="hi")
  inspect(b.get(), content="world")
  inspect(rt.core.revision.current_revision.value, content="1")
}

///|
test "input: string values" {
  let rt = Runtime()
  let sig = Input(rt, "initial")
  sig.set("updated")
  inspect(sig.get(), content="updated")
  sig.set("updated") // same value, no bump
  inspect(rt.core.revision.current_revision.value, content="1")
}

///|
test "panic input: force_set inside derived compute aborts" {
  let rt = Runtime()
  let a = Input(rt, 0, label="a")
  let b = Input(rt, 0, label="b")
  let d = Derived(rt, fn() {
    b.force_set(a.get() + 1)
    a.get()
  })
  // Read once to subscribe: the Derived now depends on a.
  // a.set(1) will trigger recompute inside a tracking context.
  let _ = d.get()
  a.set(1)
}

///|
test "panic input: force_set inside push-reactive compute aborts" {
  let rt = Runtime()
  let a = Input(rt, 0, label="a")
  let b = Input(rt, 0, label="b")
  let d = EagerDerived(rt, fn() -> Bool {
    b.force_set(a.get() + 1)
    true
  })
  let _ = d.read()
  a.set(1)
}

///|
test "input: force_set in on_change callback is allowed" {
  let rt = Runtime()
  let a = Input(rt, 0, label="a")
  let b = Input(rt, 0, label="b")
  a.on_change(fn(v : Int) { b.force_set(v * 2) })
  a.set(10)
  inspect(b.get(), content="20")
}
