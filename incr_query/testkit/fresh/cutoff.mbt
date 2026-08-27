///|
fn cutoff_value(kind : @model.CutoffKind, step : Int) -> Int {
  match kind {
    @model.CutoffKind::EqChanged => step
    _ => 0
  }
}

///|
/// Evaluates supported cutoff workloads without memo or policy sharing.
pub fn evaluate_cutoff(
  script : @model.CutoffScript,
) -> Array[@model.Observation] {
  script
  .steps()
  .map(step => @model.Observation::Value(cutoff_value(script.kind(), step)))
}
