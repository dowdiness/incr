///|
fn semantic_observations(
  observations : Array[@model.Observation],
) -> Array[@model.Observation] {
  observations.filter(observation => {
    match observation {
      @model.Observation::Counter(_) => false
      _ => true
    }
  })
}

///|
/// Compares Fresh and incremental semantic observations.
///
/// Counters are intentionally excluded: Fresh is a from-scratch semantic
/// oracle, while the incremental adapter's counters measure kernel work.
pub fn matches(script : @model.Script) -> Bool {
  semantic_observations(@fresh.evaluate(script)) ==
  semantic_observations(@incremental_adapter.evaluate(script))
}

///|
pub fn canonical_matches() -> Bool {
  matches(@scenarios.canonical())
}

///|
pub fn all_match() -> Bool {
  @scenarios.all().all(script => matches(script))
}
