///|
/// Immutable Formula evidence; its kernel result View remains package-private.
pub struct Formula[V] {
  priv core : FormulaCore[V]
}

///|
priv struct FormulaCore[V] {
  formula_id : FormulaId
  store : @kernel.StoreId
  region_id : @kernel.RegionId
  manifest : Manifest
  observations : Ref[Array[ObservedInvocation]]
  view : @kernel.View[Result[V, ProgramError]]
}

///|
/// Immutable debug snapshot of one Formula's declarations and latest attempt.
pub(all) struct FormulaDebug {
  formula_id : FormulaId
  manifest : Array[ManifestEntry]
  observations : Array[ObservedInvocation]
} derive(Eq, Debug)

///|
pub fn[V] Formula::manifest(self : Formula[V]) -> Manifest {
  Manifest::{ entries: self.core.manifest.entries.copy() }
}

///|
pub fn[V] Formula::debug(self : Formula[V]) -> FormulaDebug {
  {
    formula_id: self.core.formula_id,
    manifest: self.core.manifest.entries.copy(),
    observations: self.core.observations.val.copy(),
  }
}
