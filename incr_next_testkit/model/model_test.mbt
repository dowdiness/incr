///|
test "cycle observations use an opaque normalized contract" {
  assert_eq(@model.ScenarioError::Cycle, @model.ScenarioError::Cycle)
}
