///|
test "memo closure accepts non-raising function (auto-promotion)" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 10)
  let m = Memo::Memo(rt, () => s.get() * 2)
  inspect(read_memo_for_test(m), content="20")
}

///|
test "memo closure accepts raising function" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, 0)
  let m : Memo[Int] = Memo::Memo(rt, () => {
    if s.get() < 0 {
      fail("negative input")
    } else {
      s.get() * 2
    }
  })
  inspect(read_memo_for_test(m), content="0")
}

///|
test "panic memo closure that raises aborts caller" {
  let rt = Runtime::Runtime()
  let s = Signal::Signal(rt, -1)
  let m : Memo[Int] = Memo::Memo(rt, () => {
    if s.get() < 0 {
      fail("negative")
    } else {
      s.get()
    }
  })
  let _ = read_memo_for_test(m)
}
