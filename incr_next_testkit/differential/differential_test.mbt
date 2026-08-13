///|
test "all K1.1 graph and error scenarios match Fresh" {
  assert_true(@differential.all_match())
}

///|
test "no-memo chain recomputes every Query on every root" {
  let expected = [
    @model.Observation::Value(1),
    @model.Observation::Value(1),
    @model.Observation::Counter(4),
  ]
  assert_eq(@fresh.evaluate(@scenarios.chain()), expected)
  assert_eq(@incremental_adapter.evaluate(@scenarios.chain()), expected)
}

///|
test "no-memo diamond duplicates the shared Query on each path" {
  let expected = [
    @model.Observation::Value(3),
    @model.Observation::Value(3),
    @model.Observation::Counter(10),
  ]
  assert_eq(@fresh.evaluate(@scenarios.diamond()), expected)
  assert_eq(@incremental_adapter.evaluate(@scenarios.diamond()), expected)
}

///|
test "definitions preserve operation order in both evaluators" {
  let script = @model.Script::Script([
    @model.Operation::Read(0),
    @model.Operation::Define(0, 9),
    @model.Operation::Read(0),
  ])
  let expected = [
    @model.Observation::Value(0),
    @model.Observation::Value(9),
    @model.Observation::Counter(0),
  ]
  assert_eq(@fresh.evaluate(script), expected)
  assert_eq(@incremental_adapter.evaluate(script), expected)
}
