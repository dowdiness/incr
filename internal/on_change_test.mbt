///|
test "on_change fires on signal set" {
  let rt = Runtime::new()
  let mut count = 0
  rt.set_on_change(fn() { count = count + 1 })
  let s = Signal::new(rt, 0)
  s.set(1)
  inspect(count, content="1")
  s.set(2)
  inspect(count, content="2")
}

///|
test "on_change does not fire on same value" {
  let rt = Runtime::new()
  let mut count = 0
  rt.set_on_change(fn() { count = count + 1 })
  let s = Signal::new(rt, 0)
  s.set(0)
  inspect(count, content="0")
}

///|
test "on_change fires once at batch end" {
  let rt = Runtime::new()
  let mut count = 0
  rt.set_on_change(fn() { count = count + 1 })
  let a = Signal::new(rt, 0)
  let b = Signal::new(rt, 0)
  rt.batch(fn() {
    a.set(1)
    b.set(2)
  })
  inspect(count, content="1")
}

///|
test "on_change does not fire on batch revert" {
  let rt = Runtime::new()
  let mut count = 0
  rt.set_on_change(fn() { count = count + 1 })
  let s = Signal::new(rt, 0)
  rt.batch(fn() {
    s.set(5)
    s.set(0)
  })
  inspect(count, content="0")
}

///|
test "on_change with set_unconditional" {
  let rt = Runtime::new()
  let mut count = 0
  rt.set_on_change(fn() { count = count + 1 })
  let s = Signal::new(rt, 0)
  s.set_unconditional(0)
  inspect(count, content="1")
}

///|
test "clear_on_change stops notifications" {
  let rt = Runtime::new()
  let mut count = 0
  rt.set_on_change(fn() { count = count + 1 })
  let s = Signal::new(rt, 0)
  s.set(1)
  inspect(count, content="1")
  rt.clear_on_change()
  s.set(2)
  inspect(count, content="1")
}

///|
test "on_change does not fire during batch" {
  let rt = Runtime::new()
  let mut fired_during_batch = false
  let mut check_inside_batch = false
  let s = Signal::new(rt, 0)
  rt.set_on_change(fn() { fired_during_batch = true })
  rt.batch(fn() {
    s.set(1)
    check_inside_batch = fired_during_batch
  })
  inspect(check_inside_batch, content="false")
  inspect(fired_during_batch, content="true")
}

///|
test "on_change with memo and backdating" {
  let rt = Runtime::new()
  let mut count = 0
  rt.set_on_change(fn() { count = count + 1 })
  let x = Signal::new(rt, 10)
  let parity = Memo::new(rt, fn() { x.get() % 2 == 0 })
  inspect(parity.get(), content="true")
  x.set(12)
  inspect(count, content="1")
  inspect(parity.get(), content="true")
}

///|
test "on_change optional param fires on signal set" {
  let mut count = 0
  let rt = Runtime::new(on_change=fn() { count = count + 1 })
  let s = Signal::new(rt, 0)
  s.set(1)
  inspect(count, content="1")
}

///|
test "on_change optional param defaults to none" {
  let count = 0
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  s.set(1)
  inspect(count, content="0")
}
