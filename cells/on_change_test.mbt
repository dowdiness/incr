///|
test "on_change fires on signal set" {
  let rt = Runtime::Runtime()
  let mut count = 0
  rt.set_on_change(() => count = count + 1)
  let s = Signal::Signal(rt, 0)
  s.set(1)
  inspect(count, content="1")
  s.set(2)
  inspect(count, content="2")
}

///|
test "on_change does not fire on same value" {
  let rt = Runtime::Runtime()
  let mut count = 0
  rt.set_on_change(() => count = count + 1)
  let s = Signal::Signal(rt, 0)
  s.set(0)
  inspect(count, content="0")
}

///|
test "on_change fires once at batch end" {
  let rt = Runtime::Runtime()
  let mut count = 0
  rt.set_on_change(() => count = count + 1)
  let a = Signal::Signal(rt, 0)
  let b = Signal::Signal(rt, 0)
  rt.batch(() => {
    a.set(1)
    b.set(2)
  })
  inspect(count, content="1")
}

///|
test "on_change does not fire on batch revert" {
  let rt = Runtime::Runtime()
  let mut count = 0
  rt.set_on_change(() => count = count + 1)
  let s = Signal::Signal(rt, 0)
  rt.batch(() => {
    s.set(5)
    s.set(0)
  })
  inspect(count, content="0")
}

///|
test "on_change with set_unconditional" {
  let rt = Runtime::Runtime()
  let mut count = 0
  rt.set_on_change(() => count = count + 1)
  let s = Signal::Signal(rt, 0)
  s.set_unconditional(0)
  inspect(count, content="1")
}

///|
test "clear_on_change stops notifications" {
  let rt = Runtime::Runtime()
  let mut count = 0
  rt.set_on_change(() => count = count + 1)
  let s = Signal::Signal(rt, 0)
  s.set(1)
  inspect(count, content="1")
  rt.clear_on_change()
  s.set(2)
  inspect(count, content="1")
}

///|
test "on_change does not fire during batch" {
  let rt = Runtime::Runtime()
  let mut fired_during_batch = false
  let mut check_inside_batch = false
  let s = Signal::Signal(rt, 0)
  rt.set_on_change(() => fired_during_batch = true)
  rt.batch(() => {
    s.set(1)
    check_inside_batch = fired_during_batch
  })
  inspect(check_inside_batch, content="false")
  inspect(fired_during_batch, content="true")
}

///|
test "on_change with memo and backdating" {
  let rt = Runtime::Runtime()
  let mut count = 0
  rt.set_on_change(() => count = count + 1)
  let x = Signal::Signal(rt, 10)
  let parity = Memo::Memo(rt, () => x.get() % 2 == 0)
  inspect(rt.read(parity), content="true")
  x.set(12)
  inspect(count, content="1")
  inspect(rt.read(parity), content="true")
}

///|
test "on_change optional param fires on signal set" {
  let mut count = 0
  let rt = Runtime::Runtime(on_change=() => count = count + 1)
  let s = Signal::Signal(rt, 0)
  s.set(1)
  inspect(count, content="1")
}

///|
test "on_change optional param defaults to none" {
  let count = 0
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 0)
  s.set(1)
  inspect(count, content="0")
}

///|
test "on_change fires for relation-derived updates via fixpoint" {
  let rt = Runtime::Runtime()
  let mut count = 0
  rt.set_on_change(() => count = count + 1)
  let edge : Relation[(String, String)] = Relation::Relation(rt)
  let path : Relation[(String, String)] = Relation::Relation(rt)
  let _ = rt.new_rule([edge.id()], [path.id()], () => {
    for e in edge.delta_iter() {
      path.insert(e) |> ignore
    }
  })
  edge.insert(("a", "b")) |> ignore
  rt.fixpoint()
  inspect(count, content="1")
  rt.fixpoint()
  inspect(count, content="1")
}
