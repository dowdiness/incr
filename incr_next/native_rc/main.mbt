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
priv struct TraceKey {
  _token : RcToken
  id : Int
}

///|
impl Eq for TraceKey with fn equal(self, other) -> Bool {
  self.id == other.id
}

///|
impl Hash for TraceKey with fn hash(self) {
  self.id.hash()
}

///|
impl Hash for TraceKey with fn hash_combine(self, hasher) {
  self.id.hash_combine(hasher)
}

///|
fn trace_key(kind : Int, id : Int) -> TraceKey {
  { _token: token_new(kind), id }
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
fn probe_successful_recompute_releases_old_memo_value_and_trace() -> Bool {
  let store = @incr_next.Store::Store()
  let child_region = store.region().unwrap()
  let parent_region = store.region().unwrap()
  let selector = parent_region.source(0).unwrap()
  let child = child_region.query((_ctx, key : TraceKey) => Ok(key.id)).unwrap()
  let parent = parent_region
    .query((ctx, _unit : Unit) => {
      match ctx.read(selector.view()) {
        Ok(flag) => {
          let key = trace_key(if flag == 0 { 16 } else { 17 }, flag)
          match ctx.read(child.at(key)) {
            Ok(value) => Ok(payload(if flag == 0 { 18 } else { 19 }, value))
            Err(error) => Err(error)
          }
        }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = parent.at(())
  let initial_value = match store.read(view) {
    Ok(value) => value.value
    Err(_) => -1
  }
  let initial = initial_value == 0 &&
    live(16) == 1 &&
    live(17) == 0 &&
    live(18) == 1 &&
    live(19) == 0
  ignore(store.transaction(tx => tx.set(selector, 1)))
  let next_value = match store.read(view) {
    Ok(value) => value.value
    Err(_) => -1
  }
  let replaced = next_value == 1 &&
    live(16) == 1 &&
    live(17) == 1 &&
    live(18) == 0 &&
    finalized(18) == 1 &&
    live(19) == 1 &&
    finalized(19) == 0
  ignore(child_region.close())
  let old_trace_released = live(16) == 0 && finalized(16) == 1 && live(17) == 1
  ignore(parent_region.close())
  let closed = live(17) == 0 &&
    finalized(17) == 1 &&
    live(19) == 0 &&
    finalized(19) == 1
  initial && replaced && old_trace_released && closed
}

///|
fn probe_failed_recompute_releases_temporary_trace() -> Bool {
  let store = @incr_next.Store::Store()
  let foreign_store = @incr_next.Store::Store()
  let child_region = store.region().unwrap()
  let parent_region = store.region().unwrap()
  let foreign_region = foreign_store.region().unwrap()
  let selector = parent_region.source(0).unwrap()
  let foreign = foreign_region.source(9).unwrap()
  let child = child_region.query((_ctx, key : TraceKey) => Ok(key.id)).unwrap()
  let parent = parent_region
    .query((ctx, _unit : Unit) => {
      match ctx.read(selector.view()) {
        Ok(flag) => {
          let key = trace_key(if flag == 0 { 20 } else { 21 }, flag)
          match ctx.read(child.at(key)) {
            Ok(value) =>
              if flag == 1 {
                match ctx.read(foreign.view()) {
                  Ok(foreign_value) => Ok(payload(23, foreign_value))
                  Err(error) => Err(error)
                }
              } else {
                Ok(payload(22, value))
              }
            Err(error) => Err(error)
          }
        }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = parent.at(())
  let initial_value = match store.read(view) {
    Ok(value) => value.value
    Err(_) => -1
  }
  ignore(store.transaction(tx => tx.set(selector, 1)))
  let failed = store.read(view) is Err(@incr_next.ReadError::CrossStore(..))
  let old_authority = live(20) == 1 && live(21) == 1 && live(22) == 1
  ignore(child_region.close())
  let temporary_released = live(20) == 1 &&
    live(21) == 0 &&
    finalized(21) == 1 &&
    live(22) == 1
  ignore(parent_region.close())
  ignore(foreign_region.close())
  initial_value == 0 &&
  failed &&
  old_authority &&
  temporary_released &&
  live(20) == 0 &&
  finalized(20) == 1 &&
  live(22) == 0 &&
  finalized(22) == 1
}

///|
fn probe_close_releases_memo_payloads_but_view_keeps_key() -> Bool {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let source = region.source(1).unwrap()
  let child = region.query((_ctx, key : TraceKey) => Ok(key.id)).unwrap()
  let query = region
    .query((ctx, _key : TraceKey) => {
      match ctx.read(child.at(trace_key(27, 0))) {
        Ok(value) =>
          match ctx.read(source.view()) {
            Ok(_) => Ok(payload(28, value))
            Err(error) => Err(error)
          }
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = Ref(Some(query.at(trace_key(26, 0))))
  let read_ok = match store.read(view.val.unwrap()) {
    Ok(value) => value.value == 0
    Err(_) => false
  }
  let retained_before_close = live(26) == 1 && live(27) == 1 && live(28) == 1
  ignore(region.close())
  let closed = live(26) == 1 &&
    live(27) == 0 &&
    finalized(27) == 1 &&
    live(28) == 0 &&
    finalized(28) == 1
  // The View is the only remaining owner of the target key after close.
  view.val = None
  let view_released = live(26) == 0
  read_ok && retained_before_close && closed && view_released
}

///|
fn probe_cycle_witness_does_not_retain_key() -> Bool {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let self_view : Ref[@incr_next.View[Int]?] = Ref(None)
  let query = region
    .query((ctx, _key : TraceKey) => ctx.read(self_view.val.unwrap()))
    .unwrap()
  let view = Ref(Some(query.at(trace_key(30, 0))))
  self_view.val = view.val
  let result = store.read(view.val.unwrap())
  let held_error = Ref(Some(result))
  let witness_held = match held_error.val {
    Some(Err(@incr_next.ReadError::Cycle(witness))) =>
      witness.path().length() == 2
    _ => false
  }
  let retained_by_view = live(30) == 1 && finalized(30) == 0
  self_view.val = None
  view.val = None
  let released_before_close = live(30) == 0 && finalized(30) == 1
  let witness_still_held = match held_error.val {
    Some(Err(@incr_next.ReadError::Cycle(witness))) =>
      witness.path().length() == 2
    _ => false
  }
  ignore(region.close())
  witness_held &&
  retained_by_view &&
  released_before_close &&
  witness_still_held
}

///|
fn main {
  let close = probe_close()
  let callback_rollback = probe_callback_rollback()
  let poison_rollback = probe_poison_rollback()
  let last_write_wins = probe_last_write_wins()
  let commit_replacement = probe_commit_replacement()
  let successful_recompute = probe_successful_recompute_releases_old_memo_value_and_trace()
  let failed_recompute = probe_failed_recompute_releases_temporary_trace()
  let memo_close = probe_close_releases_memo_payloads_but_view_keeps_key()
  let cycle_witness = probe_cycle_witness_does_not_retain_key()
  let query_capture_close = probe_query_capture_close()
  let external_alias = probe_external_alias_control()
  let passed = close &&
    callback_rollback &&
    poison_rollback &&
    last_write_wins &&
    commit_replacement &&
    successful_recompute &&
    failed_recompute &&
    memo_close &&
    cycle_witness &&
    query_capture_close &&
    external_alias
  let verdict = if passed { "PASS" } else { "FAIL" }
  println("native RC/finalizer evidence: \{verdict}")
  if !passed {
    abort("native RC/finalizer evidence failed")
  }
}
