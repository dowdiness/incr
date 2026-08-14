///|
test "Script snapshots its caller-owned operation array" {
  let operations = [@model.Operation::Read(0)]
  let script = @model.Script::Script(operations)
  operations[0] = @model.Operation::Set(0, 9)
  assert_eq(script.operations(), [@model.Operation::Read(0)])
}
