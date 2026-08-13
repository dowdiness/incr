///|
/// Canonical K1.1 scenario shared by both evaluators.
pub fn canonical() -> @model.Script {
  @model.Script::Script([
    @model.Operation::Read(0),
    @model.Operation::Set(0, 4),
    @model.Operation::Read(0),
  ])
}
