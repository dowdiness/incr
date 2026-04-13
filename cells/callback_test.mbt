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
  let _ = rt.read(m)
  let received : Ref[Int] = { val: 0 }
  m.on_change(v => received.val = v)
  s.set(2)
  let _ = rt.read(m)
  inspect(received.val, content="20")
}

///|
test "Memo callback does not fire when value backdated" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 2)
  let m = Memo::new(rt, () => s.get() * 0 + 1)
  let _ = rt.read(m)
  let count : Ref[Int] = { val: 0 }
  m.on_change(_v => count.val = count.val + 1)
  s.set(4)
  let _ = rt.read(m)
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
test "signal callback sees fresh push-reactive state before memo read" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get() * 10)
  let m = Memo::new(rt, () => r.get() + 1)
  inspect(rt.read(m), content="11")
  let seen_at_callback : Ref[Int] = { val: -1 }
  s.on_change(_v => seen_at_callback.val = rt.read(m))
  s.set(2)
  inspect(seen_at_callback.val, content="21")
  inspect(rt.read(m), content="21")
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
test "non-batch: callback re-entrancy — set inside on_change propagates and memo reads correctly" {
  // Non-batch path: s1.on_change fires synchronously inside set_unconditional,
  // BEFORE s1's own push_propagate_from. Calling s2.set() from within the
  // callback is a recursive set_unconditional that fully completes (including
  // s2's push propagation) before returning. A pull memo that depends on s2
  // must see the post-set s2 value when read after s2.set() in the same callback.
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 0)
  let s2 = Signal::new(rt, 0)
  let m = Memo::new(rt, () => s2.get() * 2)
  let _ = rt.read(m) // prime: m = 0
  let mut count2 = 0
  s2.on_change(_v => count2 = count2 + 1)
  let mut memo_in_callback = -1
  s1.on_change(_v => {
    s2.set(10) // recursive set_unconditional; s2's callbacks fire, push propagates
    memo_in_callback = rt.read(m) // pull-verify: s2 changed → recompute → 20
  })
  s1.set(1)
  inspect(count2, content="1") // s2's on_change ran once during re-entrant call
  inspect(memo_in_callback, content="20") // callback saw updated memo value
  inspect(rt.read(m), content="20")
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
test "batch: callback sees fresh push-reactive state before memo read" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get() * 10)
  let m = Memo::new(rt, () => r.get() + 1)
  inspect(rt.read(m), content="11")
  let seen_at_callback : Ref[Int] = { val: -1 }
  s.on_change(_v => seen_at_callback.val = rt.read(m))
  rt.batch(() => s.set(2))
  inspect(seen_at_callback.val, content="21")
  inspect(rt.read(m), content="21")
}

///|
test "batch: global on_change fires exactly once when callback sets another signal" {
  // When s1's on_change callback sets s2, commit_batch loops to commit s2
  // in a second wave. fire_on_change() is called once after all waves complete.
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 0)
  let s2 = Signal::new(rt, 0)
  let global_count : Ref[Int] = { val: 0 }
  rt.set_on_change(() => global_count.val = global_count.val + 1)
  s1.on_change(_v => s2.set(1))
  rt.batch(() => s1.set(1))
  inspect(global_count.val, content="1")
  inspect(s1.get(), content="1")
  inspect(s2.get(), content="1")
}

///|
test "clear_on_change removes Memo callback" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let m = Memo::new(rt, () => s.get() * 2)
  let _ = rt.read(m)
  let count : Ref[Int] = { val: 0 }
  m.on_change(_v => count.val = count.val + 1)
  s.set(1)
  let _ = rt.read(m)
  m.clear_on_change()
  s.set(2)
  let _ = rt.read(m)
  inspect(count.val, content="1")
}
