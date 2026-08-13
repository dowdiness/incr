///|
priv type RcToken

///|
extern "C" fn token_new() -> RcToken = "incr_next_rc_token_new"

///|
extern "C" fn live() -> Int = "incr_next_rc_live"

///|
extern "C" fn finalized() -> Int = "incr_next_rc_finalized"

///|
priv struct Payload {
  token : RcToken
  value : Int
}

///|
fn probe_close() -> Unit {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  ignore(region.source(Payload::{ token: token_new(), value: 7 }).unwrap())
  ignore(region.close())
}

///|
fn main {
  probe_close()
  if live() != 0 || finalized() != 1 {
    abort("native RC close evidence failed")
  }
  println("native RC close evidence: PASS")
}
