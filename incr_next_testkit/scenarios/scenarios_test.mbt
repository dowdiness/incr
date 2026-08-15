///|
test "cycle_matrix follows the canonical scenarios in all" {
  assert_eq(@scenarios.cycle_matrix().length(), 9)
  assert_eq(@scenarios.all().length(), 21)
}

///|
test "cycle scripts use logical Query reads" {
  assert_eq(@scenarios.direct_cycle().operations(), [
    @model.Operation::ReadQuery(0, 0),
  ])
  assert_eq(@scenarios.old_trace_cycle().operations(), [
    @model.Operation::ReadQuery(1, 0),
    @model.Operation::Set(0, 1),
    @model.Operation::ReadQuery(0, 0),
  ])
}
