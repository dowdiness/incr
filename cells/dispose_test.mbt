///|
test "signal: dispose marks cell as disposed" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  assert_false(sig.is_disposed())
  sig.dispose()
  assert_true(sig.is_disposed())
}

///|
test "signal: dispose is idempotent" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  sig.dispose()
  sig.dispose() // second call is no-op, no abort
  assert_true(sig.is_disposed())
}

///|
test "panic signal: get after dispose aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  sig.dispose()
  ignore(sig.get()) // should abort
}

///|
test "memo: dispose marks cell as disposed" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get()) // prime
  assert_false(m.is_disposed())
  m.dispose()
  assert_true(m.is_disposed())
}

///|
test "memo: dispose is idempotent" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get())
  m.dispose()
  m.dispose() // no-op
  assert_true(m.is_disposed())
}

///|
test "panic memo: get after dispose aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m.get())
  m.dispose()
  ignore(m.get()) // should abort
}

///|
test "memo: dispose then new memo works independently" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m1 = Memo::new(rt, fn() { sig.get() * 2 })
  ignore(m1.get())
  m1.dispose()
  let m2 = Memo::new(rt, fn() { sig.get() * 3 })
  assert_eq(m2.get(), 30)
  assert_true(m1.is_disposed())
  assert_false(m2.is_disposed())
}

///|
test "hybrid memo: is_disposed returns correct state" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let h = HybridMemo::new(rt, fn() { sig.get() * 2 })
  ignore(h.get())
  assert_false(h.is_disposed())
  h.dispose()
  assert_true(h.is_disposed())
}
