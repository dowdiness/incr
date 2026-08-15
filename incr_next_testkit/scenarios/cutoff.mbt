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
/// A non-Eq result owns its propagation-equivalence relation.
pub fn type_owned_equivalent() -> @model.CutoffScript {
  cutoff_script(@model.CutoffKind::TypeOwnedEquivalent, [0, 1])
}

///|
/// A type-owned relation reports a changed result.
pub fn type_owned_changed() -> @model.CutoffScript {
  cutoff_script(@model.CutoffKind::TypeOwnedChanged, [0, 4])
}

///|
/// Equivalent output with a replacement of the dependency trace.
pub fn dynamic_equivalent() -> @model.CutoffScript {
  cutoff_script(@model.CutoffKind::DynamicEquivalent, [0, 1])
}

///|
/// Multiple equivalent recomputations always expose the newest direct value.
pub fn consecutive_equivalent() -> @model.CutoffScript {
  cutoff_script(@model.CutoffKind::ConsecutiveEquivalent, [0, 1, 2])
}

///|
/// The admissible K1.4 cutoff scenarios.
pub fn cutoff_all() -> Array[@model.CutoffScript] {
  [
    always_changed_equivalent(),
    eq_equivalent(),
    eq_changed(),
    type_owned_equivalent(),
    type_owned_changed(),
    dynamic_equivalent(),
    consecutive_equivalent(),
  ]
}
