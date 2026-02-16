///|
test "memo: id() returns valid CellId" {
  let rt = Runtime::new()
  let m = Memo::new(rt, fn() { 42 })
  let id = m.id()
  inspect(id.id >= 0, content="true")
}

///|
test "memo: dependencies() returns empty before computation" {
  let rt = Runtime::new()
  let m = Memo::new(rt, fn() { 10 })
  inspect(m.dependencies(), content="[]")
}

///|
test "memo: dependencies() includes all inputs after computation" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 1)
  let y = Signal::new(rt, 2)
  let sum = Memo::new(rt, fn() { x.get() + y.get() })

  sum.get() |> ignore
  let deps = sum.dependencies()
  inspect(deps.length(), content="2")
  inspect(deps.contains(x.id()), content="true")
  inspect(deps.contains(y.id()), content="true")
}

///|
test "memo: changed_at and verified_at track revisions" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 5)
  x.set(10)  // Bump revision to 1
  let doubled = Memo::new(rt, fn() { x.get() * 2 })

  doubled.get() |> ignore
  let initial_changed = doubled.changed_at()
  let initial_verified = doubled.verified_at()

  inspect(initial_changed.value > 0, content="true")
  inspect(initial_verified.value > 0, content="true")

  // Change input
  x.set(20)
  doubled.get() |> ignore

  inspect(doubled.changed_at().value > initial_changed.value, content="true")
  inspect(doubled.verified_at().value > initial_verified.value, content="true")
}

///|
test "memo: dependencies update on recomputation" {
  let rt = Runtime::new()
  let cond = Signal::new(rt, true)
  let a = Signal::new(rt, 1)
  let b = Signal::new(rt, 2)

  let dynamic = Memo::new(rt, fn() {
    if cond.get() { a.get() } else { b.get() }
  })

  dynamic.get() |> ignore
  let deps1 = dynamic.dependencies()
  inspect(deps1.contains(a.id()), content="true")
  inspect(deps1.contains(b.id()), content="false")

  cond.set(false)
  dynamic.get() |> ignore
  let deps2 = dynamic.dependencies()
  inspect(deps2.contains(a.id()), content="false")
  inspect(deps2.contains(b.id()), content="true")
}
