///|
test "admissible K1.4 cutoff scenarios preserve Fresh semantics" {
  assert_true(@differential.all_cutoff_match())
}

///|
test "cutoff oracle keeps direct values newest across equivalent updates" {
  assert_eq(@fresh.evaluate_cutoff(@scenarios.consecutive_equivalent()), [
    @model.Observation::Value(0),
    @model.Observation::Marker(0),
    @model.Observation::Value(0),
    @model.Observation::Marker(1),
    @model.Observation::Value(0),
    @model.Observation::Marker(2),
  ])
  assert_true(@differential.cutoff_matches(@scenarios.type_owned_changed()))
}
