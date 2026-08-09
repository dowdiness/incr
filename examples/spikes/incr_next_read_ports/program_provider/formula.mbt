///|
/// Immutable Formula evidence and opaque kernel View result.
pub struct Formula[V] {
  priv core : FormulaCore[V]
}

///|
priv struct FormulaCore[V] {
  formula_id : FormulaId
  manifest : Manifest
  observations : Ref[Array[ObservedInvocation]]
  view : @kernel.View[Result[V, ProgramError]]
}

///|
/// Immutable debug snapshot of one Formula's declaration and latest attempt.
pub(all) struct FormulaDebug {
  formula_id : FormulaId
  manifest : Array[PortId]
  observations : Array[ObservedInvocation]
} derive(Eq, Debug)

///|
/// Returns the Formula's immutable declaration manifest.
pub fn[V] Formula::manifest(self : Formula[V]) -> Manifest {
  Manifest::{ ports: self.core.manifest.ports.copy() }
}

///|
/// Returns the opaque kernel View yielding this Formula's application result.
pub fn[V] Formula::view(
  self : Formula[V],
) -> @kernel.View[Result[V, ProgramError]] {
  self.core.view
}

///|
/// Returns defensive debug evidence for the latest attempted invocation.
pub fn[V] Formula::debug(self : Formula[V]) -> FormulaDebug {
  {
    formula_id: self.core.formula_id,
    manifest: self.core.manifest.ports.copy(),
    observations: self.core.observations.val.copy(),
  }
}
