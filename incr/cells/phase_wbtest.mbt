///|
// enter_phase/leave_phase transition tests live in the owning kernel package
// (internal/kernel/phase_wbtest.mbt). This case stays here because it drives
// the full Runtime::gc() coordinator path, which is a cells/ concern.
test "phase: gc returns to Idle after completion" {
  let rt = Runtime::Runtime()
  rt.gc()
  inspect(rt.core.phase, content="Idle")
}
