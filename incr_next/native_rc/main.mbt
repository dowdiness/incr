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
fn probe_close() -> Bool raise {
  let store = @incr_next.Store::Store()
  let region = store.region()
  ignore(region.source(payload(0, 7)))
  region.close()
  live(0) == 0 && finalized(0) == 1
}

///|
fn probe_callback_rollback() -> Bool raise {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let source = region.source(payload(1, 0))
  let result : Result[Unit, String] = store.transaction(tx => {
    tx.set(source, payload(2, 1))
    Err("callback rejected")
  })
  let passed = result == Err("callback rejected") &&
    live(2) == 0 &&
    finalized(2) == 1
  region.close()
  passed
}

///|
fn probe_poison_rollback() -> Bool raise {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let source = region.source(payload(3, 0))
  let other_store = @incr_next.Store::Store()
  let other_region = other_store.region()
  let foreign = other_region.source(payload(4, 0))
  let result : Result[Result[Unit, Unit], @incr_next.TransactionError] = Ok(
    store.transaction(tx => {
      tx.set(source, payload(5, 1))
      tx.set(foreign, payload(6, 2))
      Ok(())
    }),
  ) catch {
    error => Err(error)
  }
  let passed = result is Err(@incr_next.TransactionError::CrossStore(_)) &&
    live(5) == 0 &&
    finalized(5) == 1 &&
    live(6) == 0 &&
    finalized(6) == 1
  region.close()
  other_region.close()
  passed
}

///|
fn probe_last_write_wins() -> Bool raise {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let source = region.source(payload(7, 0))
  let superseded = Ref(false)
  let result : Result[Unit, Unit] = store.transaction(tx => {
    tx.set(source, payload(8, 1))
    tx.set(source, payload(9, 2))
    superseded.val = live(8) == 0 && finalized(8) == 1
    Ok(())
  })
  let committed = result is Ok(_) && live(9) == 1
  region.close()
  superseded.val && committed && live(9) == 0 && finalized(9) == 1
}

///|
priv struct OwnedCutoff {
  token : RcToken
  value : Int
}

///|
impl @incr_next.CutoffEq for OwnedCutoff with fn cutoff_equal(self, other) {
  ignore(self.token)
  ignore(other.token)
  self.value == other.value
}

///|
fn probe_cutoff_releases_old_memo_value() -> Bool raise {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let trigger = region.source(0)
  let compute : (@incr_next.QueryContext, Unit) -> OwnedCutoff raise @incr_next.ReadError = (
    ctx,
    _unit,
  ) => {
    if ctx.get(trigger.view()) == 0 {
      OwnedCutoff::{ token: token_new(14), value: 7 }
    } else {
      OwnedCutoff::{ token: token_new(15), value: 7 }
    }
  }
  let query = region.query(compute, cutoff=@incr_next.Cutoff::type_owned())
  let view = query.view(())
  let first = Ok(store.get(view)) catch { error => Err(error) }
  let first_held = first is Ok(value) && value.value == 7 && live(14) == 1
  ignore(
    (
      store.transaction(tx => {
        tx.set(trigger, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let second = Ok(store.get(view)) catch { error => Err(error) }
  let replaced = second is Ok(value) &&
    value.value == 7 &&
    live(14) == 0 &&
    finalized(14) == 1 &&
    live(15) == 1
  region.close()
  first_held && replaced && live(15) == 0 && finalized(15) == 1
}

///|
fn probe_cutoff_dynamic_trace_replacement() -> Bool raise {
  let store = @incr_next.Store::Store()
  let child_region = store.region()
  let parent_region = store.region()
  let selector = parent_region.source(0)
  let child = child_region.query((_ctx, key : TraceKey) => key.id)
  let parent = parent_region.query(
    (ctx, _unit : Unit) => {
      let flag = ctx.get(selector.view())
      let key = trace_key(if flag == 0 { 24 } else { 25 }, flag)
      ignore(ctx.get(child.view(key)))
      OwnedCutoff::{
        token: token_new(if flag == 0 { 29 } else { 31 }),
        value: 7,
      }
    },
    cutoff=@incr_next.Cutoff::type_owned(),
  )

  let view = parent.view(())
  let initial = match (Ok(store.get(view)) catch { error => Err(error) }) {
    Ok(value) => value.value == 7
    Err(_) => false
  }
  let initial_owners = live(24) == 1 &&
    live(25) == 0 &&
    live(29) == 1 &&
    live(31) == 0
  ignore(
    (
      store.transaction(tx => {
        tx.set(selector, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let replaced = match (Ok(store.get(view)) catch { error => Err(error) }) {
    Ok(value) => value.value == 7
    Err(_) => false
  }
  let newest = live(24) == 1 &&
    live(25) == 1 &&
    live(29) == 0 &&
    finalized(29) == 1 &&
    live(31) == 1
  child_region.close()
  let after_child_close = live(24) == 0 &&
    finalized(24) == 1 &&
    live(25) == 1 &&
    live(31) == 1
  parent_region.close()
  let after_parent_close = live(25) == 0 &&
    finalized(25) == 1 &&
    live(31) == 0 &&
    finalized(31) == 1
  initial &&
  initial_owners &&
  replaced &&
  newest &&
  after_child_close &&
  after_parent_close
}

///|
fn probe_query_capture_close() -> Bool raise {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let captured = payload(12, 41)
  let query = region.query((_ctx, _unit : Unit) => {
    ignore(captured.token)
    captured.value
  })

  ignore(query)
  region.close()
  live(12) == 0 && finalized(12) == 1
}

///|
fn probe_external_alias_control() -> Bool raise {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let external_payload = Ref(Some(payload(13, 42)))
  let query = region.query((_ctx, _unit : Unit) => {
    match external_payload.val {
      Some(value) => {
        ignore(value.token)
        value.value
      }
      None => 0
    }
  })

  ignore(query)
  region.close()
  let retained = live(13) == 1 && finalized(13) == 0
  external_payload.val = None
  retained && live(13) == 0 && finalized(13) == 1
}

///|
fn probe_commit_replacement() -> Bool raise {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let source = region.source(payload(10, 0))
  let result : Result[Unit, Unit] = store.transaction(tx => {
    tx.set(source, payload(11, 1))
    Ok(())
  })
  let replaced = result is Ok(_) &&
    live(10) == 0 &&
    finalized(10) == 1 &&
    live(11) == 1
  region.close()
  replaced && live(11) == 0 && finalized(11) == 1
}

///|
fn probe_successful_recompute_releases_old_memo_value_and_trace() -> Bool raise {
  let store = @incr_next.Store::Store()
  let child_region = store.region()
  let parent_region = store.region()
  let selector = parent_region.source(0)
  let child = child_region.query((_ctx, key : TraceKey) => key.id)
  let parent = parent_region.query((ctx, _unit : Unit) => {
    let flag = ctx.get(selector.view())
    let key = trace_key(if flag == 0 { 16 } else { 17 }, flag)
    payload(if flag == 0 { 18 } else { 19 }, ctx.get(child.view(key)))
  })

  let view = parent.view(())
  let initial_value = match
    (Ok(store.get(view)) catch { error => Err(error) }) {
    Ok(value) => value.value
    Err(_) => -1
  }
  let initial = initial_value == 0 &&
    live(16) == 1 &&
    live(17) == 0 &&
    live(18) == 1 &&
    live(19) == 0
  ignore(
    (
      store.transaction(tx => {
        tx.set(selector, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let next_value = match (Ok(store.get(view)) catch { error => Err(error) }) {
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
  child_region.close()
  let old_trace_released = live(16) == 0 && finalized(16) == 1 && live(17) == 1
  parent_region.close()
  let closed = live(17) == 0 &&
    finalized(17) == 1 &&
    live(19) == 0 &&
    finalized(19) == 1
  initial && replaced && old_trace_released && closed
}

///|
fn probe_failed_recompute_releases_temporary_trace() -> Bool raise {
  let store = @incr_next.Store::Store()
  let foreign_store = @incr_next.Store::Store()
  let child_region = store.region()
  let parent_region = store.region()
  let foreign_region = foreign_store.region()
  let selector = parent_region.source(0)
  let foreign = foreign_region.source(9)
  let child = child_region.query((_ctx, key : TraceKey) => key.id)
  let parent = parent_region.query((ctx, _unit : Unit) => {
    let flag = ctx.get(selector.view())
    let key = trace_key(if flag == 0 { 20 } else { 21 }, flag)
    let value = ctx.get(child.view(key))
    if flag == 1 {
      payload(23, ctx.get(foreign.view()))
    } else {
      payload(22, value)
    }
  })

  let view = parent.view(())
  let initial_value = match
    (Ok(store.get(view)) catch { error => Err(error) }) {
    Ok(value) => value.value
    Err(_) => -1
  }
  ignore(
    (
      store.transaction(tx => {
        tx.set(selector, 1)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let failed = (Ok(store.get(view)) catch { error => Err(error) })
    is Err(@incr_next.ReadError::CrossStore(_))
  let old_authority = live(20) == 1 && live(21) == 1 && live(22) == 1
  child_region.close()
  let temporary_released = live(20) == 1 &&
    live(21) == 0 &&
    finalized(21) == 1 &&
    live(22) == 1
  parent_region.close()
  foreign_region.close()
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
fn probe_close_releases_memo_payloads_but_view_keeps_key() -> Bool raise {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let source = region.source(1)
  let child = region.query((_ctx, key : TraceKey) => key.id)
  let query = region.query((ctx, _key : TraceKey) => {
    let value = ctx.get(child.view(trace_key(27, 0)))
    ignore(ctx.get(source.view()))
    payload(28, value)
  })

  let view = Ref(Some(query.view(trace_key(26, 0))))
  let read_ok = match
    (Ok(store.get(view.val.unwrap())) catch { error => Err(error) }) {
    Ok(value) => value.value == 0
    Err(_) => false
  }
  let retained_before_close = live(26) == 1 && live(27) == 1 && live(28) == 1
  region.close()
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
fn probe_cycle_diagnostic_does_not_retain_key() -> Bool raise {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let self_view : Ref[@incr_next.View[Int]?] = Ref(None)
  let query = region.query((ctx, _key : TraceKey) => {
    ctx.get(self_view.val.unwrap())
  })

  let view = Ref(Some(query.view(trace_key(30, 0))))
  self_view.val = view.val
  let result = Ok(store.get(view.val.unwrap())) catch { error => Err(error) }
  let held_error = Ref(Some(result))
  let diagnostic_held = match held_error.val {
    Some(Err(@incr_next.ReadError::Cycle(diagnostic))) =>
      diagnostic.message().length() > 0
    _ => false
  }
  let retained_by_view = live(30) == 1 && finalized(30) == 0
  self_view.val = None
  view.val = None
  let released_before_close = live(30) == 0 && finalized(30) == 1
  let diagnostic_still_held = match held_error.val {
    Some(Err(@incr_next.ReadError::Cycle(diagnostic))) =>
      diagnostic.message().length() > 0
    _ => false
  }
  region.close()
  diagnostic_held &&
  retained_by_view &&
  released_before_close &&
  diagnostic_still_held
}

///|
fn main raise {
  let close = probe_close()
  let callback_rollback = probe_callback_rollback()
  let poison_rollback = probe_poison_rollback()
  let last_write_wins = probe_last_write_wins()
  let commit_replacement = probe_commit_replacement()
  let successful_recompute = probe_successful_recompute_releases_old_memo_value_and_trace()
  let failed_recompute = probe_failed_recompute_releases_temporary_trace()
  let memo_close = probe_close_releases_memo_payloads_but_view_keeps_key()
  let cycle_diagnostic = probe_cycle_diagnostic_does_not_retain_key()
  let query_capture_close = probe_query_capture_close()
  let cutoff_capture = probe_cutoff_releases_old_memo_value()
  let external_alias = probe_external_alias_control()
  let passed = close &&
    callback_rollback &&
    poison_rollback &&
    last_write_wins &&
    commit_replacement &&
    successful_recompute &&
    failed_recompute &&
    memo_close &&
    cycle_diagnostic &&
    query_capture_close &&
    cutoff_capture &&
    probe_cutoff_dynamic_trace_replacement() &&
    external_alias
  let verdict = if passed { "PASS" } else { "FAIL" }
  println("native RC/finalizer evidence: \{verdict}")
  if !passed {
    abort("native RC/finalizer evidence failed")
  }
}
