///|
test "Signal derives Debug" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 42)
  debug_inspect(
    s,
    content=(
      #|{
      #|  rt: ...,
      #|  cell_id: ...,
      #|  value: 42,
      #|  pending_value: None,
      #|  durability: Low,
      #|}
    ),
  )
}

///|
test "Memo derives Debug before compute" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { s.get() * 2 })
  debug_inspect(
    m,
    content=(
      #|{ rt: ..., cell_id: ..., compute: <function: ...>, value: None }
    ),
  )
}

///|
test "Memo derives Debug after compute" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { s.get() * 2 })
  let _ = m.get()
  debug_inspect(
    m,
    content=(
      #|{ rt: ..., cell_id: ..., compute: <function: ...>, value: Some(20) }
    ),
  )
}
