///|
test "input label stored in PullInputData" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0, label="my_input")
  let data = rt.get_pull_input(sig.id())
  debug_inspect(data.meta.label, content="Some(\"my_input\")")
}

///|
test "input None label stored in PullInputData" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let data = rt.get_pull_input(sig.id())
  debug_inspect(data.meta.label, content="None")
}
