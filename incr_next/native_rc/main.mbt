///|
priv type RcToken

///|
extern "C" fn token_new(kind : Int) -> RcToken = "incr_next_rc_token_new"

///|
extern "C" fn live(kind : Int) -> Int = "incr_next_rc_live"

///|
extern "C" fn finalized(kind : Int) -> Int = "incr_next_rc_finalized"

///|
priv struct Payload {
  token : RcToken
  value : Int
}

///|
fn payload(kind : Int, value : Int) -> Payload {
  { token: token_new(kind), value }
}

///|
fn probe_close() -> Bool {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  ignore(region.source(payload(0, 7)).unwrap())
  ignore(region.close())
  live(0) == 0 && finalized(0) == 1
}

///|
fn probe_callback_rollback() -> Bool {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let source = region.source(payload(1, 0)).unwrap()
  let result = store.transaction(tx => {
    ignore(tx.set(source, payload(2, 1)))
    Err(@incr_next.TransactionError::CallbackRejected)
  })
  let passed = result is Err(@incr_next.TransactionError::CallbackRejected) &&
    live(2) == 0 &&
    finalized(2) == 1
  ignore(region.close())
  passed
}

///|
fn probe_poison_rollback() -> Bool {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let source = region.source(payload(3, 0)).unwrap()
  let other_store = @incr_next.Store::Store()
  let other_region = other_store.region().unwrap()
  let foreign = other_region.source(payload(4, 0)).unwrap()
  let result = store.transaction(tx => {
    ignore(tx.set(source, payload(5, 1)))
    ignore(tx.set(foreign, payload(6, 2)))
    Ok(())
  })
  let passed = result is Err(@incr_next.TransactionError::CrossStore(..)) &&
    live(5) == 0 &&
    finalized(5) == 1 &&
    live(6) == 0 &&
    finalized(6) == 1
  ignore(region.close())
  ignore(other_region.close())
  passed
}

///|
fn probe_last_write_wins() -> Bool {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let source = region.source(payload(7, 0)).unwrap()
  let superseded = Ref(false)
  let result = store.transaction(tx => {
    ignore(tx.set(source, payload(8, 1)))
    ignore(tx.set(source, payload(9, 2)))
    superseded.val = live(8) == 0 && finalized(8) == 1
    Ok(())
  })
  let committed = result is Ok(_) && live(9) == 1
  ignore(region.close())
  superseded.val && committed && live(9) == 0 && finalized(9) == 1
}

///|
fn probe_query_capture_close() -> Bool {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let captured = payload(12, 41)
  let query = region
    .query((_ctx, _unit : Unit) => {
      ignore(captured.token)
      Ok(captured.value)
    })
    .unwrap()
  ignore(query)
  ignore(region.close())
  live(12) == 0 && finalized(12) == 1
}

///|
fn probe_external_alias_control() -> Bool {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let external_payload = Ref(Some(payload(13, 42)))
  let query = region
    .query((_ctx, _unit : Unit) => {
      match external_payload.val {
        Some(value) => {
          ignore(value.token)
          Ok(value.value)
        }
        None => Ok(0)
      }
    })
    .unwrap()
  ignore(query)
  ignore(region.close())
  let retained = live(13) == 1 && finalized(13) == 0
  external_payload.val = None
  retained && live(13) == 0 && finalized(13) == 1
}

///|
fn probe_commit_replacement() -> Bool {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let source = region.source(payload(10, 0)).unwrap()
  let result = store.transaction(tx => tx.set(source, payload(11, 1)))
  let replaced = result is Ok(_) &&
    live(10) == 0 &&
    finalized(10) == 1 &&
    live(11) == 1
  ignore(region.close())
  replaced && live(11) == 0 && finalized(11) == 1
}

///|
fn main {
  let close = probe_close()
  let callback_rollback = probe_callback_rollback()
  let poison_rollback = probe_poison_rollback()
  let last_write_wins = probe_last_write_wins()
  let commit_replacement = probe_commit_replacement()
  let query_capture_close = probe_query_capture_close()
  let external_alias = probe_external_alias_control()
  let passed = close &&
    callback_rollback &&
    poison_rollback &&
    last_write_wins &&
    commit_replacement &&
    query_capture_close &&
    external_alias
  let verdict = if passed { "PASS" } else { "FAIL" }
  println("native RC/finalizer evidence: \{verdict}")
  if !passed {
    abort("native RC/finalizer evidence failed")
  }
}
