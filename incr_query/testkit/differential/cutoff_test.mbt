///|
test "supported cutoff scenarios preserve Fresh semantics" {
  assert_true(@differential.all_cutoff_match())
}

///|
test "cutoff oracle distinguishes equivalent and changed Eq values" {
  assert_true(@differential.cutoff_matches(@scenarios.eq_equivalent()))
  assert_true(@differential.cutoff_matches(@scenarios.eq_changed()))
}
