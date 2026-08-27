///|
fn cutoff_script(
  kind : @model.CutoffKind,
  steps : Array[Int],
) -> @model.CutoffScript {
  @model.CutoffScript::CutoffScript(kind, steps)
}

///|
/// AlwaysChanged recomputes an equivalent direct result.
pub fn always_changed_equivalent() -> @model.CutoffScript {
  cutoff_script(@model.CutoffKind::AlwaysChangedEquivalent, [0, 1])
}

///|
/// Structural Eq observes an equivalent result after a selected trigger.
pub fn eq_equivalent() -> @model.CutoffScript {
  cutoff_script(@model.CutoffKind::EqEquivalent, [0, 1])
}

///|
/// Structural Eq observes a changed result.
pub fn eq_changed() -> @model.CutoffScript {
  cutoff_script(@model.CutoffKind::EqChanged, [0, 4])
}

///|
/// Equivalent output with a replacement of the dependency trace.
pub fn dynamic_equivalent() -> @model.CutoffScript {
  cutoff_script(@model.CutoffKind::DynamicEquivalent, [0, 1])
}

///|
/// The supported cutoff scenarios.
pub fn cutoff_all() -> Array[@model.CutoffScript] {
  [
    always_changed_equivalent(),
    eq_equivalent(),
    eq_changed(),
    dynamic_equivalent(),
  ]
}
