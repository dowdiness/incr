///|
test "cutoff matrix contains each supported policy workload" {
  let scripts = @scenarios.cutoff_all()
  assert_eq(scripts.length(), 4)
  assert_eq(scripts.map(script => script.kind()), [
    @model.CutoffKind::AlwaysChangedEquivalent,
    @model.CutoffKind::EqEquivalent,
    @model.CutoffKind::EqChanged,
    @model.CutoffKind::DynamicEquivalent,
  ])
}
