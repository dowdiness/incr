///|
test "derived closure accepts non-raising function (auto-promotion)" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 10)
  let m = Derived(rt, () => s.get() * 2)
  inspect(m.read_or_abort(), content="20")
}

///|
test "derived closure accepts raising function" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 0)
  let m : Derived[Int] = Derived(rt, () => {
    if s.get() < 0 {
      fail("negative input")
    } else {
      s.get() * 2
    }
  })
  inspect(m.read_or_abort(), content="0")
}

///|
test "panic derived closure that raises aborts caller" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, -1)
  let m : Derived[Int] = Derived(rt, () => {
    if s.get() < 0 {
      fail("negative")
    } else {
      s.get()
    }
  })
  let _ = m.read_or_abort()
}
