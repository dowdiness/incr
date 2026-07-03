///|
test "Input derives Debug" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 42)
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
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 10)
  let m = Derived::Derived(rt, () => s.get() * 2)
  debug_inspect(
    m,
    content=(
      #|{
      #|  label: None,
      #|  rt: ...,
      #|  cell_id: ...,
      #|  compute: <function: ...>,
      #|  is_static: false,
      #|  backdate_eq: <function: ...>,
      #|  value: None,
      #|}
    ),
  )
}

///|
test "Memo derives Debug after compute" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 10)
  let m = Derived::Derived(rt, () => s.get() * 2)
  let _ = m.read_or_abort()
  debug_inspect(
    m,
    content=(
      #|{
      #|  label: None,
      #|  rt: ...,
      #|  cell_id: ...,
      #|  compute: <function: ...>,
      #|  is_static: false,
      #|  backdate_eq: <function: ...>,
      #|  value: Some(20),
      #|}
    ),
  )
}

///|
test "InputField derives Debug" {
  let rt = Runtime::Runtime()
  let cell = InputField::InputField(rt, 42, label="test")
  debug_inspect(cell, content="{ input: ... }")
}
