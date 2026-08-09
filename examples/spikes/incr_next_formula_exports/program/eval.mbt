///|
/// One authorized facade-level read attempt in the latest invocation.
pub(all) struct ObservedInvocation {
  local_port_id : PortId
  origin : PortOrigin
  ordinal : Int
} derive(Eq, Debug)

///|
/// Evaluation capability whose kernel context remains private.
pub struct ProgramEvalCtx {
  priv raw : @kernel.EvalCtx
  priv program : ProgramId
  priv formula_id : FormulaId
  priv auth : Map[PortId, PortOrigin]
  priv observations : Ref[Array[ObservedInvocation]]
  priv structural : Ref[@kernel.ReadError?]
  priv active : Ref[Bool]
}

///|
/// Reads only a declaration authorized by this Formula.
pub fn[T] ProgramEvalCtx::read(
  self : ProgramEvalCtx,
  declared : DeclaredRead[T],
) -> Result[T, ProgramError] {
  let port_id = declared.port.core.port_id
  if !self.active.val {
    Err(ExpiredProgramEvaluation(formula_id=self.formula_id))
  } else if declared.formula_id != self.formula_id ||
    declared.port.core.program != self.program ||
    !self.auth.contains(port_id) {
    Err(UnauthorizedRead(port_id~))
  } else {
    let ordinal = self.observations.val.length()
    self.observations.val.push(ObservedInvocation::{
      local_port_id: port_id,
      origin: declared.port.core.origin,
      ordinal,
    })
    match self.raw.read(declared.port.core.view) {
      Ok(value) => Ok(value)
      Err(error) => {
        if self.structural.val is None {
          self.structural.val = Some(error)
        }
        Err(UnauthorizedRead(port_id~))
      }
    }
  }
}
