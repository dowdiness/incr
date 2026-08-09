///|
/// Errors while creating a local port from a View.
pub(all) enum PortError {
  PortRegionMismatch
} derive(Eq, Debug)

///|
/// Errors while publishing a provider-owned export.
pub(all) enum ExportError {
  ForeignView
  ForeignFormula
  FormulaRegionMismatch
  ReexportForbidden
} derive(Eq, Debug)

///|
/// Import validation happens before a local PortId is allocated.
pub(all) enum ImportError {
  DifferentStore
} derive(Eq, Debug)

///|
/// Definition and consuming-builder failures.
pub(all) enum BuilderError {
  ForeignPort(port_id~ : PortId)
  BuilderExpired
  Region(error~ : @kernel.RegionError)
} derive(Eq, Debug)

///|
/// Application-level failures returned inside a successful Formula result.
pub(all) enum ProgramError {
  UnauthorizedRead(port_id~ : PortId)
  ExpiredProgramEvaluation(formula_id~ : FormulaId)
} derive(Eq, Debug)

///|
/// Structural errors remain outside the Formula application result.
pub(all) enum FormulaReadError {
  ForeignFormula
  CrossStore
  ClosedRegion
  Cycle
  Other
} derive(Eq, Debug)
