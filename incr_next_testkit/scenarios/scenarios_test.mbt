///|
test "cycle_matrix is separate from canonical all scenarios" {
  assert_eq(@scenarios.cycle_matrix().length(), 9)
  assert_eq(@scenarios.all().length(), 12)
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
