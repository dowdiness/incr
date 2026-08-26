///|
test "Fresh cutoff oracle exposes supported semantic values" {
  assert_eq(@fresh.evaluate_cutoff(@scenarios.eq_equivalent()), [
    @model.Observation::Value(0),
    @model.Observation::Value(0),
  ])
  assert_eq(@fresh.evaluate_cutoff(@scenarios.eq_changed()), [
    @model.Observation::Value(0),
    @model.Observation::Value(4),
  ])
}
