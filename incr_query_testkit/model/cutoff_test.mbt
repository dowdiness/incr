///|
test "CutoffScript freezes setup steps and returns defensive copies" {
  let input = [0, 1]
  let script = @model.CutoffScript::CutoffScript(
    @model.CutoffKind::EqEquivalent,
    input,
  )
  input[0] = 9
  assert_eq(script.steps(), [0, 1])
  let observed = script.steps()
  observed[1] = 8
  assert_eq(script.steps(), [0, 1])
  assert_eq(script.kind(), @model.CutoffKind::EqEquivalent)
}
