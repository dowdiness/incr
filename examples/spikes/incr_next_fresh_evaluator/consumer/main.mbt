///|
/// Mutable key used to demonstrate semantic invocation drift without memoization.
struct MutableInvocationKey {
  value : Ref[Int]
}

///|
/// Mutable payload used to demonstrate revision-bypassing alias mutation.
struct MutablePayload {
  value : Ref[Int]
}

///|
/// Returns a Region or aborts the evidence executable.
fn must_region(
  result : Result[@provider.Region, @provider.RegionError],
) -> @provider.Region {
  match result {
    Ok(region) => region
    Err(_) => abort("expected Region creation")
  }
}

///|
/// Returns a Source or aborts the evidence executable.
fn[T] must_source(
  result : Result[@provider.Source[T], @provider.RegionError],
) -> @provider.Source[T] {
  match result {
    Ok(source) => source
    Err(_) => abort("expected Source creation")
  }
}

///|
/// Returns a Query or aborts the evidence executable.
fn[K, V] must_query(
  result : Result[@provider.Query[K, V], @provider.RegionError],
) -> @provider.Query[K, V] {
  match result {
    Ok(query) => query
    Err(_) => abort("expected Query creation")
  }
}

///|
/// Lifts one structural read through an Int transformation.
fn map_int(
  result : Result[Int, @provider.ReadError],
  transform : (Int) -> Int,
) -> Result[Int, @provider.ReadError] {
  match result {
    Ok(value) => Ok(transform(value))
    Err(error) => Err(error)
  }
}

///|
/// Formats Int-valued root reads without a Show requirement on ReadError.
fn int_read_text(result : Result[Int, @provider.ReadError]) -> String {
  match result {
    Ok(value) => "Ok(\{value})"
    Err(@provider.ReadError::CrossStore(_)) => "Err(CrossStore)"
    Err(@provider.ReadError::ClosedRegion(_)) => "Err(ClosedRegion)"
    Err(@provider.ReadError::ExpiredEvalContext(_)) => "Err(ExpiredEvalContext)"
    Err(@provider.ReadError::ReentrantRootRead(_)) => "Err(ReentrantRootRead)"
    Err(@provider.ReadError::ReadDuringTransaction(_)) =>
      "Err(ReadDuringTransaction)"
  }
}

///|
/// Source, Unit Formula, keyed Query, chain, and repeated fresh evaluation.
fn scenario_fresh_queries() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let source = must_source(region.source(2))
  let source_view = source.view()
  let doubled = must_query(
    region.query((ctx, _unit : Unit) => {
      map_int(ctx.read(source_view), value => value * 2)
    }),
  )
  let plus_one = must_query(
    region.query((ctx, _unit : Unit) => {
      map_int(ctx.read(doubled.at(())), value => value + 1)
    }),
  )
  let keyed = must_query(region.query((_ctx, key : String) => Ok(key.length())))
  let direct = store.read(source_view)
  let first = store.read(plus_one.at(()))
  let second = store.read(plus_one.at(()))
  let keyed_value = store.read(keyed.at("abcd"))
  let source_state = source.debug()
  let doubled_state = doubled.debug()
  let plus_one_state = plus_one.debug()
  let passed = source.view().handle_id() == source_view.handle_id() &&
    direct == Ok(2) &&
    first == Ok(5) &&
    second == Ok(5) &&
    keyed_value == Ok(4) &&
    source_state.read_count == 3 &&
    doubled_state.compute_count == 2 &&
    plus_one_state.compute_count == 2 &&
    store.revision().value() == 0
  println("scenario=fresh_queries")
  println(
    "  direct=\{int_read_text(direct)} chain_reads=[\{int_read_text(first)},\{int_read_text(second)}] keyed=\{int_read_text(keyed_value)}",
  )
  println(
    "  counts source=\{source_state.read_count} doubled=\{doubled_state.compute_count} plus_one=\{plus_one_state.compute_count} revision=\{store.revision().value()} stable_source_view=\{source.view().handle_id() == source_view.handle_id()}",
  )
  println("  passed=\{passed}")
  ignore(region.close())
  passed
}

///|
/// A diamond intentionally evaluates the shared Query twice without a memo.
fn scenario_diamond_no_memo() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let source = must_source(region.source(1))
  let shared = must_query(
    region.query((ctx, _unit : Unit) => ctx.read(source.view())),
  )
  let left = must_query(
    region.query((ctx, _unit : Unit) => {
      map_int(ctx.read(shared.at(())), value => value + 1)
    }),
  )
  let right = must_query(
    region.query((ctx, _unit : Unit) => {
      map_int(ctx.read(shared.at(())), value => value + 2)
    }),
  )
  let root = must_query(
    region.query((ctx, _unit : Unit) => {
      match (ctx.read(left.at(())), ctx.read(right.at(()))) {
        (Ok(a), Ok(b)) => Ok(a + b)
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    }),
  )
  let result = store.read(root.at(()))
  let passed = result == Ok(5) &&
    shared.debug().compute_count == 2 &&
    source.debug().read_count == 2 &&
    left.debug().compute_count == 1 &&
    right.debug().compute_count == 1
  println(
    "scenario=diamond_no_memo result=\{int_read_text(result)} shared_runs=\{shared.debug().compute_count} source_reads=\{source.debug().read_count} passed=\{passed}",
  )
  ignore(region.close())
  passed
}

///|
/// Dynamic branches read only the selected Source in each fresh evaluation.
fn scenario_dynamic_branch() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let mode = must_source(region.source(true))
  let left = must_source(region.source(10))
  let right = must_source(region.source(20))
  let choose = must_query(
    region.query((ctx, _unit : Unit) => {
      match ctx.read(mode.view()) {
        Err(error) => Err(error)
        Ok(true) => ctx.read(left.view())
        Ok(false) => ctx.read(right.view())
      }
    }),
  )
  let first = store.read(choose.at(()))
  let update = store.transaction(tx => {
    match tx.set(mode, false) {
      Ok(_) => Ok(())
      Err(error) => Err(error)
    }
  })
  let second = store.read(choose.at(()))
  let passed = first == Ok(10) &&
    second == Ok(20) &&
    update is Ok(_) &&
    left.debug().read_count == 1 &&
    right.debug().read_count == 1 &&
    mode.debug().read_count == 2
  println(
    "scenario=dynamic_branch values=[\{int_read_text(first)},\{int_read_text(second)}] reads=mode:\{mode.debug().read_count},left:\{left.debug().read_count},right:\{right.debug().read_count} passed=\{passed}",
  )
  ignore(region.close())
  passed
}

///|
/// One root captures one Revision and domain errors remain inside V.
fn scenario_revision_and_domain_error() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let a = must_source(region.source(1))
  let b = must_source(region.source(2))
  let snapshot = must_query(
    region.query((ctx, _unit : Unit) => {
      let before = ctx.revision().value()
      match (ctx.read(a.view()), ctx.read(b.view())) {
        (Ok(av), Ok(bv)) => Ok((before, av, bv, ctx.revision().value()))
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    }),
  )
  let domain = must_query(
    region.query((_ctx, _unit : Unit) => {
      let domain_value : Result[Int, String] = Err("domain failure")
      Ok(domain_value)
    }),
  )
  let observed = store.read(snapshot.at(()))
  let domain_result = store.read(domain.at(()))
  let passed = observed == Ok((0, 1, 2, 0)) &&
    domain_result == Ok(Err("domain failure")) &&
    store.revision().value() == 0
  println(
    "scenario=revision_and_domain_error snapshot_ok=\{observed == Ok((0, 1, 2, 0))} domain_error_is_value=\{domain_result == Ok(Err("domain failure"))} revision=\{store.revision().value()} passed=\{passed}",
  )
  ignore(region.close())
  passed
}

///|
/// Multi-Source commit is atomic because root reads are rejected during staging.
fn scenario_atomic_transaction() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let a = must_source(region.source(1))
  let b = must_source(region.source(2))
  let root = must_query(
    region.query((ctx, _unit : Unit) => {
      match (ctx.read(a.view()), ctx.read(b.view())) {
        (Ok(av), Ok(bv)) => Ok((av, bv, ctx.revision().value()))
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    }),
  )
  let blocked = Ref(false)
  let outcome = store.transaction(tx => {
    match tx.set(a, 10) {
      Err(error) => Err(error)
      Ok(_) => {
        blocked.val = store.read(root.at(()))
          is Err(@provider.ReadError::ReadDuringTransaction(_))
        match tx.set(b, 20) {
          Ok(_) => Ok(())
          Err(error) => Err(error)
        }
      }
    }
  })
  let after = store.read(root.at(()))
  let outcome_ok = match outcome {
    Ok(value) =>
      value.advanced &&
      value.staged_count == 2 &&
      value.applied_count == 2 &&
      value.revision.value() == 1
    Err(_) => false
  }
  let passed = blocked.val && outcome_ok && after == Ok((10, 20, 1))
  println(
    "scenario=atomic_transaction blocked_intermediate=\{blocked.val} outcome_ok=\{outcome_ok} after_ok=\{after == Ok((10, 20, 1))} revision=\{store.revision().value()} passed=\{passed}",
  )
  ignore(region.close())
  passed
}

///|
/// Callback failure and ignored invalid write both roll back every staged write.
fn scenario_rollbacks_and_poison() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let value = must_source(region.source(5))
  let rollback = store.transaction(tx => {
    ignore(tx.set(value, 9))
    Err(@provider.TransactionError::CallbackRejected)
  })
  let after_callback = store.read(value.view())

  let other_store = @provider.Store()
  let other_region = must_region(other_store.region())
  let other = must_source(other_region.source(77))
  let staged_before_invalid = Ref(0)
  let staged_after_invalid = Ref(0)
  let poison_seen = Ref(false)
  let poisoned = store.transaction(tx => {
    ignore(tx.set(value, 11))
    staged_before_invalid.val = tx.staged_count()
    ignore(tx.set(other, 88))
    staged_after_invalid.val = tx.staged_count()
    poison_seen.val = tx.is_poisoned()
    Ok(())
  })
  let after_poison = store.read(value.view())
  let callback_rolled_back = rollback
    is Err(@provider.TransactionError::CallbackRejected)
  let passed = callback_rolled_back &&
    after_callback == Ok(5) &&
    poisoned is Err(@provider.TransactionError::CrossStore(_)) &&
    after_poison == Ok(5) &&
    staged_before_invalid.val == 1 &&
    staged_after_invalid.val == 1 &&
    poison_seen.val &&
    store.revision().value() == 0
  println(
    "scenario=rollbacks_and_poison callback_value=\{int_read_text(after_callback)} poisoned_value=\{int_read_text(after_poison)} staged=\{staged_before_invalid.val}->\{staged_after_invalid.val} poison_seen=\{poison_seen.val} revision=\{store.revision().value()} passed=\{passed}",
  )
  ignore(region.close())
  ignore(other_region.close())
  passed
}

///|
/// Last-write-wins, equal commits advance, empty commits do not, Tx expires.
fn scenario_transaction_edges() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let source = must_source(region.source(1))
  let captured : Ref[@provider.Transaction?] = Ref(None)
  let last_write = store.transaction(tx => {
    captured.val = Some(tx)
    ignore(tx.set(source, 2))
    ignore(tx.set(source, 3))
    Ok(())
  })
  let after_last = store.read(source.view())
  let equal_commit = store.transaction(tx => {
    ignore(tx.set(source, 3))
    Ok(())
  })
  let empty = store.transaction(_tx => Ok(()))
  let expired = match captured.val {
    Some(tx) => tx.set(source, 4)
    None => Ok(())
  }
  let last_ok = match last_write {
    Ok(outcome) => outcome.staged_count == 1 && outcome.revision.value() == 1
    Err(_) => false
  }
  let equal_ok = match equal_commit {
    Ok(outcome) => outcome.advanced && outcome.revision.value() == 2
    Err(_) => false
  }
  let empty_ok = match empty {
    Ok(outcome) => !outcome.advanced && outcome.revision.value() == 2
    Err(_) => false
  }
  let passed = last_ok &&
    equal_ok &&
    empty_ok &&
    after_last == Ok(3) &&
    expired is Err(@provider.TransactionError::ExpiredTransaction(_)) &&
    store.revision().value() == 2
  println(
    "scenario=transaction_edges value=\{int_read_text(after_last)} revisions=1,2,2 expired=\{expired is Err(@provider.TransactionError::ExpiredTransaction(_))} passed=\{passed}",
  )
  ignore(region.close())
  passed
}

///|
/// Global guards reject capability re-entry across same and different Stores.
fn scenario_execution_boundaries() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let source = must_source(region.source(1))
  let other_store = @provider.Store()
  let other_region = must_region(other_store.region())
  let other_source = must_source(other_region.source(2))
  let escaped_ctx : Ref[@provider.EvalCtx?] = Ref(None)
  let boundary_query = must_query(
    region.query((ctx, _unit : Unit) => {
      escaped_ctx.val = Some(ctx)
      let same_read = store.read(source.view())
        is Err(@provider.ReadError::ReentrantRootRead(_))
      let other_read = other_store.read(other_source.view())
        is Err(@provider.ReadError::ReentrantRootRead(_))
      let same_tx = store.transaction(_ => Ok(()))
        is Err(@provider.TransactionError::TransactionDuringEvaluation(_))
      let other_tx = other_store.transaction(_ => Ok(()))
        is Err(@provider.TransactionError::TransactionDuringEvaluation(_))
      let source_rejected = region.source(3)
        is Err(@provider.RegionError::MutationDuringEvaluation(_))
      let query_rejected = region.query((_nested, _key : Unit) => Ok(0))
        is Err(@provider.RegionError::MutationDuringEvaluation(_))
      let close_rejected = region.close()
        is Err(@provider.RegionError::MutationDuringEvaluation(_))
      Ok(
        (
          same_read, other_read, same_tx, other_tx, source_rejected, query_rejected,
          close_rejected,
        ),
      )
    }),
  )
  let observed = store.read(boundary_query.at(()))
  let expired = match escaped_ctx.val {
    Some(ctx) => ctx.read(source.view())
    None => Ok(0)
  }
  let tx_region_rejections = Ref((false, false, false))
  let transaction = store.transaction(_tx => {
    tx_region_rejections.val = (
      region.source(4)
      is Err(@provider.RegionError::MutationDuringTransaction(_)),
      region.query((_ctx, _key : Unit) => Ok(0))
      is Err(@provider.RegionError::MutationDuringTransaction(_)),
      region.close() is Err(@provider.RegionError::MutationDuringTransaction(_)),
    )
    Ok(())
  })
  let all_eval_rejected = match observed {
    Ok((a, b, c, d, e, f, g)) => a && b && c && d && e && f && g
    Err(_) => false
  }
  let passed = all_eval_rejected &&
    expired is Err(@provider.ReadError::ExpiredEvalContext(_)) &&
    tx_region_rejections.val == (true, true, true) &&
    transaction is Ok(_)
  println(
    "scenario=execution_boundaries eval_rejections=\{all_eval_rejected} expired_ctx=\{expired is Err(@provider.ReadError::ExpiredEvalContext(_))} tx_region_rejections=\{tx_region_rejections.val == (true, true, true)} passed=\{passed}",
  )
  ignore(region.close())
  ignore(other_region.close())
  passed
}

///|
/// CrossStore root validation and Region close happen before recipe execution.
fn scenario_metadata_and_close() -> Bool {
  let left = @provider.Store()
  let left_region = must_region(left.region())
  let right = @provider.Store()
  let right_region = must_region(right.region())
  let compute_runs = Ref(0)
  let query = must_query(
    left_region.query((_ctx, key : Int) => {
      compute_runs.val = compute_runs.val + 1
      Ok(key)
    }),
  )
  let query_view = query.at(5)
  let cross = right.read(query_view)
  let source = must_source(left_region.source(9))
  let source_view = source.view()
  let before_source = left.read(source_view)
  ignore(left_region.close())
  let closed_source = left.read(source_view)
  let closed_query = left.read(query_view)
  let passed = cross is Err(@provider.ReadError::CrossStore(_)) &&
    compute_runs.val == 0 &&
    before_source == Ok(9) &&
    closed_source is Err(@provider.ReadError::ClosedRegion(_)) &&
    closed_query is Err(@provider.ReadError::ClosedRegion(_)) &&
    !source.debug().committed &&
    !query.debug().compute_available
  println(
    "scenario=metadata_and_close cross_before_recipe=\{cross is Err(@provider.ReadError::CrossStore(_)) && compute_runs.val == 0} source_before=\{int_read_text(before_source)} closed_source=\{int_read_text(closed_source)} closed_query=\{int_read_text(closed_query)} payload_cleared=\{!source.debug().committed} compute_cleared=\{!query.debug().compute_available} passed=\{passed}",
  )
  ignore(right_region.close())
  passed
}

///|
/// Documents caller-owned semantic immutability contracts by counterexample.
fn scenario_caller_contracts() -> Bool {
  let store = @provider.Store()
  let region = must_region(store.region())
  let mutable_key = MutableInvocationKey::{ value: Ref(1) }
  let keyed = must_query(
    region.query((_ctx, key : MutableInvocationKey) => Ok(key.value.val)),
  )
  let same_view = keyed.at(mutable_key)
  let key_before = store.read(same_view)
  mutable_key.value.val = 2
  let key_after = store.read(same_view)

  let payload = MutablePayload::{ value: Ref(10) }
  let source = must_source(region.source(payload))
  let projected = must_query(
    region.query((ctx, _unit : Unit) => {
      match ctx.read(source.view()) {
        Ok(value) => Ok(value.value.val)
        Err(error) => Err(error)
      }
    }),
  )
  let revision_before = store.revision()
  let payload_before = store.read(projected.at(()))
  payload.value.val = 11
  let payload_after = store.read(projected.at(()))
  let revision_after = store.revision()
  let key_drift = key_before == Ok(1) && key_after == Ok(2)
  let payload_drift = payload_before == Ok(10) &&
    payload_after == Ok(11) &&
    revision_before == revision_after
  let passed = key_drift && payload_drift
  println(
    "scenario=caller_contracts same_view_key=\{int_read_text(key_before)}->\{int_read_text(key_after)} mutable_payload=\{int_read_text(payload_before)}->\{int_read_text(payload_after)} revision=\{revision_before.value()}->\{revision_after.value()} outside_contract_observed=\{passed}",
  )
  ignore(region.close())
  passed
}

///|
/// Runs the complete target-independent reference-semantics evidence.
fn main {
  println("INCR NEXT — FRESH EVALUATOR AND ATOMIC TRANSACTION ORACLE")
  let fresh = scenario_fresh_queries()
  let diamond = scenario_diamond_no_memo()
  let dynamic = scenario_dynamic_branch()
  let revision = scenario_revision_and_domain_error()
  let transaction_atomic = scenario_atomic_transaction()
  let rollback = scenario_rollbacks_and_poison()
  let transaction_edges = scenario_transaction_edges()
  let boundaries = scenario_execution_boundaries()
  let metadata = scenario_metadata_and_close()
  let contracts = scenario_caller_contracts()
  let passed = fresh &&
    diamond &&
    dynamic &&
    revision &&
    transaction_atomic &&
    rollback &&
    transaction_edges &&
    boundaries &&
    metadata &&
    contracts
  println(
    "full_state fresh=\{fresh} diamond=\{diamond} dynamic=\{dynamic} revision=\{revision} transaction_atomic=\{transaction_atomic} rollback=\{rollback} transaction_edges=\{transaction_edges} boundaries=\{boundaries} metadata=\{metadata} contracts=\{contracts}",
  )
  println("constrained verdict: \{if passed { "PASS" } else { "FAIL" }}")
  if !passed {
    abort("fresh evaluator evidence failed")
  }
}
