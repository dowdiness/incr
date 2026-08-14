///|
/// Compares normalized Fresh and incremental observations.
pub fn matches(script : @model.Script) -> Bool {
  @fresh.evaluate(script) == @incremental_adapter.evaluate(script)
}

///|
pub fn canonical_matches() -> Bool {
  matches(@scenarios.canonical())
}

///|
pub fn all_match() -> Bool {
  @scenarios.all().all(script => matches(script))
}
