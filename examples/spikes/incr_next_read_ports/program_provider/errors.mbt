///|
/// Application-level failure reported inside a successful Formula value.
pub(all) enum ProgramError {
  UnauthorizedRead(port_id~ : PortId)
  ExpiredProgramEvaluation(formula_id~ : FormulaId)
} derive(Eq, Debug)

///|
/// Definition and lifecycle failures at the Program/Formula boundary.
pub(all) enum BuilderError {
  ForeignPort(port_id~ : PortId)
  PortRegionMismatch
  BuilderExpired
  Region(error~ : @kernel.RegionError)
} derive(Eq, Debug)
