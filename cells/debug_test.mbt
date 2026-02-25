///|
test "Signal derives Debug" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 42)
  debug_inspect(
    s,
    content=(
      #|{
      #|  label: None,
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
  let m = Memo::new(rt, () => s.get() * 2)
  debug_inspect(
    m,
    content=(
      #|{
      #|  label: None,
      #|  rt: ...,
      #|  cell_id: ...,
      #|  compute: <function: ...>,
      #|  value: None,
      #|}
    ),
  )
}

///|
test "Memo derives Debug after compute" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let m = Memo::new(rt, () => s.get() * 2)
  let _ = m.get()
  debug_inspect(
    m,
    content=(
      #|{
      #|  label: None,
      #|  rt: ...,
      #|  cell_id: ...,
      #|  compute: <function: ...>,
      #|  value: Some(20),
      #|}
    ),
  )
}

///|
test "TrackedCell derives Debug" {
  let rt = Runtime::new()
  let cell = TrackedCell::new(rt, 42, label="test")
  debug_inspect(cell, content="{ signal: ... }")
}
