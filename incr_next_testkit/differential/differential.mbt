///|
/// Compares normalized Fresh and incremental observations.
pub fn canonical_matches() -> Bool {
  let script = @scenarios.canonical()
  @fresh.evaluate(script) == @incremental_adapter.evaluate(script)
}
