///|
test "Fresh cutoff oracle exposes newest direct markers without kernel state" {
  assert_eq(@fresh.evaluate_cutoff(@scenarios.consecutive_equivalent()), [
    @model.Observation::Value(0),
    @model.Observation::Marker(0),
    @model.Observation::Value(0),
    @model.Observation::Marker(1),
    @model.Observation::Value(0),
    @model.Observation::Marker(2),
  ])
  assert_eq(@fresh.evaluate_cutoff(@scenarios.eq_changed()), [
    @model.Observation::Value(0),
    @model.Observation::Value(4),
  ])
}
