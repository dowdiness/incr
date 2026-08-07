///|
priv type RcProbeToken

///|
extern "C" fn token_new(kind : Int) -> RcProbeToken = "incr_next_cycle_token_new"

///|
#borrow(token)
extern "C" fn token_touch(token : RcProbeToken) -> Unit = "incr_next_cycle_token_touch"

///|
extern "C" fn live(kind : Int) -> Int = "incr_next_cycle_live"

///|
extern "C" fn finalized(kind : Int) -> Int = "incr_next_cycle_finalized"

///|
priv struct ObservedKey {
  token : RcProbeToken
  value : Int
}

///|
fn ObservedKey::ObservedKey(token : RcProbeToken, value : Int) -> ObservedKey {
  { token, value }
}

///|
impl Hash for ObservedKey with fn hash(self) {
  self.value.hash()
}

///|
impl Hash for ObservedKey with fn hash_combine(self, hasher) {
  self.value.hash_combine(hasher)
}

///|
impl Eq for ObservedKey with fn equal(self, other) -> Bool {
  self.value == other.value
}

///|
priv struct ObservedValue {
  token : RcProbeToken
  value : Int
}

///|
fn fresh_region(
  result : Result[@fresh.Region, @fresh.RegionError],
) -> @fresh.Region {
  match result {
    Ok(value) => value
    Err(_) => abort("fresh region")
  }
}

///|
fn incremental_region(
  result : Result[@incremental.Region, @incremental.RegionError],
) -> @incremental.Region {
  match result {
    Ok(value) => value
    Err(_) => abort("incremental region")
  }
}

///|
fn[T] fresh_source(
  result : Result[@fresh.Source[T], @fresh.RegionError],
) -> @fresh.Source[T] {
  match result {
    Ok(value) => value
    Err(_) => abort("fresh source")
  }
}

///|
fn[T] incremental_source(
  result : Result[@incremental.Source[T], @incremental.RegionError],
) -> @incremental.Source[T] {
  match result {
    Ok(value) => value
    Err(_) => abort("incremental source")
  }
}

///|
fn[K, V] fresh_query(
  result : Result[@fresh.Query[K, V], @fresh.RegionError],
) -> @fresh.Query[K, V] {
  match result {
    Ok(value) => value
    Err(_) => abort("fresh query")
  }
}

///|
fn[K, V] incremental_query(
  result : Result[@incremental.Query[K, V], @incremental.RegionError],
) -> @incremental.Query[K, V] {
  match result {
    Ok(value) => value
    Err(_) => abort("incremental query")
  }
}

///|
/// A temporary fresh active key is released after successful evaluation.
fn probe_success_active_key() -> Bool {
  let store = @fresh.Store()
  let region = fresh_region(store.region())
  let child = fresh_query(
    region.query((_ctx, key : ObservedKey) => {
      token_touch(key.token)
      Ok(key.value)
    }),
  )
  let parent = fresh_query(
    region.query((ctx, _ : Unit) => {
      let key = ObservedKey::ObservedKey(token_new(0), 1)
      ctx.read(child.at(key))
    }),
  )
  let result = store.read(parent.at(())) == Ok(1)
  let released = live(0) == 0 &&
    finalized(0) == 1 &&
    child.debug().active_count == 0 &&
    parent.debug().active_count == 0 &&
    store.debug().last_finished_active_depth == 0
  ignore(region.close())
  result && released
}

///|
/// Nested equal key is released on Cycle; the surviving root View retains its key.
fn probe_cycle_active_key_inside_scope() -> Bool {
  let store = @fresh.Store()
  let region = fresh_region(store.region())
  let query_ref : Ref[@fresh.Query[ObservedKey, Int]?] = Ref(None)
  let query = fresh_query(
    region.query((ctx, key : ObservedKey) => {
      token_touch(key.token)
      match query_ref.val {
        Some(self) => {
          let nested = ObservedKey::ObservedKey(token_new(2), key.value)
          ctx.read(self.at(nested))
        }
        None => Ok(-1)
      }
    }),
  )
  query_ref.val = Some(query)
  let view = query.at(ObservedKey::ObservedKey(token_new(1), 1))
  let cycle = store.read(view) is Err(@fresh.ReadError::Cycle(_))
  let nested_released = live(2) == 0 && finalized(2) == 1
  ignore(region.close())
  let root_retained = live(1) == 1 &&
    query.debug().active_count == 0 &&
    store.debug().last_finished_active_depth == 0
  let tombstone = store.read(view) is Err(@fresh.ReadError::ClosedRegion(_))
  cycle && nested_released && root_retained && tombstone
}

///|
/// Active key is released when current compute returns another ReadError.
fn probe_other_error_active_key() -> Bool {
  let store = @fresh.Store()
  let closed_region = fresh_region(store.region())
  let live_region = fresh_region(store.region())
  let unavailable = fresh_source(closed_region.source(1))
  let child = fresh_query(
    live_region.query((ctx, key : ObservedKey) => {
      token_touch(key.token)
      ctx.read(unavailable.view())
    }),
  )
  let parent = fresh_query(
    live_region.query((ctx, _ : Unit) => {
      let key = ObservedKey::ObservedKey(token_new(3), 3)
      ctx.read(child.at(key))
    }),
  )
  ignore(closed_region.close())
  let failed = store.read(parent.at(()))
    is Err(@fresh.ReadError::ClosedRegion(_))
  let released = live(3) == 0 &&
    finalized(3) == 1 &&
    child.debug().active_count == 0 &&
    parent.debug().active_count == 0 &&
    store.debug().last_finished_active_depth == 0
  ignore(live_region.close())
  failed && released
}

///|
/// Failed parent Cycle drops its temporary trace; successful upstream memo remains.
fn probe_incremental_cycle_temporary_trace() -> Bool {
  let store = @incremental.Store()
  let child_region = incremental_region(store.region())
  let cycle_region = incremental_region(store.region())
  let parent_region = incremental_region(store.region())
  let child = incremental_query(
    child_region.query((_ctx, key : ObservedKey) => {
      token_touch(key.token)
      Ok(key.value)
    }),
  )
  let cycle_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let cycle = incremental_query(
    cycle_region.query((ctx, _ : Unit) => {
      match cycle_ref.val {
        Some(self) => ctx.read(self.at(()))
        None => Ok(-1)
      }
    }),
  )
  cycle_ref.val = Some(cycle)
  let parent = incremental_query(
    parent_region.query((ctx, _ : Unit) => {
      let key = ObservedKey::ObservedKey(token_new(4), 4)
      match ctx.read(child.at(key)) {
        Err(error) => Err(error)
        Ok(_) => ctx.read(cycle.at(()))
      }
    }),
  )
  let failed = store.read(parent.at(()))
    is Err(@incremental.ReadError::Cycle(_))
  let upstream_remains = parent.debug().memo_count == 0 &&
    child.debug().memo_count == 1 &&
    live(4) == 1
  ignore(child_region.close())
  let temporary_released = live(4) == 0 && finalized(4) == 1
  let clean = parent.debug().active_count + cycle.debug().active_count == 0 &&
    store.debug().last_finished_active_depth == 0
  ignore(cycle_region.close())
  ignore(parent_region.close())
  failed && upstream_remains && temporary_released && clean
}

///|
/// Cycle preserves old memo; retained witness owns only copied QueryIds.
fn probe_preserved_memo_and_witness() -> Bool {
  let store = @incremental.Store()
  let region = incremental_region(store.region())
  let mode = incremental_source(region.source(false))
  let compute_marker = token_new(6)
  let query_ref : Ref[@incremental.Query[Unit, ObservedValue]?] = Ref(None)
  let query = incremental_query(
    region.query((ctx, _ : Unit) => {
      token_touch(compute_marker)
      match ctx.read(mode.view()) {
        Err(error) => Err(error)
        Ok(false) => Ok(ObservedValue::{ token: token_new(5), value: 5 })
        Ok(true) =>
          match query_ref.val {
            Some(self) => ctx.read(self.at(()))
            None => Ok(ObservedValue::{ token: token_new(5), value: -1 })
          }
      }
    }),
  )
  query_ref.val = Some(query)
  let view = query.at(())
  let first = match store.read(view) {
    Ok(value) => {
      token_touch(value.token)
      value.value == 5
    }
    Err(_) => false
  }
  let before = query.memo_debug(())
  ignore(store.transaction(tx => tx.set(mode, true)))
  let retained_error = store.read(view)
  let cycle = retained_error is Err(@incremental.ReadError::Cycle(_))
  let after = query.memo_debug(())
  let preserved = match (before, after) {
    (Some(a), Some(b)) =>
      a.memo_id == b.memo_id &&
      a.verified_at == b.verified_at &&
      a.changed_at == b.changed_at &&
      a.trace_length == b.trace_length
    _ => false
  }
  let old_value_alive = live(5) == 1 && query.debug().memo_count == 1
  ignore(region.close())
  // retained_error remains in scope, so zero counts establish witness non-retention.
  let witness_is_value_only = retained_error
    is Err(@incremental.ReadError::Cycle(_)) &&
    live(5) == 0 &&
    live(6) == 0 &&
    finalized(5) == 1 &&
    finalized(6) == 1
  first &&
  cycle &&
  preserved &&
  old_value_alive &&
  witness_is_value_only &&
  query.debug().active_count == 0 &&
  store.debug().last_finished_active_depth == 0
}

///|
fn main {
  let success = probe_success_active_key()
  let cycle_inside = probe_cycle_active_key_inside_scope()
  let root_key_released_after_scope = live(1) == 0 && finalized(1) == 1
  let other_error = probe_other_error_active_key()
  let temporary = probe_incremental_cycle_temporary_trace()
  let preserved = probe_preserved_memo_and_witness()
  let passed = success &&
    cycle_inside &&
    root_key_released_after_scope &&
    other_error &&
    temporary &&
    preserved
  println("INCR NEXT — #463 CYCLE NATIVE RC")
  println("active_key_success_released=\{success}")
  println(
    "cycle_nested_key_released_view_key_retained_then_dropped=\{cycle_inside && root_key_released_after_scope}",
  )
  println("active_key_other_error_released=\{other_error}")
  println("cycle_temporary_trace_released_upstream_retained=\{temporary}")
  println("old_memo_preserved_witness_value_only=\{preserved}")
  println(
    "full_state live=[\{live(0)},\{live(1)},\{live(2)},\{live(3)},\{live(4)},\{live(5)},\{live(6)}] finalized=[\{finalized(0)},\{finalized(1)},\{finalized(2)},\{finalized(3)},\{finalized(4)},\{finalized(5)},\{finalized(6)}]",
  )
  println("constrained verdict: \{if passed { "PASS" } else { "FAIL" }}")
  if !passed {
    abort("cycle RC evidence failed")
  }
}
