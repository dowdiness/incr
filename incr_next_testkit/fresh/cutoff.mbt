///|
fn cutoff_value(kind : @model.CutoffKind, step : Int) -> Int {
  match kind {
    @model.CutoffKind::EqChanged | @model.CutoffKind::TypeOwnedChanged => step
    _ => 0
  }
}

///|
/// Evaluates K1.4 cutoff workloads without memo or policy sharing.
pub fn evaluate_cutoff(
  script : @model.CutoffScript,
) -> Array[@model.Observation] {
  let observations : Array[@model.Observation] = []
  for step in script.steps() {
    observations.push(
      @model.Observation::Value(cutoff_value(script.kind(), step)),
    )
    match script.kind() {
      @model.CutoffKind::TypeOwnedEquivalent
      | @model.CutoffKind::TypeOwnedChanged
      | @model.CutoffKind::ConsecutiveEquivalent =>
        observations.push(@model.Observation::Marker(step))
      _ => ()
    }
  }
  observations
}
