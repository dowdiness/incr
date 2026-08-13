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
