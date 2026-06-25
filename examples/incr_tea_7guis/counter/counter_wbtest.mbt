///|
test "counter dispatch updates view state" {
  let runtime = @incr.Runtime()
  let program : @tea.Program[Msg, @tea.Html[Msg]] = @tea.Program::stateful(
    runtime,
    { count: 0 },
    update_model,
    view_model,
    label="7guis.counter.view",
  )
  let initial = program.read_view_or_abort()
  ignore(program.dispatch(Increment))
  let after_increment = program.read_view_or_abort()

  inspect(initial == view_model({ count: 0 }), content="true")
  inspect(after_increment == view_model({ count: 1 }), content="true")
  inspect(initial == after_increment, content="false")
  program.dispose()
}
