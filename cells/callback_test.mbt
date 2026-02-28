///|
test "Signal callback fires on value change" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let called : Ref[Bool] = { val: false }
  let received : Ref[Int] = { val: 0 }
  s.on_change(v => {
    called.val = true
    received.val = v
  })
  s.set(42)
  inspect(called.val, content="true")
  inspect(received.val, content="42")
}

///|
test "Signal callback does not fire on same value" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 5)
  let count : Ref[Int] = { val: 0 }
  s.on_change(_v => count.val = count.val + 1)
  s.set(5)
  inspect(count.val, content="0")
}

///|
test "Memo callback fires on get() when value changed" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let m = Memo::new(rt, () => s.get() * 10)
  let _ = m.get()
  let received : Ref[Int] = { val: 0 }
  m.on_change(v => received.val = v)
  s.set(2)
  let _ = m.get()
  inspect(received.val, content="20")
}

///|
test "Memo callback does not fire when value backdated" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 2)
  let m = Memo::new(rt, () => s.get() * 0 + 1)
  let _ = m.get()
  let count : Ref[Int] = { val: 0 }
  m.on_change(_v => count.val = count.val + 1)
  s.set(4)
  let _ = m.get()
  inspect(count.val, content="0")
}

///|
test "per-cell callback fires before global on_change" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let order : Ref[String] = { val: "" }
  s.on_change(_v => order.val = order.val + "cell ")
  rt.set_on_change(() => order.val = order.val + "global")
  s.set(1)
  inspect(order.val, content="cell global")
}

///|
test "clear_on_change removes Signal callback" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let count : Ref[Int] = { val: 0 }
  s.on_change(_v => count.val = count.val + 1)
  s.set(1)
  s.clear_on_change()
  s.set(2)
  inspect(count.val, content="1")
}

///|
test "batch: per-cell callbacks fire once per changed signal" {
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 0)
  let s2 = Signal::new(rt, 0)
  let count1 : Ref[Int] = { val: 0 }
  let count2 : Ref[Int] = { val: 0 }
  s1.on_change(_v => count1.val = count1.val + 1)
  s2.on_change(_v => count2.val = count2.val + 1)
  rt.batch(() => {
    s1.set(1)
    s2.set(1)
  })
  inspect(count1.val, content="1")
  inspect(count2.val, content="1")
}

///|
test "batch: callback re-entrancy — set inside on_change is handled correctly" {
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 0)
  let s2 = Signal::new(rt, 0)
  let count1 : Ref[Int] = { val: 0 }
  let count2 : Ref[Int] = { val: 0 }
  s2.on_change(_v => count2.val = count2.val + 1)
  s1.on_change(_v => {
    count1.val = count1.val + 1
    s2.set(1)
  })
  rt.batch(() => s1.set(1))
  inspect(count1.val, content="1")
  inspect(count2.val, content="1")
}

///|
test "batch: global on_change fires once per commit_batch call when callback sets another signal" {
  // When s1's on_change callback sets s2, commit_batch calls itself recursively
  // to commit s2. fire_on_change() is called unconditionally at the end of each
  // commit_batch invocation — including the recursive one — so the global
  // callback fires TWICE: once after s2 commits (recursive call) and once after
  // s1 commits (outer call).
  //
  // NOTE: The api-reference documents "fires once at batch end", which conflicts
  // with this behaviour. This test captures the actual implementation so any
  // future fix is caught as a deliberate change.
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 0)
  let s2 = Signal::new(rt, 0)
  let global_count : Ref[Int] = { val: 0 }
  rt.set_on_change(() => { global_count.val = global_count.val + 1 })
  s1.on_change(_v => s2.set(1))
  rt.batch(() => s1.set(1))
  // Fires twice: once for the s2 commit (recursive), once for the s1 commit (outer)
  inspect(global_count.val, content="2")
  inspect(s1.get(), content="1")
  inspect(s2.get(), content="1")
}

///|
test "clear_on_change removes Memo callback" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let m = Memo::new(rt, () => s.get() * 2)
  let _ = m.get()
  let count : Ref[Int] = { val: 0 }
  m.on_change(_v => count.val = count.val + 1)
  s.set(1)
  let _ = m.get()
  m.clear_on_change()
  s.set(2)
  let _ = m.get()
  inspect(count.val, content="1")
}
