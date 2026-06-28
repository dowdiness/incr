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
