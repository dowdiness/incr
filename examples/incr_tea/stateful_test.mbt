///|
priv struct SModel {
  count : Int
} derive(Eq, Debug)

///|
priv enum SMsg {
  Inc
  Dec
  Reset
} derive(Eq)

///|
fn s_update(msg : SMsg, model : SModel) -> SModel {
  match msg {
    Inc => { count: model.count + 1 }
    Dec => { count: model.count - 1 }
    Reset => { count: 0 }
  }
}

///|
fn s_view(model : SModel) -> Int {
  model.count
}

///|
test "stateful: initial view reflects initial model" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful(
    runtime,
    { count: 0 },
    s_update,
    s_view,
  )
  inspect(program.read_view_or_abort(), content="0")
  program.dispose()
}

///|
test "stateful: dispatch updates view" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful(
    runtime,
    { count: 0 },
    s_update,
    s_view,
  )
  ignore(program.dispatch(Inc))
  inspect(program.read_view_or_abort(), content="1")
  program.dispose()
}

///|
test "stateful: multiple dispatches accumulate correctly" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful(
    runtime,
    { count: 0 },
    s_update,
    s_view,
  )
  ignore(program.dispatch(Inc))
  ignore(program.dispatch(Inc))
  ignore(program.dispatch(Dec))
  inspect(program.read_view_or_abort(), content="1")
  program.dispose()
}

///|
test "stateful: disposal makes dispatch return false and view return None" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful(
    runtime,
    { count: 0 },
    s_update,
    s_view,
  )
  program.dispose()
  inspect(program.is_disposed(), content="true")
  inspect(program.dispatch(Inc), content="false")
  debug_inspect(program.read_view(), content="None")
}

///|
test "stateful: gc after mount preserves watched view" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful(
    runtime,
    { count: 0 },
    s_update,
    s_view,
  )
  runtime.gc()
  ignore(program.dispatch(Inc))
  inspect(program.read_view_or_abort(), content="1")
  program.dispose()
}

///|
test "stateful: subscriptions=None still works correctly" {
  let runtime = @incr.Runtime()
  let program : @incr_tea.Program[SMsg, Int] = @incr_tea.Program::stateful(
    runtime,
    { count: 0 },
    s_update,
    s_view,
    subscriptions=fn(_model) { @hashmap.HashMap([]) },
  )
  ignore(program.dispatch(Inc))
  inspect(program.read_view_or_abort(), content="1")
  program.dispose()
}
