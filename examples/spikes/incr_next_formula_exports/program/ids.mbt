///|
/// Identity of one standalone Program.
pub(all) struct ProgramId {
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
/// Identity of one provider-owned export.
pub(all) struct ExportId {
  priv provider : ProgramId
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
/// Identity of one consumer-owned local port.
pub(all) struct PortId {
  priv program : ProgramId
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
/// Identity of one Formula definition.
pub(all) struct FormulaId {
  priv program : ProgramId
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
pub fn ProgramId::sequence(self : ProgramId) -> Int {
  self.sequence
}

///|
pub fn ExportId::provider_program(self : ExportId) -> ProgramId {
  self.provider
}

///|
pub fn ExportId::sequence(self : ExportId) -> Int {
  self.sequence
}

///|
pub fn PortId::program(self : PortId) -> ProgramId {
  self.program
}

///|
pub fn PortId::sequence(self : PortId) -> Int {
  self.sequence
}

///|
pub fn FormulaId::sequence(self : FormulaId) -> Int {
  self.sequence
}
