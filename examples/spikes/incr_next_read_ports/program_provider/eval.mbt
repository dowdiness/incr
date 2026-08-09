///|
/// One authorized attempted read in the latest Formula invocation.
pub(all) struct ObservedInvocation {
  port_id : PortId
  ordinal : Int
} derive(Eq, Debug)

///|
/// Evaluation capability passed to Formula callbacks. Its kernel context is private.
pub struct ProgramEvalCtx {
  priv raw : @kernel.EvalCtx
  priv program : ProgramId
  priv formula_id : FormulaId
  priv auth : Map[PortId, Unit]
  priv observations : Ref[Array[ObservedInvocation]]
  priv structural : Ref[@kernel.ReadError?]
}

///|
/// Reads only a Port declared by this Formula; unauthorized reads do not invoke the View.
pub fn[T] ProgramEvalCtx::read(
  self : ProgramEvalCtx,
  declared : DeclaredRead[T],
) -> Result[T, ProgramError] {
  let port_id = declared.port.core.port_id
  if declared.formula_id != self.formula_id ||
    declared.port.core.program != self.program ||
    !self.auth.contains(port_id) {
    Err(UnauthorizedRead(port_id~))
  } else {
    let ordinal = self.observations.val.length()
    self.observations.val.push(ObservedInvocation::{ port_id, ordinal })
    match self.raw.read(declared.port.core.view) {
      Ok(value) => Ok(value)
      Err(error) => {
        self.structural.val = Some(error)
        Err(UnauthorizedRead(port_id~))
      }
    }
  }
}
