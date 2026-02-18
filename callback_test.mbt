///|
test "Signal callback fires on value change" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let called : Ref[Bool] = { val: false }
  let received : Ref[Int] = { val: 0 }
  s.on_change(fn(v) {
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
  s.on_change(fn(_v) { count.val = count.val + 1 })
  s.set(5)
  inspect(count.val, content="0")
}

///|
test "Memo callback fires on get() when value changed" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { s.get() * 10 })
  let _ = m.get()
  let received : Ref[Int] = { val: 0 }
  m.on_change(fn(v) { received.val = v })
  s.set(2)
  let _ = m.get()
  inspect(received.val, content="20")
}

///|
test "Memo callback does not fire when value backdated" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 2)
  let m = Memo::new(rt, fn() { s.get() * 0 + 1 })
  let _ = m.get()
  let count : Ref[Int] = { val: 0 }
  m.on_change(fn(_v) { count.val = count.val + 1 })
  s.set(4)
  let _ = m.get()
  inspect(count.val, content="0")
}

///|
test "per-cell callback fires before global on_change" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let order : Ref[String] = { val: "" }
  s.on_change(fn(_v) { order.val = order.val + "cell " })
  rt.set_on_change(fn() { order.val = order.val + "global" })
  s.set(1)
  inspect(order.val, content="cell global")
}

///|
test "clear_on_change removes Signal callback" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let count : Ref[Int] = { val: 0 }
  s.on_change(fn(_v) { count.val = count.val + 1 })
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
  s1.on_change(fn(_v) { count1.val = count1.val + 1 })
  s2.on_change(fn(_v) { count2.val = count2.val + 1 })
  rt.batch(fn() {
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
  s2.on_change(fn(_v) { count2.val = count2.val + 1 })
  s1.on_change(fn(_v) {
    count1.val = count1.val + 1
    s2.set(1)
  })
  rt.batch(fn() { s1.set(1) })
  inspect(count1.val, content="1")
  inspect(count2.val, content="1")
}

///|
test "clear_on_change removes Memo callback" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let m = Memo::new(rt, fn() { s.get() * 2 })
  let _ = m.get()
  let count : Ref[Int] = { val: 0 }
  m.on_change(fn(_v) { count.val = count.val + 1 })
  s.set(1)
  let _ = m.get()
  m.clear_on_change()
  s.set(2)
  let _ = m.get()
  inspect(count.val, content="1")
}
