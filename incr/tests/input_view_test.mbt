///|
test "input view: tracks source updates" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 10)
  let view : @incr.InputView[Int] = input[:]
  let derived = @incr.Derived(rt, () => view.get() + 1)

  inspect(derived.read_or_abort(), content="11")
  input.set(20)
  inspect(derived.read_or_abort(), content="21")
  inspect(input.as_view().get(), content="20")
}

///|
test "input view: field view peek does not track" {
  let rt = @incr.Runtime()
  let field = @incr.InputField(rt, 3)
  let view : @incr.InputView[Int] = field[:]
  inspect(field.as_view().get(), content="3")
  let mut runs = 0
  let derived = @incr.Derived(rt, () => {
    runs = runs + 1
    view.peek() + 1
  })

  inspect(derived.read_or_abort(), content="4")
  inspect(runs, content="1")
  field.set(4)
  inspect(derived.read_or_abort(), content="4")
  inspect(runs, content="1")
}

///|
test "panic input view: get after source disposal aborts" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1)
  let view = input[:]
  input.dispose()
  ignore(view.get())
}
