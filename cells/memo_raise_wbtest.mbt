///|
test "memo closure accepts non-raising function (auto-promotion)" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let m = Memo::new(rt, () => s.get() * 2)
  inspect(rt.read(m), content="20")
}

///|
test "memo closure accepts raising function" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let m : Memo[Int] = Memo::new(rt, () => {
    if s.get() < 0 {
      fail("negative input")
    } else {
      s.get() * 2
    }
  })
  inspect(rt.read(m), content="0")
}

///|
test "panic memo closure that raises aborts caller" {
  let rt = Runtime::new()
  let s = Signal::new(rt, -1)
  let m : Memo[Int] = Memo::new(rt, () => {
    if s.get() < 0 {
      fail("negative")
    } else {
      s.get()
    }
  })
  let _ = rt.read(m)
}
