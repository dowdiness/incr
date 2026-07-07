///|
test "phase: starts at Idle" {
  let core = new_runtime_core_for_wbtest()
  inspect(core.phase, content="Idle")
}

///|
test "phase: enter and leave PushPropagating" {
  let core = new_runtime_core_for_wbtest()
  enter_phase(core, PushPropagating)
  inspect(core.phase, content="PushPropagating")
  leave_phase(core)
  inspect(core.phase, content="Idle")
}

///|
test "phase: enter and leave InFixpoint" {
  let core = new_runtime_core_for_wbtest()
  enter_phase(core, InFixpoint)
  inspect(core.phase, content="InFixpoint")
  leave_phase(core)
  inspect(core.phase, content="Idle")
}

///|
test "phase: enter and leave GarbageCollecting" {
  let core = new_runtime_core_for_wbtest()
  enter_phase(core, GarbageCollecting)
  inspect(core.phase, content="GarbageCollecting")
  leave_phase(core)
  inspect(core.phase, content="Idle")
}

///|
test "panic phase: enter PushPropagating while InFixpoint" {
  let core = new_runtime_core_for_wbtest()
  enter_phase(core, InFixpoint)
  enter_phase(core, PushPropagating)
}

///|
test "panic phase: enter InFixpoint while PushPropagating" {
  let core = new_runtime_core_for_wbtest()
  enter_phase(core, PushPropagating)
  enter_phase(core, InFixpoint)
}

///|
test "panic phase: enter GarbageCollecting while InFixpoint" {
  let core = new_runtime_core_for_wbtest()
  enter_phase(core, InFixpoint)
  enter_phase(core, GarbageCollecting)
}
