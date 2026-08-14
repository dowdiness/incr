///|
test "all K1.1 graph and error scenarios match Fresh" {
  assert_true(@differential.all_match())
}

///|
test "keyed work identity includes SourceId and key" {
  let script = @model.Script::scenario(@model.Scenario::KeyedQuery, [
    @model.Operation::Define(1, 10),
    @model.Operation::ReadKey(0, 3),
    @model.Operation::ReadKey(1, 3),
    @model.Operation::ReadKey(1, 3),
  ])
  let expected = [
    @model.Observation::Value(3),
    @model.Observation::Value(13),
    @model.Observation::Value(13),
    @model.Observation::Counter(2),
  ]
  assert_eq(@fresh.evaluate(script), expected)
  assert_eq(@incremental_adapter.evaluate(script), expected)
}

///|
test "same-epoch chain shares Query memo work" {
  let expected = [
    @model.Observation::Value(1),
    @model.Observation::Value(1),
    @model.Observation::Counter(2),
  ]
  assert_eq(@fresh.evaluate(@scenarios.chain()), expected)
  assert_eq(@incremental_adapter.evaluate(@scenarios.chain()), expected)
}

///|
test "same-epoch diamond shares Query memo work" {
  let expected = [
    @model.Observation::Value(3),
    @model.Observation::Value(3),
    @model.Observation::Counter(4),
  ]
  assert_eq(@fresh.evaluate(@scenarios.diamond()), expected)
  assert_eq(@incremental_adapter.evaluate(@scenarios.diamond()), expected)
}

///|
test "UnitQuery Define publishes an existing Source" {
  let script = @model.Script::scenario(@model.Scenario::UnitQuery, [
    @model.Operation::Read(0),
    @model.Operation::Define(0, 7),
    @model.Operation::Read(0),
  ])
  let expected = [
    @model.Observation::Value(0),
    @model.Observation::Value(7),
    @model.Observation::Counter(2),
  ]
  assert_eq(@fresh.evaluate(script), expected)
  assert_eq(@incremental_adapter.evaluate(script), expected)
}

///|
test "DynamicBranch late Define publishes a pre-existing default Source" {
  let script = @scenarios.dynamic_branch()
  let expected = [
    @model.Observation::Value(0),
    @model.Observation::Value(9),
    @model.Observation::Counter(2),
  ]
  assert_eq(@fresh.evaluate(script), expected)
  assert_eq(@incremental_adapter.evaluate(script), expected)
}
