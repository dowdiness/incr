///|
priv type RcProbeToken

///|
extern "C" fn token_new(kind : Int) -> RcProbeToken = "incr_next_incremental_token_new"

///|
#borrow(token)
extern "C" fn token_touch(token : RcProbeToken) -> Unit = "incr_next_incremental_token_touch"

///|
extern "C" fn live(kind : Int) -> Int = "incr_next_incremental_live"

///|
extern "C" fn finalized(kind : Int) -> Int = "incr_next_incremental_finalized"

///|
priv struct Observed {
  token : RcProbeToken
  value : Int
}

///|
fn Observed::Observed(token : RcProbeToken, value : Int) -> Observed {
  { token, value }
}

///| Key marker used to distinguish table ownership from View/trace retention.
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
fn region(result : Result[@provider.Region, @provider.RegionError]) -> @provider.Region {
  match result {
    Ok(value) => value
    Err(_) => abort("region")
  }
}

///|
fn[T] source(result : Result[@provider.Source[T], @provider.RegionError]) -> @provider.Source[T] {
  match result {
    Ok(value) => value
    Err(_) => abort("source")
  }
}

///|
fn[K, V] query(result : Result[@provider.Query[K, V], @provider.RegionError]) -> @provider.Query[K, V] {
  match result {
    Ok(value) => value
    Err(_) => abort("query")
  }
}

///| Close cuts Source payload, Query compute capture, and table-owned memo value.
fn probe_close_owned_state() -> Bool {
  let store = @provider.Store()
  let region = region(store.region())
  let input = source(region.source(Observed::Observed(token_new(0), 7)))
  let compute_marker = token_new(1)
  let projection = query(region.query((ctx, _ : Unit) => {
    token_touch(compute_marker)
    match ctx.read(input.view()) {
      Ok(observed) => {
        token_touch(observed.token)
        Ok(Observed::Observed(token_new(4), observed.value))
      }
      Err(error) => Err(error)
    }
  }))
  let view = projection.at(())
  let populated = match store.read(view) {
    Ok(value) => {
      token_touch(value.token)
      value.value == 7
    }
    Err(_) => false
  }
  let before = (live(0), live(1), live(4), projection.debug().memo_count)
  ignore(region.close())
  let after = (live(0), live(1), live(4), projection.debug().memo_count)
  let tombstone = store.read(view) is Err(@provider.ReadError::ClosedRegion(_))
  populated && before == (1, 1, 1, 1) && after == (0, 0, 0, 0) &&
  finalized(0) == 1 && finalized(1) == 1 && finalized(4) == 1 && tombstone
}

///| Rollback releases staged ownership; commit replaces old committed payload.
fn probe_transaction_ownership() -> Bool {
  let store = @provider.Store()
  let region = region(store.region())
  let value = source(region.source(Observed::Observed(token_new(8), 0)))
  let rollback = store.transaction(tx => {
    ignore(tx.set(value, Observed::Observed(token_new(2), 1)))
    Err(@provider.TransactionError::CallbackRejected)
  })
  let staged = rollback is Err(@provider.TransactionError::CallbackRejected) &&
    live(2) == 0 && finalized(2) == 1
  let commit = store.transaction(tx =>
    tx.set(value, Observed::Observed(token_new(3), 2)))
  let replaced = commit is Ok(_) && live(3) == 1 && live(8) == 0 &&
    finalized(8) == 1
  ignore(region.close())
  staged && replaced && live(3) == 0 && finalized(3) == 1
}

///| Finite same-Query recursion creates memo->dependency->QueryCore SCCs.
fn probe_recursive_trace_scc() -> Bool {
  let store = @provider.Store()
  let region = region(store.region())
  let compute_marker = token_new(5)
  let recursive_ref : Ref[@provider.Query[Int, Int]?] = Ref(None)
  let recursive = query(region.query((ctx, key : Int) => {
    token_touch(compute_marker)
    if key == 0 {
      Ok(0)
    } else {
      match recursive_ref.val {
        Some(self) => match ctx.read(self.at(key - 1)) {
          Ok(value) => Ok(value + 1)
          Err(error) => Err(error)
        }
        None => Err(@provider.ReadError::ClosedRegion(generation=region.generation()))
      }
    }
  }))
  recursive_ref.val = Some(recursive)
  let surviving_view = recursive.at(3)
  let populated = store.read(surviving_view) == Ok(3) &&
    recursive.debug().memo_count == 4 && live(5) == 1
  ignore(region.close())
  populated && recursive.debug().memo_count == 0 &&
    !recursive.debug().compute_available && live(5) == 0 && finalized(5) == 1 &&
    store.read(surviving_view) is Err(@provider.ReadError::ClosedRegion(_))
}

///| Successful recompute releases the previous memo value before Region close.
fn probe_successful_memo_replacement() -> Bool {
  let store = @provider.Store()
  let region = region(store.region())
  let input = source(region.source(1))
  let projection = query(region.query((ctx, _ : Unit) => {
    match ctx.read(input.view()) {
      Ok(value) => Ok(Observed::Observed(token_new(10), value))
      Err(error) => Err(error)
    }
  }))
  let first = match store.read(projection.at(())) {
    Ok(value) => { token_touch(value.token); value.value == 1 }
    Err(_) => false
  }
  ignore(store.transaction(tx => tx.set(input, 2)))
  let second = match store.read(projection.at(())) {
    Ok(value) => { token_touch(value.token); value.value == 2 }
    Err(_) => false
  }
  let old_released = first && second && live(10) == 1 && finalized(10) == 1
  ignore(region.close())
  old_released && live(10) == 0 && finalized(10) == 2
}

///| Successful dynamic trace replacement releases its old branch dependency.
fn probe_successful_trace_replacement() -> Bool {
  let store = @provider.Store()
  let left_region = region(store.region())
  let parent_region = region(store.region())
  let mode = source(parent_region.source(true))
  let left = query(left_region.query((_ctx, key : ObservedKey) => {
    token_touch(key.token)
    Ok(key.value)
  }))
  let parent = query(parent_region.query((ctx, _ : Unit) => {
    match ctx.read(mode.view()) {
      Err(error) => Err(error)
      Ok(true) => {
        let key = ObservedKey::ObservedKey(token_new(11), 11)
        ctx.read(left.at(key))
      }
      Ok(false) => Ok(9)
    }
  }))
  let initial = store.read(parent.at(())) == Ok(11) && live(11) == 1
  ignore(store.transaction(tx => tx.set(mode, false)))
  let replaced = store.read(parent.at(())) == Ok(9)
  ignore(left_region.close())
  let old_trace_released = live(11) == 0 && finalized(11) == 1
  ignore(parent_region.close())
  initial && replaced && old_trace_released
}

///| A failed target drops its temporary trace; successful upstream memo remains.
fn probe_failed_temporary_trace_release() -> Bool {
  let store = @provider.Store()
  let child_region = region(store.region())
  let failed_region = region(store.region())
  let parent_region = region(store.region())
  let unavailable = source(failed_region.source(1))
  let child = query(child_region.query((_ctx, key : ObservedKey) => {
    token_touch(key.token)
    Ok(key.value)
  }))
  ignore(failed_region.close())
  let parent = query(parent_region.query((ctx, _ : Unit) => {
    let key = ObservedKey::ObservedKey(token_new(9), 9)
    match ctx.read(child.at(key)) {
      Err(error) => Err(error)
      Ok(_) => ctx.read(unavailable.view())
    }
  }))
  let failed = store.read(parent.at(())) is Err(@provider.ReadError::ClosedRegion(_))
  let upstream_remains = parent.debug().memo_count == 0 &&
    child.debug().memo_count == 1 && live(9) == 1
  ignore(child_region.close())
  let released_after_upstream_close = live(9) == 0 && finalized(9) == 1
  ignore(parent_region.close())
  failed && upstream_remains && released_after_upstream_close
}

///| A surviving View retains its captured key after table ownership is cut.
fn probe_view_key_retention_inside_scope() -> Bool {
  let store = @provider.Store()
  let region = region(store.region())
  let keyed = query(region.query((_ctx, key : ObservedKey) => {
    token_touch(key.token)
    Ok(key.value)
  }))
  let view = keyed.at(ObservedKey::ObservedKey(token_new(6), 6))
  let read = store.read(view) == Ok(6)
  ignore(region.close())
  read && keyed.debug().memo_count == 0 && live(6) == 1 &&
    store.read(view) is Err(@provider.ReadError::ClosedRegion(_))
}

///| A downstream trace may retain an upstream tombstone/key until replacement.
fn probe_downstream_tombstone_retention() -> Bool {
  let store = @provider.Store()
  let upstream_region = region(store.region())
  let downstream_region = region(store.region())
  let mode = source(downstream_region.source(true))
  let upstream = query(upstream_region.query((_ctx, key : ObservedKey) => {
    token_touch(key.token)
    Ok(key.value)
  }))
  let downstream = query(downstream_region.query((ctx, _ : Unit) => {
    match ctx.read(mode.view()) {
      Err(error) => Err(error)
      Ok(true) => {
        let key = ObservedKey::ObservedKey(token_new(7), 7)
        ctx.read(upstream.at(key))
      }
      Ok(false) => Ok(9)
    }
  }))
  let initial = store.read(downstream.at(())) == Ok(7) && live(7) == 1
  ignore(upstream_region.close())
  let retained_by_downstream = upstream.debug().memo_count == 0 && live(7) == 1
  ignore(store.transaction(tx => tx.set(mode, false)))
  let replaced = store.read(downstream.at(())) == Ok(9) &&
    live(7) == 0 && finalized(7) == 1
  ignore(downstream_region.close())
  initial && retained_by_downstream && replaced
}

///|
fn main {
  let close = probe_close_owned_state()
  let transaction = probe_transaction_ownership()
  let recursive_scc = probe_recursive_trace_scc()
  let memo_replacement = probe_successful_memo_replacement()
  let trace_replacement = probe_successful_trace_replacement()
  let failed_temporary_trace = probe_failed_temporary_trace_release()
  let view_key_inside = probe_view_key_retention_inside_scope()
  let view_key_released_after_scope = live(6) == 0 && finalized(6) == 1
  let downstream_tombstone = probe_downstream_tombstone_retention()
  let passed = close && transaction && recursive_scc && memo_replacement &&
    trace_replacement && failed_temporary_trace && view_key_inside &&
    view_key_released_after_scope && downstream_tombstone
  println("INCR NEXT — #462 INCREMENTAL NATIVE RC")
  println("close_owned_source_compute_memo=\{close}")
  println("transaction_staged_and_committed_replacement=\{transaction}")
  println("finite_recursive_trace_scc_cut=\{recursive_scc}")
  println("successful_memo_value_replaced=\{memo_replacement}")
  println("successful_old_branch_trace_replaced=\{trace_replacement}")
  println("failed_temporary_trace_released=\{failed_temporary_trace}")
  println("view_key_retained_until_view_drop=\{view_key_inside && view_key_released_after_scope}")
  println("downstream_tombstone_retained_then_replaced=\{downstream_tombstone}")
  println("full_state live=[\{live(0)},\{live(1)},\{live(2)},\{live(3)},\{live(4)},\{live(5)},\{live(6)},\{live(7)},\{live(8)},\{live(9)},\{live(10)},\{live(11)}] finalized=[\{finalized(0)},\{finalized(1)},\{finalized(2)},\{finalized(3)},\{finalized(4)},\{finalized(5)},\{finalized(6)},\{finalized(7)},\{finalized(8)},\{finalized(9)},\{finalized(10)},\{finalized(11)}]")
  println("constrained verdict: \{if passed { "PASS" } else { "FAIL" }}")
  if !passed { abort("native RC evidence failed") }
}
