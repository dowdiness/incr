///|
test "phase: starts at Idle" {
  let rt = Runtime::new()
  inspect(rt.core.phase, content="Idle")
}

///|
test "phase: enter and leave PushPropagating" {
  let rt = Runtime::new()
  rt.enter_phase(PushPropagating)
  inspect(rt.core.phase, content="PushPropagating")
  rt.leave_phase()
  inspect(rt.core.phase, content="Idle")
}

///|
test "phase: enter and leave InFixpoint" {
  let rt = Runtime::new()
  rt.enter_phase(InFixpoint)
  inspect(rt.core.phase, content="InFixpoint")
  rt.leave_phase()
  inspect(rt.core.phase, content="Idle")
}

///|
test "phase: enter and leave GarbageCollecting" {
  let rt = Runtime::new()
  rt.enter_phase(GarbageCollecting)
  inspect(rt.core.phase, content="GarbageCollecting")
  rt.leave_phase()
  inspect(rt.core.phase, content="Idle")
}

///|
test "panic phase: enter PushPropagating while InFixpoint" {
  let rt = Runtime::new()
  rt.enter_phase(InFixpoint)
  rt.enter_phase(PushPropagating) |> ignore
}

///|
test "panic phase: enter InFixpoint while PushPropagating" {
  let rt = Runtime::new()
  rt.enter_phase(PushPropagating)
  rt.enter_phase(InFixpoint) |> ignore
}

///|
test "panic phase: enter GarbageCollecting while InFixpoint" {
  let rt = Runtime::new()
  rt.enter_phase(InFixpoint)
  rt.enter_phase(GarbageCollecting) |> ignore
}

///|
test "phase: gc returns to Idle after completion" {
  let rt = Runtime::new()
  rt.gc()
  inspect(rt.core.phase, content="Idle")
}
