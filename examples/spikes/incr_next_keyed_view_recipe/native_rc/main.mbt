///|
/// Native external token used only as an observation marker.
priv type RcProbeToken

///|
/// Allocates an RC-observed token.
extern "C" fn token_new(kind : Int) -> RcProbeToken = "incr_next_view_token_new"

///|
/// Keeps the token capture live without retaining it from the probe.
#borrow(token)
extern "C" fn token_touch(token : RcProbeToken) -> Unit = "incr_next_view_token_touch"

///|
/// Returns live native tokens for a category.
extern "C" fn live(kind : Int) -> Int = "incr_next_view_live"

///|
/// Returns finalized native tokens for a category.
extern "C" fn finalized(kind : Int) -> Int = "incr_next_view_finalized"

///|
/// Payload whose token represents a materialized memo payload.
priv struct RcPayload {
  token : RcProbeToken
  value : Int
}

///|
/// Constructs one observed memo payload.
fn RcPayload::RcPayload(token : RcProbeToken, value : Int) -> RcPayload {
  { token, value }
}

///|
/// Builds and drops one unclosed but acyclic Region/Query/View graph.
fn build_and_drop_acyclic() -> Unit {
  let store = @provider.Store()
  let region = store.region()
  let compute_token = token_new(0)
  let query = region.query((key : Int) => {
    token_touch(compute_token)
    RcPayload(token_new(1), key)
  })
  let view = query.at(7)
  match store.read(view) {
    Ok(payload) => {
      token_touch(payload.token)
      ignore(payload.value)
    }
    Err(_) => abort("acyclic graph unexpectedly closed")
  }
}

///|
/// Proves the field graph has no library-controlled cycle before close.
fn probe_acyclic_drop() -> Bool {
  build_and_drop_acyclic()
  live(0) == 0 && live(1) == 0 && finalized(0) == 1 && finalized(1) == 1
}

///|
/// Proves Region close clears Query payloads while a View remains live.
fn probe_close_with_view() -> Bool {
  let store = @provider.Store()
  let region = store.region()
  let compute_token = token_new(0)
  let query = region.query((key : Int) => {
    token_touch(compute_token)
    RcPayload(token_new(1), key)
  })
  let view = query.at(9)
  ignore(store.read(view))
  let before_compute = live(0)
  let before_payload = live(1)
  region.close()
  let after_compute = live(0)
  let after_payload = live(1)
  let result = store.read(view)
  let closed = match result {
    Err(@provider.ReadError::ClosedRegion(_)) => true
    _ => false
  }
  before_compute == 1 &&
  before_payload == 1 &&
  after_compute == 0 &&
  after_payload == 0 &&
  finalized(0) == 2 &&
  finalized(1) == 2 &&
  closed
}

///|
/// Native RC executable with full external-token state.
fn main {
  let acyclic = probe_acyclic_drop()
  let close = probe_close_with_view()
  let passed = acyclic && close
  println("INCR NEXT KEYED VIEW RECIPE — NATIVE RC")
  println(
    "external_object_counts compute=live:\{live(0)},finalized:\{finalized(0)} payload=live:\{live(1)},finalized:\{finalized(1)}",
  )
  println("acyclic_unclosed_drop=\{acyclic}")
  println("region_close_with_surviving_view=\{close}")
  println(
    "full_state acyclic=\{acyclic} close=\{close} live_compute=\{live(0)} live_payload=\{live(1)} finalized_compute=\{finalized(0)} finalized_payload=\{finalized(1)}",
  )
  println("constrained verdict: \{if passed { "PASS" } else { "FAIL" }}")
  if !passed {
    abort("native RC evidence failed")
  }
}
