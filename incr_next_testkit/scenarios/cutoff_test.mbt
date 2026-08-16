///|
test "cutoff matrix contains each commissioned admissible policy workload" {
  let scripts = @scenarios.cutoff_all()
  assert_eq(scripts.length(), 7)
  assert_eq(scripts.map(script => script.kind()), [
    @model.CutoffKind::AlwaysChangedEquivalent,
    @model.CutoffKind::EqEquivalent,
    @model.CutoffKind::EqChanged,
    @model.CutoffKind::TypeOwnedEquivalent,
    @model.CutoffKind::TypeOwnedChanged,
    @model.CutoffKind::DynamicEquivalent,
    @model.CutoffKind::ConsecutiveEquivalent,
  ])
}
