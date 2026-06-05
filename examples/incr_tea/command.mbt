///|
/// Managed command value for the experimental TEA scheduler.
///
/// A `Cmd` describes follow-up work returned by `update`. The program
/// scheduler executes commands after the current `Runtime::batch` commits.
pub struct Cmd[Msg] {
  priv command : Command[Msg]
}

///|
priv enum Command[Msg] {
  None
  Batch(Array[Cmd[Msg]])
  Message(Msg)
  Effect(((Cmd[Msg]) -> Unit) -> Unit)
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
/// commands through its argument. Checked failures are intentionally unsupported
/// in this prototype; represent recoverable failures as messages carrying
/// `Result`.
pub fn[Msg] Cmd::effect(callback : ((Cmd[Msg]) -> Unit) -> Unit) -> Cmd[Msg] {
  Cmd(Effect(callback))
}
