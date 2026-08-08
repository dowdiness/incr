///|
priv type RcProbeToken

///|
extern "C" fn token_new(kind : Int) -> RcProbeToken = "incr_next_eviction_token_new"

///|
#borrow(token)
extern "C" fn token_touch(token : RcProbeToken) -> Unit = "incr_next_eviction_token_touch"

///|
extern "C" fn live(kind : Int) -> Int = "incr_next_eviction_live"

///|
extern "C" fn finalized(kind : Int) -> Int = "incr_next_eviction_finalized"

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
/// RC token identity is nonsemantic for this evidence value.
impl Eq for ObservedValue with fn equal(self, other) {
  self.value == other.value
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
/// Equivalent recompute replaces both old value and dynamic forward trace.
fn probe_equivalent_value_and_trace_replacement() -> Bool {
  let store = @incremental.Store()
  let left_region = incremental_region(store.region())
  let right_region = incremental_region(store.region())
  let query_region = incremental_region(store.region())
  let left = incremental_query(
    left_region.query((_ctx, key : ObservedKey) => {
      token_touch(key.token)
      Ok(key.value)
    }),
  )
  let right = incremental_query(
    right_region.query((_ctx, key : ObservedKey) => {
      token_touch(key.token)
      Ok(key.value)
    }),
  )
  let mode = incremental_source(query_region.source(false))
  let query = incremental_query(
    query_region.query_eq((ctx, _ : Unit) => {
      match ctx.read(mode.view()) {
        Err(error) => Err(error)
        Ok(false) => {
          let key = ObservedKey::ObservedKey(token_new(8), 0)
          match ctx.read(left.at(key)) {
            Err(error) => Err(error)
            Ok(value) => Ok(ObservedValue::{ token: token_new(7), value })
          }
        }
        Ok(true) => {
          let key = ObservedKey::ObservedKey(token_new(9), 0)
          match ctx.read(right.at(key)) {
            Err(error) => Err(error)
            Ok(value) => Ok(ObservedValue::{ token: token_new(10), value })
          }
        }
      }
    }),
  )
  let first = match store.read(query.at(())) {
    Ok(value) => {
      token_touch(value.token)
      value.value == 0
    }
    Err(_) => false
  }
  let before = match query.memo_debug(()) {
    Some(value) => value
    None => abort("equivalent RC memo")
  }
  ignore(store.transaction(tx => tx.set(mode, true)))
  let second = match store.read(query.at(())) {
    Ok(value) => {
      token_touch(value.token)
      value.value == 0
    }
    Err(_) => false
  }
  let after = match query.memo_debug(()) {
    Some(value) => value
    None => abort("equivalent RC replaced memo")
  }
  let old_value_released = live(7) == 0 && finalized(7) == 1
  // Closing the child clears its memo key. A stale old q trace would still own
  // that key, so finalization here discriminates trace replacement.
  ignore(left_region.close())
  let old_trace_released = live(8) == 0 && finalized(8) == 1
  let only_new_owned = live(9) == 1 &&
    live(10) == 1 &&
    after.memo_id == before.memo_id &&
    after.changed_at == before.changed_at &&
    after.verified_at.value() > before.verified_at.value()
  ignore(query_region.close())
  let new_memo_released = live(10) == 0 && finalized(10) == 1
  ignore(right_region.close())
  let new_source_released = live(9) == 0 && finalized(9) == 1
  first &&
  second &&
  old_value_released &&
  old_trace_released &&
  only_new_owned &&
  new_memo_released &&
  new_source_released
}

///|
/// Changed recompute follows the same single-value ownership rule.
fn probe_changed_value_replacement() -> Bool {
  let store = @incremental.Store()
  let region = incremental_region(store.region())
  let input = incremental_source(region.source(0))
  let query = incremental_query(
    region.query_eq((ctx, _ : Unit) => {
      match ctx.read(input.view()) {
        Err(error) => Err(error)
        Ok(value) =>
          Ok(ObservedValue::{
            token: token_new(if value == 0 { 11 } else { 12 }),
            value,
          })
      }
    }),
  )
  let first = match store.read(query.at(())) {
    Ok(value) => {
      token_touch(value.token)
      value.value == 0
    }
    Err(_) => false
  }
  ignore(store.transaction(tx => tx.set(input, 1)))
  let second = match store.read(query.at(())) {
    Ok(value) => {
      token_touch(value.token)
      value.value == 1
    }
    Err(_) => false
  }
  let old_released = live(11) == 0 && finalized(11) == 1 && live(12) == 1
  ignore(region.close())
  first && second && old_released && live(12) == 0 && finalized(12) == 1
}

///|
/// Eviction releases the table-owned value and obsolete dependency trace.
fn probe_evicted_value_and_trace() -> Bool {
  let store = @incremental.Store()
  let child_region = incremental_region(store.region())
  let query_region = incremental_region(store.region())
  let child = incremental_query(
    child_region.query((_ctx, key : ObservedKey) => {
      token_touch(key.token)
      Ok(key.value)
    }),
  )
  let traced = incremental_query(
    query_region.query((ctx, _ : Unit) => {
      let key = ObservedKey::ObservedKey(token_new(14), 0)
      match ctx.read(child.at(key)) {
        Err(error) => Err(error)
        Ok(value) => Ok(ObservedValue::{ token: token_new(13), value })
      }
    }),
  )
  let first = match store.read(traced.at(())) {
    Ok(value) => {
      token_touch(value.token)
      value.value == 0
    }
    Err(_) => false
  }
  let removed = traced.evict_memo(()) == Ok(true) &&
    traced.debug().memo_count == 0 &&
    live(13) == 0 &&
    finalized(13) == 1
  // The child memo still owns key 14. Closing it clears that owner; a stale
  // evicted trace would keep the key alive.
  ignore(child_region.close())
  let trace_released = live(14) == 0 && finalized(14) == 1
  ignore(query_region.close())
  first && removed && trace_released
}

///|
/// An external value alias may outlive removal of the table-owned reference.
fn probe_external_alias_survives() -> Bool {
  let store = @incremental.Store()
  let region = incremental_region(store.region())
  let query = incremental_query(
    region.query((_ctx, _ : Unit) => {
      Ok(ObservedValue::{ token: token_new(15), value: 15 })
    }),
  )
  let retained_value = match store.read(query.at(())) {
    Ok(value) => value
    Err(_) => abort("eviction external alias")
  }
  let removed = query.evict_memo(()) == Ok(true) &&
    query.debug().memo_count == 0
  let alias_alive = live(15) == 1
  token_touch(retained_value.token)
  ignore(region.close())
  removed && alias_alive && live(15) == 1 && retained_value.value == 15
}

///|
/// A surviving View owns its key independently from an evicted memo table key.
fn probe_surviving_view_key() -> Bool {
  let store = @incremental.Store()
  let region = incremental_region(store.region())
  let query = incremental_query(
    region.query((_ctx, key : ObservedKey) => {
      token_touch(key.token)
      Ok(key.value)
    }),
  )
  let view = query.at(ObservedKey::ObservedKey(token_new(16), 16))
  let first = store.read(view) == Ok(16)
  let removed = query.evict_memo(ObservedKey::ObservedKey(token_new(16), 16)) ==
    Ok(true)
  // The temporary equal lookup key finalizes; the View's original key remains.
  let view_retains = live(16) == 1 && query.debug().memo_count == 0
  ignore(region.close())
  let tombstone = store.read(view)
    is Err(@incremental.ReadError::ClosedRegion(_))
  first && removed && view_retains && tombstone
}

///|
/// A downstream trace retains the child QueryCore/key recipe after child eviction.
fn probe_downstream_trace_retention() -> Bool {
  let store = @incremental.Store()
  let child_region = incremental_region(store.region())
  let parent_region = incremental_region(store.region())
  let child = incremental_query(
    child_region.query((_ctx, key : ObservedKey) => {
      token_touch(key.token)
      Ok(key.value)
    }),
  )
  let parent = incremental_query(
    parent_region.query((ctx, _ : Unit) => {
      let key = ObservedKey::ObservedKey(token_new(17), 17)
      ctx.read(child.at(key))
    }),
  )
  let first = store.read(parent.at(())) == Ok(17)
  let removed = child.evict_memo(ObservedKey::ObservedKey(token_new(17), 17)) ==
    Ok(true)
  ignore(child_region.close())
  let downstream_retains = live(17) == 1 && parent.debug().memo_count == 1
  ignore(parent_region.close())
  first && removed && downstream_retains && live(17) == 0 && finalized(17) == 2
}

///|
/// Per-key removal releases only that entry's value.
fn probe_per_key_isolation() -> Bool {
  let store = @incremental.Store()
  let region = incremental_region(store.region())
  let query = incremental_query(
    region.query((_ctx, key : Int) => {
      Ok(ObservedValue::{
        token: token_new(if key == 1 { 18 } else { 19 }),
        value: key,
      })
    }),
  )
  let a = match store.read(query.at(1)) {
    Ok(value) => value.value == 1
    Err(_) => false
  }
  let b = match store.read(query.at(2)) {
    Ok(value) => value.value == 2
    Err(_) => false
  }
  let removed = query.evict_memo(1) == Ok(true)
  let isolated = live(18) == 0 &&
    finalized(18) == 1 &&
    live(19) == 1 &&
    query.memo_debug(2) is Some(_)
  ignore(region.close())
  a && b && removed && isolated && live(19) == 0 && finalized(19) == 1
}

///|
/// Rematerialization never retains old and new memo values together.
fn probe_rematerialization_replaces_incarnation() -> Bool {
  let store = @incremental.Store()
  let region = incremental_region(store.region())
  let mode = incremental_source(region.source(false))
  let query = incremental_query(
    region.query((ctx, _ : Unit) => {
      match ctx.read(mode.view()) {
        Err(error) => Err(error)
        Ok(value) =>
          Ok(ObservedValue::{
            token: token_new(if value { 21 } else { 20 }),
            value: if value {
              21
            } else {
              20
            },
          })
      }
    }),
  )
  let first = match store.read(query.at(())) {
    Ok(value) => value.value == 20
    Err(_) => false
  }
  let removed = query.evict_memo(()) == Ok(true) &&
    live(20) == 0 &&
    finalized(20) == 1
  ignore(store.transaction(tx => tx.set(mode, true)))
  let second = match store.read(query.at(())) {
    Ok(value) => value.value == 21
    Err(_) => false
  }
  let only_new = live(20) == 0 && live(21) == 1 && query.debug().memo_count == 1
  ignore(region.close())
  first && removed && second && only_new && live(21) == 0 && finalized(21) == 1
}

///|
fn main {
  let success = probe_success_active_key()
  let cycle_inside = probe_cycle_active_key_inside_scope()
  let root_key_released_after_scope = live(1) == 0 && finalized(1) == 1
  let other_error = probe_other_error_active_key()
  let temporary = probe_incremental_cycle_temporary_trace()
  let preserved = probe_preserved_memo_and_witness()
  let equivalent = probe_equivalent_value_and_trace_replacement()
  let changed = probe_changed_value_replacement()
  let evicted = probe_evicted_value_and_trace()
  let external_alias = probe_external_alias_survives()
  let external_alias_released = live(15) == 0 && finalized(15) == 1
  let view_key = probe_surviving_view_key()
  let view_key_released = live(16) == 0 && finalized(16) == 2
  let downstream = probe_downstream_trace_retention()
  let per_key = probe_per_key_isolation()
  let rematerialized = probe_rematerialization_replaces_incarnation()
  let passed = success &&
    cycle_inside &&
    root_key_released_after_scope &&
    other_error &&
    temporary &&
    preserved &&
    equivalent &&
    changed &&
    evicted &&
    external_alias &&
    external_alias_released &&
    view_key &&
    view_key_released &&
    downstream &&
    per_key &&
    rematerialized
  println("INCR NEXT — MEMO EVICTION NATIVE RC")
  println("active_key_success_released=\{success}")
  println(
    "cycle_nested_key_released_view_key_retained_then_dropped=\{cycle_inside && root_key_released_after_scope}",
  )
  println("active_key_other_error_released=\{other_error}")
  println("cycle_temporary_trace_released_upstream_retained=\{temporary}")
  println("old_memo_preserved_witness_value_only=\{preserved}")
  println("equivalent_replaces_value_and_trace=\{equivalent}")
  println("changed_replaces_value=\{changed}")
  println("evicted_value_and_trace_released=\{evicted}")
  println(
    "external_alias_survives_then_releases=\{external_alias && external_alias_released}",
  )
  println(
    "surviving_view_key_survives_then_releases=\{view_key && view_key_released}",
  )
  println("downstream_trace_retains_recipe=\{downstream}")
  println("per_key_ownership_isolated=\{per_key}")
  println("rematerialization_single_incarnation=\{rematerialized}")
  println(
    "full_state live=[\{live(0)},\{live(1)},\{live(2)},\{live(3)},\{live(4)},\{live(5)},\{live(6)},\{live(7)},\{live(8)},\{live(9)},\{live(10)},\{live(11)},\{live(12)},\{live(13)},\{live(14)},\{live(15)},\{live(16)},\{live(17)},\{live(18)},\{live(19)},\{live(20)},\{live(21)}]",
  )
  println("constrained verdict: \{if passed { "PASS" } else { "FAIL" }}")
  if !passed {
    abort("eviction RC evidence failed")
  }
}
