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
  inspect(read_memo_for_test(parity), content="true")
  x.set(12)
  inspect(count, content="1")
  inspect(read_memo_for_test(parity), content="true")
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
// --- Composable on-change listeners (#210) ---

///|
test "add_on_change_listener: two additive listeners both fire in registration order" {
  let rt = Runtime::Runtime()
  let mut log = ""
  rt.add_on_change_listener(() => log = log + "a") |> ignore
  rt.add_on_change_listener(() => log = log + "b") |> ignore
  let s = Signal::Signal(rt, 0)
  s.set(1)
  inspect(log, content="ab")
}

///|
test "remove_on_change_listener: stops that listener and is idempotent" {
  let rt = Runtime::Runtime()
  let mut count = 0
  let id = rt.add_on_change_listener(() => count = count + 1)
  let s = Signal::Signal(rt, 0)
  s.set(1)
  inspect(count, content="1")
  rt.remove_on_change_listener(id)
  s.set(2)
  inspect(count, content="1")
  // Removing again is a no-op, not an error.
  rt.remove_on_change_listener(id)
  s.set(3)
  inspect(count, content="1")
}

///|
test "set_on_change singleton coexists with additive listeners" {
  let rt = Runtime::Runtime()
  let mut log = ""
  rt.set_on_change(() => log = log + "S")
  rt.add_on_change_listener(() => log = log + "a") |> ignore
  let s = Signal::Signal(rt, 0)
  s.set(1)
  inspect(log, content="Sa")
}

///|
test "set_on_change replaces the singleton in place (position preserved)" {
  let rt = Runtime::Runtime()
  let mut log = ""
  rt.set_on_change(() => log = log + "S1")
  rt.add_on_change_listener(() => log = log + "a") |> ignore
  rt.set_on_change(() => log = log + "S2")
  let s = Signal::Signal(rt, 0)
  s.set(1)
  inspect(log, content="S2a")
}

///|
test "clear_on_change then set_on_change re-appends at the end" {
  let rt = Runtime::Runtime()
  let mut log = ""
  rt.set_on_change(() => log = log + "S1")
  rt.add_on_change_listener(() => log = log + "a") |> ignore
  rt.clear_on_change()
  rt.set_on_change(() => log = log + "S2")
  let s = Signal::Signal(rt, 0)
  s.set(1)
  inspect(log, content="aS2")
}

///|
test "on-change mutation during callback takes effect on the next fire (snapshot)" {
  let rt = Runtime::Runtime()
  let mut log = ""
  let mut added = false
  rt.add_on_change_listener(() => {
    log = log + "a"
    if added {
      ()
    } else {
      added = true
      rt.add_on_change_listener(() => log = log + "b") |> ignore
    }
  })
  |> ignore
  let s = Signal::Signal(rt, 0)
  s.set(1)
  // "b" was registered during this fire but is not in the snapshot → not fired.
  inspect(log, content="a")
  s.set(2)
  // second fire: snapshot now includes both, in registration order.
  inspect(log, content="aab")
}

///|
test "remove_on_change_listener with another runtime's id is a no-op (runtime-scoped ListenerId)" {
  let rt1 = Runtime::Runtime()
  let rt2 = Runtime::Runtime()
  let mut count2 = 0
  // The first listener of each runtime would share a bare counter value; the
  // RuntimeId in the id keeps them distinct.
  let id1 = rt1.add_on_change_listener(() => ())
  let _id2 = rt2.add_on_change_listener(() => count2 = count2 + 1)
  inspect(id1 == _id2, content="false")
  // Removing rt1's id from rt2 must not detach rt2's listener.
  rt2.remove_on_change_listener(id1)
  let s2 = Signal::Signal(rt2, 0)
  s2.set(1)
  inspect(count2, content="1")
}

///|
test "add_on_change_listener registered mid-batch participates in the batch-end fire" {
  let rt = Runtime::Runtime()
  let mut log = ""
  rt.add_on_change_listener(() => log = log + "a") |> ignore
  let s = Signal::Signal(rt, 0)
  rt.batch(() => {
    s.set(1)
    rt.add_on_change_listener(() => log = log + "b") |> ignore
  })
  inspect(log, content="ab")
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
