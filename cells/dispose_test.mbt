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
