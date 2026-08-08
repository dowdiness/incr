///| Key trait calls are observable only to prove rejection precedes lookup.
struct HostileEvictionKey {
  calls : Ref[Int]
}

///|
impl Hash for HostileEvictionKey with fn hash(self) {
  self.calls.val = self.calls.val + 1
  0
}

///|
impl Hash for HostileEvictionKey with fn hash_combine(self, hasher) {
  self.calls.val = self.calls.val + 1
  Hash::hash_combine(self.calls.val, hasher)
}

///|
impl Eq for HostileEvictionKey with fn equal(self, _other) {
  self.calls.val = self.calls.val + 1
  true
}

///|
/// Direct View rematerialization and equal-key View sharing.
fn eviction_view_rematerialization() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_query = must_fresh_query(
    fresh_region.query_eq((_ctx, key : String) => Ok(key.length())),
  )
  let fresh_view = fresh_query.at("same")
  let fresh_first = fresh_store.read(fresh_view)
  let fresh_revision = fresh_store.revision()
  let fresh_evict = fresh_query.evict_memo("same")
  let fresh_second = fresh_store.read(fresh_view)

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_query = must_inc_query(
    inc_region.query_eq((_ctx, key : String) => Ok(key.length())),
  )
  let first_view = inc_query.at("same")
  let equal_view = inc_query.at("same")
  let inc_first = inc_store.read(first_view)
  let first_memo = match inc_query.memo_debug("same") {
    Some(value) => value
    None => abort("eviction first memo")
  }
  let before_clocks = (inc_store.revision(), inc_store.change_epoch())
  let inc_evict = inc_query.evict_memo("same")
  let after_clocks = (inc_store.revision(), inc_store.change_epoch())
  let absent = inc_query.memo_debug("same") is None
  let duplicate = inc_query.evict_memo("same")
  let inc_second = inc_store.read(first_view)
  let second_memo = match inc_query.memo_debug("same") {
    Some(value) => value
    None => abort("eviction second memo")
  }
  let equal_read = inc_store.read(equal_view)
  let equal_memo = match inc_query.memo_debug("same") {
    Some(value) => value
    None => abort("eviction equal memo")
  }
  let debug = inc_query.debug()
  let passed = fresh_first is Ok(4) &&
    inc_first is Ok(4) &&
    fresh_second is Ok(4) &&
    inc_second is Ok(4) &&
    fresh_evict == Ok(false) &&
    fresh_store.revision() == fresh_revision &&
    inc_evict == Ok(true) &&
    duplicate == Ok(false) &&
    absent &&
    before_clocks == after_clocks &&
    first_memo.memo_id != second_memo.memo_id &&
    second_memo.memo_id == equal_memo.memo_id &&
    second_memo.verified_at == after_clocks.1 &&
    second_memo.changed_at == after_clocks.1 &&
    inc_second == equal_read &&
    debug.memo_count == 1 &&
    debug.compute_count == 2 &&
    debug.cutoff_calls == 0 &&
    debug.eviction_attempts == 2 &&
    debug.evictions == 1 &&
    debug.eviction_noops == 1 &&
    debug.eviction_rejections == 0
  println(
    "eviction_view old=\{first_memo.memo_id.sequence()} new=\{second_memo.memo_id.sequence()} shared=\{second_memo.memo_id == equal_memo.memo_id} clocks=\{before_clocks == after_clocks} passed=\{passed}",
  )
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///|
/// Downstream verification rematerializes an evicted child and loses proof.
fn eviction_downstream_proof_loss() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_input = must_fresh_source(fresh_region.source(2))
  let fresh_unrelated = must_fresh_source(fresh_region.source(100))
  let fresh_child = must_fresh_query(
    fresh_region.query_eq((ctx, _ : Unit) => {
      match ctx.read(fresh_input.view()) {
        Ok(value) => Ok(value % 2)
        Err(error) => Err(error)
      }
    }),
  )
  let fresh_parent = must_fresh_query(
    fresh_region.query_always_changed((ctx, _ : Unit) => {
      ctx.read(fresh_child.at(()))
    }),
  )
  let fresh_values = [must_fresh_read(fresh_store.read(fresh_parent.at(())))]
  ignore(fresh_child.evict_memo(()))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_parent.at(()))))
  ignore(fresh_store.transaction(tx => tx.set(fresh_unrelated, 101)))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_parent.at(()))))
  ignore(fresh_store.transaction(tx => tx.set(fresh_input, 4)))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_parent.at(()))))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_input = must_inc_source(inc_region.source(2))
  let inc_unrelated = must_inc_source(inc_region.source(100))
  let inc_child = must_inc_query(
    inc_region.query_eq((ctx, _ : Unit) => {
      match ctx.read(inc_input.view()) {
        Ok(value) => Ok(value % 2)
        Err(error) => Err(error)
      }
    }),
  )
  let inc_parent = must_inc_query(
    inc_region.query_always_changed((ctx, _ : Unit) => {
      ctx.read(inc_child.at(()))
    }),
  )
  let inc_values = [must_inc_read(inc_store.read(inc_parent.at(())))]
  let first_memo = match inc_child.memo_debug(()) {
    Some(value) => value
    None => abort("proof first memo")
  }
  let clocks = (inc_store.revision(), inc_store.change_epoch())
  let removed = inc_child.evict_memo(()) == Ok(true)
  inc_values.push(must_inc_read(inc_store.read(inc_parent.at(()))))
  let same_epoch_cache = inc_child.memo_debug(()) is None &&
    inc_parent.debug().compute_count == 1 &&
    (inc_store.revision(), inc_store.change_epoch()) == clocks
  ignore(inc_store.transaction(tx => tx.set(inc_unrelated, 101)))
  inc_values.push(must_inc_read(inc_store.read(inc_parent.at(()))))
  let rematerialized = match inc_child.memo_debug(()) {
    Some(value) => value
    None => abort("proof rematerialized memo")
  }
  let proof_loss_recomputed = rematerialized.memo_id != first_memo.memo_id &&
    rematerialized.changed_at == inc_store.change_epoch() &&
    rematerialized.verified_at == inc_store.change_epoch() &&
    inc_child.debug().cutoff_calls == 0 &&
    inc_parent.debug().compute_count == 2
  ignore(inc_store.transaction(tx => tx.set(inc_input, 4)))
  inc_values.push(must_inc_read(inc_store.read(inc_parent.at(()))))
  let retained_equivalent = match inc_child.memo_debug(()) {
    Some(value) => value.changed_at == rematerialized.changed_at
    None => false
  }
  let passed = fresh_values == inc_values &&
    removed &&
    same_epoch_cache &&
    proof_loss_recomputed &&
    retained_equivalent &&
    inc_child.debug().cutoff_calls == 1 &&
    inc_parent.debug().compute_count == 2
  println(
    "eviction_proof_loss values=\{int_values(inc_values)} same_epoch_cache=\{same_epoch_cache} parent=\{inc_parent.debug().compute_count} cutoff=\{inc_child.debug().cutoff_calls} passed=\{passed}",
  )
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///|
/// Rematerialization constructs only the currently selected branch trace.
fn eviction_dynamic_trace() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_mode = must_fresh_source(fresh_region.source(0))
  let fresh_left = must_fresh_source(fresh_region.source(2))
  let fresh_right = must_fresh_source(fresh_region.source(4))
  let fresh_query = must_fresh_query(
    fresh_region.query_eq((ctx, _ : Unit) => {
      match ctx.read(fresh_mode.view()) {
        Err(error) => Err(error)
        Ok(mode) =>
          if mode == 0 {
            match ctx.read(fresh_left.view()) {
              Ok(value) => Ok(value % 2)
              Err(error) => Err(error)
            }
          } else {
            match ctx.read(fresh_right.view()) {
              Ok(value) => Ok(value % 2)
              Err(error) => Err(error)
            }
          }
      }
    }),
  )
  let fresh_values = [must_fresh_read(fresh_store.read(fresh_query.at(())))]
  ignore(fresh_query.evict_memo(()))
  ignore(fresh_store.transaction(tx => tx.set(fresh_mode, 1)))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_query.at(()))))
  ignore(fresh_store.transaction(tx => tx.set(fresh_left, 3)))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_query.at(()))))
  ignore(fresh_store.transaction(tx => tx.set(fresh_right, 5)))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_query.at(()))))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_mode = must_inc_source(inc_region.source(0))
  let inc_left = must_inc_source(inc_region.source(2))
  let inc_right = must_inc_source(inc_region.source(4))
  let inc_query = must_inc_query(
    inc_region.query_eq((ctx, _ : Unit) => {
      match ctx.read(inc_mode.view()) {
        Err(error) => Err(error)
        Ok(mode) =>
          if mode == 0 {
            match ctx.read(inc_left.view()) {
              Ok(value) => Ok(value % 2)
              Err(error) => Err(error)
            }
          } else {
            match ctx.read(inc_right.view()) {
              Ok(value) => Ok(value % 2)
              Err(error) => Err(error)
            }
          }
      }
    }),
  )
  let inc_values = [must_inc_read(inc_store.read(inc_query.at(())))]
  let first_memo = match inc_query.memo_debug(()) {
    Some(value) => value
    None => abort("dynamic evict first")
  }
  ignore(inc_query.evict_memo(()))
  ignore(inc_store.transaction(tx => tx.set(inc_mode, 1)))
  inc_values.push(must_inc_read(inc_store.read(inc_query.at(()))))
  let second_memo = match inc_query.memo_debug(()) {
    Some(value) => value
    None => abort("dynamic evict second")
  }
  let after_rematerialize = inc_query.debug()
  ignore(inc_store.transaction(tx => tx.set(inc_left, 3)))
  inc_values.push(must_inc_read(inc_store.read(inc_query.at(()))))
  let after_old_branch = inc_query.debug()
  ignore(inc_store.transaction(tx => tx.set(inc_right, 5)))
  inc_values.push(must_inc_read(inc_store.read(inc_query.at(()))))
  let passed = fresh_values == inc_values &&
    first_memo.memo_id != second_memo.memo_id &&
    second_memo.trace_length == 2 &&
    after_rematerialize.compute_count == 2 &&
    after_rematerialize.cutoff_calls == 0 &&
    after_old_branch.compute_count == after_rematerialize.compute_count &&
    inc_query.debug().compute_count == 3 &&
    inc_query.debug().cutoff_calls == 1
  println(
    "eviction_dynamic values=\{int_values(inc_values)} old_branch_green=\{after_old_branch.compute_count == after_rematerialize.compute_count} cutoff=\{inc_query.debug().cutoff_calls} passed=\{passed}",
  )
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///|
/// Fresh reference outcomes for eviction-specific failure and Cycle scripts.
fn eviction_failure_and_cycle_fresh() -> (Array[String], Array[String]) {
  let store = @fresh.Store()
  let region = must_fresh_region(store.region())
  let fail_mode = must_fresh_source(region.source(false))
  let fail_query = must_fresh_query(
    region.query_eq((ctx, _ : Unit) => {
      match ctx.read(fail_mode.view()) {
        Err(error) => Err(error)
        Ok(false) => Ok(7)
        Ok(true) =>
          Err(@fresh.ReadError::ClosedRegion(generation=region.generation()))
      }
    }),
  )
  let failures = [fresh_int(store.read(fail_query.at(())))]
  ignore(fail_query.evict_memo(()))
  ignore(store.transaction(tx => tx.set(fail_mode, true)))
  failures.push(fresh_int(store.read(fail_query.at(()))))
  ignore(store.transaction(tx => tx.set(fail_mode, false)))
  failures.push(fresh_int(store.read(fail_query.at(()))))

  let cycle_mode = must_fresh_source(region.source(false))
  let cycle_value = must_fresh_source(region.source(2))
  let cycle_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let cycle_query = must_fresh_query(
    region.query_eq((ctx, _ : Unit) => {
      match ctx.read(cycle_mode.view()) {
        Err(error) => Err(error)
        Ok(false) =>
          match ctx.read(cycle_value.view()) {
            Ok(value) => Ok(value % 2)
            Err(error) => Err(error)
          }
        Ok(true) =>
          match cycle_ref.val {
            Some(self) => ctx.read(self.at(()))
            None => Ok(-1)
          }
      }
    }),
  )
  cycle_ref.val = Some(cycle_query)
  let cycle_name = id => if id == cycle_query.id() { "Q" } else { "?" }
  let cycles = [
    normalize_fresh_cycle(store.read(cycle_query.at(())), cycle_name),
  ]
  ignore(cycle_query.evict_memo(()))
  ignore(store.transaction(tx => tx.set(cycle_mode, true)))
  cycles.push(normalize_fresh_cycle(store.read(cycle_query.at(())), cycle_name))
  ignore(
    store.transaction(tx => {
      ignore(tx.set(cycle_mode, false))
      tx.set(cycle_value, 4)
    }),
  )
  cycles.push(normalize_fresh_cycle(store.read(cycle_query.at(())), cycle_name))
  ignore(region.close())
  (failures, cycles)
}

///|
/// Failed and cyclic rematerialization install no memo and never return stale data.
fn eviction_failure_and_cycle() -> Bool {
  let fresh = eviction_failure_and_cycle_fresh()
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let fail_mode = must_inc_source(region.source(false))
  let fail_query = must_inc_query(
    region.query_eq((ctx, _ : Unit) => {
      match ctx.read(fail_mode.view()) {
        Err(error) => Err(error)
        Ok(false) => Ok(7)
        Ok(true) =>
          Err(
            @incremental.ReadError::ClosedRegion(generation=region.generation()),
          )
      }
    }),
  )
  let first = store.read(fail_query.at(()))
  let first_memo = match fail_query.memo_debug(()) {
    Some(value) => value
    None => abort("evict failure first")
  }
  ignore(fail_query.evict_memo(()))
  ignore(store.transaction(tx => tx.set(fail_mode, true)))
  let failed = store.read(fail_query.at(()))
  let failed_clean = failed is Err(@incremental.ReadError::ClosedRegion(_)) &&
    fail_query.debug().memo_count == 0 &&
    fail_query.debug().cutoff_calls == 0
  ignore(store.transaction(tx => tx.set(fail_mode, false)))
  let recovered = store.read(fail_query.at(()))
  let recovered_memo = match fail_query.memo_debug(()) {
    Some(value) => value
    None => abort("evict failure recovered")
  }

  let cycle_mode = must_inc_source(region.source(false))
  let cycle_value = must_inc_source(region.source(2))
  let cycle_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let cycle_query = must_inc_query(
    region.query_eq((ctx, _ : Unit) => {
      match ctx.read(cycle_mode.view()) {
        Err(error) => Err(error)
        Ok(false) =>
          match ctx.read(cycle_value.view()) {
            Ok(value) => Ok(value % 2)
            Err(error) => Err(error)
          }
        Ok(true) =>
          match cycle_ref.val {
            Some(self) => ctx.read(self.at(()))
            None => Ok(-1)
          }
      }
    }),
  )
  cycle_ref.val = Some(cycle_query)
  let cycle_first = store.read(cycle_query.at(()))
  let cycle_first_memo = match cycle_query.memo_debug(()) {
    Some(value) => value
    None => abort("evict cycle first")
  }
  ignore(cycle_query.evict_memo(()))
  ignore(store.transaction(tx => tx.set(cycle_mode, true)))
  let cycled = store.read(cycle_query.at(()))
  let cycle_clean = cycled is Err(@incremental.ReadError::Cycle(_)) &&
    cycle_query.debug().memo_count == 0 &&
    cycle_query.debug().active_count == 0 &&
    cycle_query.debug().cutoff_calls == 0 &&
    store.debug().last_finished_active_depth == 0
  ignore(
    store.transaction(tx => {
      ignore(tx.set(cycle_mode, false))
      tx.set(cycle_value, 4)
    }),
  )
  let cycle_recovered = store.read(cycle_query.at(()))
  let cycle_recovered_memo = match cycle_query.memo_debug(()) {
    Some(value) => value
    None => abort("evict cycle recovered")
  }
  let incremental_failures = [
    inc_int(first),
    inc_int(failed),
    inc_int(recovered),
  ]
  let cycle_name = id => if id == cycle_query.id() { "Q" } else { "?" }
  let incremental_cycles = [
    normalize_incremental_cycle(cycle_first, cycle_name),
    normalize_incremental_cycle(cycled, cycle_name),
    normalize_incremental_cycle(cycle_recovered, cycle_name),
  ]
  let passed = fresh.0 == incremental_failures &&
    fresh.1 == incremental_cycles &&
    first == Ok(7) &&
    failed_clean &&
    recovered == Ok(7) &&
    first_memo.memo_id != recovered_memo.memo_id &&
    fail_query.debug().cutoff_calls == 0 &&
    cycle_first == Ok(0) &&
    cycle_clean &&
    cycle_recovered == Ok(0) &&
    cycle_first_memo.memo_id != cycle_recovered_memo.memo_id &&
    cycle_query.debug().cutoff_calls == 0
  println(
    "eviction_errors exact=\{fresh.0 == incremental_failures && fresh.1 == incremental_cycles} failure_new=\{first_memo.memo_id != recovered_memo.memo_id} cycle_new=\{cycle_first_memo.memo_id != cycle_recovered_memo.memo_id} clean=\{failed_clean && cycle_clean} passed=\{passed}",
  )
  ignore(region.close())
  passed
}

///|
/// Removing one typed key leaves every other memo incarnation untouched.
fn eviction_per_key_isolation() -> Bool {
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let query = must_inc_query(
    region.query_eq((_ctx, key : String) => Ok(key.length())),
  )
  let a_view = query.at("a")
  let b_view = query.at("bb")
  let a_first = store.read(a_view)
  let b_first = store.read(b_view)
  let a_memo = match query.memo_debug("a") {
    Some(value) => value
    None => abort("key a")
  }
  let b_memo = match query.memo_debug("bb") {
    Some(value) => value
    None => abort("key b")
  }
  let removed = query.evict_memo("a") == Ok(true)
  let b_again = store.read(b_view)
  let b_after = match query.memo_debug("bb") {
    Some(value) => value
    None => abort("key b after")
  }
  let a_again = store.read(a_view)
  let a_after = match query.memo_debug("a") {
    Some(value) => value
    None => abort("key a after")
  }
  let passed = a_first == Ok(1) &&
    b_first == Ok(2) &&
    removed &&
    b_again == Ok(2) &&
    b_after.memo_id == b_memo.memo_id &&
    a_again == Ok(1) &&
    a_after.memo_id != a_memo.memo_id &&
    query.debug().memo_count == 2 &&
    query.debug().compute_count == 3
  println(
    "eviction_per_key a_new=\{a_after.memo_id != a_memo.memo_id} b_same=\{b_after.memo_id == b_memo.memo_id} memos=\{query.debug().memo_count} passed=\{passed}",
  )
  ignore(region.close())
  passed
}

///|
/// Fresh validates the same phase/lifetime boundary around its semantic no-op.
fn fresh_eviction_phase_rejection() -> Bool {
  let store = @fresh.Store()
  let target_region = must_fresh_region(store.region())
  let trigger_region = must_fresh_region(store.region())
  let key_calls = Ref(0)
  let key = HostileEvictionKey::{ calls: key_calls }
  let target = must_fresh_query(
    target_region.query_eq((_ctx, _ : HostileEvictionKey) => Ok(9)),
  )
  let during_eval : Ref[Result[Bool, @fresh.EvictionError]?] = Ref(None)
  let trigger = must_fresh_query(
    trigger_region.query_always_changed((_ctx, _ : Unit) => {
      during_eval.val = Some(target.evict_memo(key))
      Ok(1)
    }),
  )
  let revision = store.revision()
  ignore(store.read(trigger.at(())))
  let eval_rejected = during_eval.val
    is Some(Err(@fresh.EvictionError::EvictionDuringEvaluation(_))) &&
    store.revision() == revision
  let during_tx : Ref[Result[Bool, @fresh.EvictionError]?] = Ref(None)
  let tx_result = store.transaction(_tx => {
    during_tx.val = Some(target.evict_memo(key))
    Ok(())
  })
  let tx_rejected = during_tx.val
    is Some(Err(@fresh.EvictionError::EvictionDuringTransaction(_))) &&
    tx_result is Ok(outcome) &&
    !outcome.advanced &&
    store.revision() == revision
  ignore(target_region.close())
  let closed_revision = store.revision()
  let closed_rejected = target.evict_memo(key)
    is Err(@fresh.EvictionError::ClosedRegion(_)) &&
    store.revision() == closed_revision &&
    key_calls.val == 0
  let debug = target.debug()
  let passed = eval_rejected &&
    tx_rejected &&
    closed_rejected &&
    debug.eviction_attempts == 3 &&
    debug.eviction_rejections == 3 &&
    debug.evictions == 0 &&
    debug.eviction_noops == 0
  ignore(trigger_region.close())
  passed
}

///|
/// Evaluation, transaction, and closed-Region operations are rejected atomically.
fn eviction_phase_rejection() -> Bool {
  let store = @incremental.Store()
  let target_region = must_inc_region(store.region())
  let trigger_region = must_inc_region(store.region())
  let target = must_inc_query(target_region.query_eq((_ctx, _ : Unit) => Ok(9)))
  ignore(store.read(target.at(())))
  let target_before = match target.memo_debug(()) {
    Some(value) => value
    None => abort("phase target")
  }
  let during_eval : Ref[Result[Bool, @incremental.EvictionError]?] = Ref(None)
  let trigger = must_inc_query(
    trigger_region.query_always_changed((_ctx, _ : Unit) => {
      during_eval.val = Some(target.evict_memo(()))
      Ok(1)
    }),
  )
  let clocks_before_eval = (store.revision(), store.change_epoch())
  ignore(store.read(trigger.at(())))
  let eval_rejected = during_eval.val
    is Some(Err(@incremental.EvictionError::EvictionDuringEvaluation(_))) &&
    (store.revision(), store.change_epoch()) == clocks_before_eval
  let after_eval = match target.memo_debug(()) {
    Some(value) => value
    None => abort("phase after eval")
  }

  let during_tx : Ref[Result[Bool, @incremental.EvictionError]?] = Ref(None)
  let clocks_before_tx = (store.revision(), store.change_epoch())
  let tx_result = store.transaction(_tx => {
    during_tx.val = Some(target.evict_memo(()))
    Ok(())
  })
  let tx_rejected = during_tx.val
    is Some(Err(@incremental.EvictionError::EvictionDuringTransaction(_))) &&
    tx_result is Ok(outcome) &&
    !outcome.advanced &&
    (store.revision(), store.change_epoch()) == clocks_before_tx
  let after_tx = match target.memo_debug(()) {
    Some(value) => value
    None => abort("phase after tx")
  }
  ignore(target_region.close())
  let clocks_after_close = (store.revision(), store.change_epoch())
  let closed = target.evict_memo(())
  let closed_rejected = closed
    is Err(@incremental.EvictionError::ClosedRegion(_)) &&
    (store.revision(), store.change_epoch()) == clocks_after_close
  let debug = target.debug()
  let fresh_passed = fresh_eviction_phase_rejection()
  let passed = fresh_passed &&
    eval_rejected &&
    tx_rejected &&
    closed_rejected &&
    same_memo(target_before, after_eval) &&
    same_memo(target_before, after_tx) &&
    debug.eviction_attempts == 3 &&
    debug.eviction_rejections == 3 &&
    debug.evictions == 0 &&
    debug.eviction_noops == 0
  println(
    "eviction_phase fresh=\{fresh_passed} eval=\{eval_rejected} tx=\{tx_rejected} closed=\{closed_rejected} clocks=true passed=\{passed}",
  )
  ignore(trigger_region.close())
  passed
}

///|
/// Runs explicit eviction and conservative rematerialization evidence.
fn run_eviction_scenarios() -> Bool {
  let view = eviction_view_rematerialization()
  let proof_loss = eviction_downstream_proof_loss()
  let dynamic = eviction_dynamic_trace()
  let errors = eviction_failure_and_cycle()
  let per_key = eviction_per_key_isolation()
  let phase = eviction_phase_rejection()
  let passed = view && proof_loss && dynamic && errors && per_key && phase
  println(
    "eviction_state view=\{view} proof_loss=\{proof_loss} dynamic=\{dynamic} errors=\{errors} per_key=\{per_key} phase=\{phase}",
  )
  passed
}
