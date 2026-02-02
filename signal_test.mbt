///|
test "signal: create and read" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  inspect(sig.get(), content="42")
}

///|
test "signal: write updates value" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  sig.set(20)
  inspect(sig.get(), content="20")
}

///|
test "signal: write bumps revision" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  inspect(rt.current_revision.value, content="0")
  sig.set(2)
  inspect(rt.current_revision.value, content="1")
  sig.set(3)
  inspect(rt.current_revision.value, content="2")
}

///|
test "signal: same-value set is no-op" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  sig.set(42)
  // Revision should not have bumped
  inspect(rt.current_revision.value, content="0")
}

///|
test "signal: set_unconditional always bumps" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  sig.set_unconditional(42)
  // Revision bumps even though value is the same
  inspect(rt.current_revision.value, content="1")
}

///|
test "signal: multiple signals independent" {
  let rt = Runtime::new()
  let a = Signal::new(rt, "hello")
  let b = Signal::new(rt, "world")
  inspect(a.get(), content="hello")
  inspect(b.get(), content="world")
  a.set("hi")
  inspect(a.get(), content="hi")
  inspect(b.get(), content="world")
  inspect(rt.current_revision.value, content="1")
}

///|
test "signal: string values" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, "initial")
  sig.set("updated")
  inspect(sig.get(), content="updated")
  sig.set("updated") // same value, no bump
  inspect(rt.current_revision.value, content="1")
}
