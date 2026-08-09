///|
priv struct ProgramId {
  sequence : Int
} derive(Eq, Hash, Debug)

///|
/// Identity of a capability owned by one Program.
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
/// Returns the Port's Program-local sequence for evidence formatting.
pub fn PortId::sequence(self : PortId) -> Int {
  self.sequence
}

///|
/// Returns the Formula's Program-local sequence for evidence formatting.
pub fn FormulaId::sequence(self : FormulaId) -> Int {
  self.sequence
}
