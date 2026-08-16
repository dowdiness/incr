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
/// Reports whether the canonical Source scenario matches Fresh.
pub fn canonical_matches() -> Bool {
  matches(@scenarios.canonical())
}

///|
/// Reports whether every canonical scenario matches Fresh semantically.
pub fn all_match() -> Bool {
  @scenarios.all().all(script => matches(script))
}

///|
/// Compares admissible K1.4 cutoff semantics with the memo-free oracle.
pub fn cutoff_matches(script : @model.CutoffScript) -> Bool {
  semantic_observations(@fresh.evaluate_cutoff(script)) ==
  semantic_observations(@incremental_adapter.evaluate_cutoff(script))
}

///|
/// Reports whether every admissible cutoff scenario preserves Fresh parity.
pub fn all_cutoff_match() -> Bool {
  @scenarios.cutoff_all().all(script => cutoff_matches(script))
}
