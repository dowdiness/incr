///|
/// Managed command value for the experimental TEA scheduler.
///
/// A `Cmd` describes follow-up work returned by `update`. The program
/// scheduler executes commands after the current `Runtime::batch` commits.
/// Post-render commands are queued for the browser renderer's next flush.
pub struct Cmd[Msg] {
  priv command : Command[Msg]
}

///|
priv enum Command[Msg] {
  None
  Batch(Array[Cmd[Msg]])
  Message(Msg)
  Effect(((Cmd[Msg]) -> Unit) -> Unit)
  AfterFlush(((Cmd[Msg]) -> Unit) -> Unit)
}

///|
fn[Msg] Cmd::Cmd(command : Command[Msg]) -> Cmd[Msg] {
  { command, }
}

///|
/// Returns a command that does nothing.
pub fn[Msg] Cmd::none() -> Cmd[Msg] {
  Cmd(None)
}

///|
/// Enqueues a follow-up message after the current model batch commits.
pub fn[Msg] Cmd::message(msg : Msg) -> Cmd[Msg] {
  Cmd(Message(msg))
}

///|
/// Snapshots and runs commands in deterministic left-to-right order.
pub fn[Msg] Cmd::batch(cmds : ArrayView[Cmd[Msg]]) -> Cmd[Msg] {
  Cmd(Batch(cmds.to_owned()))
}

///|
/// Low-level synchronous effect hook.
///
/// The callback runs outside tracked view computations and can enqueue more
/// commands through its argument. It runs before the browser renderer's next DOM
/// flush; use `after_flush` for DOM work that needs newly rendered nodes.
/// Checked failures are intentionally unsupported in this prototype; represent
/// recoverable failures as messages carrying `Result`.
pub fn[Msg] Cmd::effect(callback : ((Cmd[Msg]) -> Unit) -> Unit) -> Cmd[Msg] {
  Cmd(Effect(callback))
}

///|
/// Runs a low-level effect after the browser renderer has flushed DOM patches.
///
/// The callback stays outside cacheable `Html` values and can enqueue more
/// commands through its argument. `after_flush` callbacks enqueued while this
/// phase is already draining wait for a later flush. This is the experimental
/// escape hatch for DOM work such as focusing a newly rendered inline editor.
pub fn[Msg] Cmd::after_flush(
  callback : ((Cmd[Msg]) -> Unit) -> Unit,
) -> Cmd[Msg] {
  Cmd(AfterFlush(callback))
}
