///|
test "model scripts are kernel-independent" {
  let script = @model.Script::Script([@model.Operation::Read(0)])
  assert_eq(script.operations.length(), 1)
}
