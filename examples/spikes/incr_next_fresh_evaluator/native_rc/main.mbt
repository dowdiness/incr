///|
/// Native external token used only as a compiled ownership marker.
priv type RcProbeToken

///|
/// Allocates one external marker.
extern "C" fn token_new(kind : Int) -> RcProbeToken = "incr_next_fresh_token_new"

///|
/// Keeps a marker capture observable without retaining it elsewhere.
#borrow(token)
extern "C" fn token_touch(token : RcProbeToken) -> Unit = "incr_next_fresh_token_touch"

///|
/// Returns live markers for one category.
extern "C" fn live(kind : Int) -> Int = "incr_next_fresh_live"

///|
/// Returns finalized markers for one category.
extern "C" fn finalized(kind : Int) -> Int = "incr_next_fresh_finalized"

///|
/// Payload used for committed and staged ownership observations.
priv struct ObservedPayload {
  token : RcProbeToken
  value : Int
}

///|
/// Creates one observed payload.
fn ObservedPayload::ObservedPayload(
  token : RcProbeToken,
  value : Int,
) -> ObservedPayload {
  { token, value }
}

///|
/// Returns a Region or aborts this evidence executable.
fn must_region(
  result : Result[@provider.Region, @provider.RegionError],
) -> @provider.Region {
  match result {
    Ok(region) => region
    Err(_) => abort("expected Region")
  }
}

///|
/// Returns a Source or aborts this evidence executable.
fn[T] must_source(
  result : Result[@provider.Source[T], @provider.RegionError],
) -> @provider.Source[T] {
  match result {
    Ok(source) => source
    Err(_) => abort("expected Source")
  }
}

///|
/// Returns a Query or aborts this evidence executable.
fn[K, V] must_query(
  result : Result[@provider.Query[K, V], @provider.RegionError],
) -> @provider.Query[K, V] {
  match result {
    Ok(query) => query
    Err(_) => abort("expected Query")
  }
}

///|
/// Region close releases Source payload and Query compute capture with Views alive.
fn probe_region_close() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let source = must_source(region.source(ObservedPayload(token_new(0), 7)))
  let compute_token = token_new(1)
  let query = must_query(
    region.query((ctx, _unit : Unit) => {
      token_touch(compute_token)
      match ctx.read(source.view()) {
        Ok(payload) => {
          token_touch(payload.token)
          Ok(payload.value)
        }
        Err(error) => Err(error)
      }
    }),
  )
  let source_view = source.view()
  let query_view = query.at(())
  ignore(store.read(query_view))
  let before = (live(0), live(1))
  ignore(region.close())
  let after = (live(0), live(1))
  let source_closed = store.read(source_view)
    is Err(@provider.ReadError::ClosedRegion(_))
  let query_closed = store.read(query_view)
    is Err(@provider.ReadError::ClosedRegion(_))
  before == (1, 1) &&
  after == (0, 0) &&
  finalized(0) == 1 &&
  finalized(1) == 1 &&
  source_closed &&
  query_closed
}

///|
/// Callback rejection drops the transaction-local staged payload.
fn probe_callback_rollback() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let source = must_source(region.source(ObservedPayload(token_new(99), 0)))
  let result = store.transaction(tx => {
    ignore(tx.set(source, ObservedPayload(token_new(2), 1)))
    Err(@provider.TransactionError::CallbackRejected)
  })
  let released = result is Err(@provider.TransactionError::CallbackRejected) &&
    live(2) == 0 &&
    finalized(2) == 1
  ignore(region.close())
  released
}

///|
/// Ignored invalid set poisons and drops the earlier valid staged payload.
fn probe_poison_rollback() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let source = must_source(region.source(ObservedPayload(token_new(99), 0)))
  let other_store = @provider.Store()
  let other_region = must_region(other_store.region())
  let other = must_source(
    other_region.source(ObservedPayload(token_new(99), 0)),
  )
  let result = store.transaction(tx => {
    ignore(tx.set(source, ObservedPayload(token_new(3), 1)))
    ignore(tx.set(other, ObservedPayload(token_new(99), 2)))
    Ok(())
  })
  let released = result is Err(@provider.TransactionError::CrossStore(_)) &&
    live(3) == 0 &&
    finalized(3) == 1
  ignore(region.close())
  ignore(other_region.close())
  released
}

///|
/// Successful commit releases old payload; Region close releases current payload.
fn probe_commit_replacement() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let source = must_source(region.source(ObservedPayload(token_new(4), 0)))
  let result = store.transaction(tx => {
    tx.set(source, ObservedPayload(token_new(5), 1))
  })
  let after_commit = result is Ok(_) &&
    live(4) == 0 &&
    finalized(4) == 1 &&
    live(5) == 1
  ignore(region.close())
  after_commit && live(5) == 0 && finalized(5) == 1
}

///|
/// Last-write-wins releases the superseded staged closure during the callback.
fn probe_staged_replacement() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let source = must_source(region.source(ObservedPayload(token_new(99), 0)))
  let superseded_released = Ref(false)
  let result = store.transaction(tx => {
    ignore(tx.set(source, ObservedPayload(token_new(6), 1)))
    ignore(tx.set(source, ObservedPayload(token_new(7), 2)))
    superseded_released.val = live(6) == 0 && finalized(6) == 1
    Ok(())
  })
  let committed_current = result is Ok(_) && live(7) == 1
  ignore(region.close())
  superseded_released.val &&
  committed_current &&
  live(7) == 0 &&
  finalized(7) == 1
}

///|
/// Runs native external-finalizer evidence and prints every category.
fn main {
  let region_close = probe_region_close()
  let callback_rollback = probe_callback_rollback()
  let poison_rollback = probe_poison_rollback()
  let commit_replacement = probe_commit_replacement()
  let staged_replacement = probe_staged_replacement()
  let passed = region_close &&
    callback_rollback &&
    poison_rollback &&
    commit_replacement &&
    staged_replacement
  println("INCR NEXT — FRESH EVALUATOR NATIVE RC")
  println("region_close_source_and_compute=\{region_close}")
  println("callback_rollback_staged_payload=\{callback_rollback}")
  println("poison_rollback_staged_payload=\{poison_rollback}")
  println("commit_old_then_close_current=\{commit_replacement}")
  println("last_write_releases_superseded_stage=\{staged_replacement}")
  println(
    "full_state live=[\{live(0)},\{live(1)},\{live(2)},\{live(3)},\{live(4)},\{live(5)},\{live(6)},\{live(7)}] finalized=[\{finalized(0)},\{finalized(1)},\{finalized(2)},\{finalized(3)},\{finalized(4)},\{finalized(5)},\{finalized(6)},\{finalized(7)}]",
  )
  println("constrained verdict: \{if passed { "PASS" } else { "FAIL" }}")
  if !passed {
    abort("native RC evidence failed")
  }
}
