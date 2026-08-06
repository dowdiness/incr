///| Normalized observations intentionally omit runtime identities and counters.
struct ScriptResult {
  reads : Array[String]
  operation_results : Array[String]
  final_revision : Int
}

///| Normalized rejected/lifecycle operations and their public Revisions.
struct EdgeResult {
  operations : Array[String]
  revisions : Array[Int]
}

///| Deliberately mutable value used only for an excluded caller-contract probe.
struct MutablePayload {
  value : Ref[Int]
}

///| Deliberately mutable cached result used only for the same excluded probe.
struct MutableResult {
  value : Ref[Int]
}

///|
fn must_fresh_region(result : Result[@fresh.Region, @fresh.RegionError]) -> @fresh.Region {
  match result { Ok(value) => value; Err(_) => abort("fresh region") }
}

///|
fn must_inc_region(result : Result[@incremental.Region, @incremental.RegionError]) -> @incremental.Region {
  match result { Ok(value) => value; Err(_) => abort("incremental region") }
}

///|
fn[T] must_fresh_source(result : Result[@fresh.Source[T], @fresh.RegionError]) -> @fresh.Source[T] {
  match result { Ok(value) => value; Err(_) => abort("fresh source") }
}

///|
fn[T] must_inc_source(result : Result[@incremental.Source[T], @incremental.RegionError]) -> @incremental.Source[T] {
  match result { Ok(value) => value; Err(_) => abort("incremental source") }
}

///|
fn[K, V] must_fresh_query(result : Result[@fresh.Query[K, V], @fresh.RegionError]) -> @fresh.Query[K, V] {
  match result { Ok(value) => value; Err(_) => abort("fresh query") }
}

///|
fn[K, V] must_inc_query(result : Result[@incremental.Query[K, V], @incremental.RegionError]) -> @incremental.Query[K, V] {
  match result { Ok(value) => value; Err(_) => abort("incremental query") }
}

///|
fn fresh_int(result : Result[Int, @fresh.ReadError]) -> String {
  match result {
    Ok(value) => "Ok(\{value})"
    Err(@fresh.ReadError::CrossStore(_)) => "Err(CrossStore)"
    Err(@fresh.ReadError::ClosedRegion(_)) => "Err(ClosedRegion)"
    Err(@fresh.ReadError::ExpiredEvalContext(_)) => "Err(ExpiredEvalContext)"
    Err(@fresh.ReadError::ReentrantRootRead(_)) => "Err(ReentrantRootRead)"
    Err(@fresh.ReadError::ReadDuringTransaction(_)) => "Err(ReadDuringTransaction)"
  }
}

///|
fn inc_int(result : Result[Int, @incremental.ReadError]) -> String {
  match result {
    Ok(value) => "Ok(\{value})"
    Err(@incremental.ReadError::CrossStore(_)) => "Err(CrossStore)"
    Err(@incremental.ReadError::ClosedRegion(_)) => "Err(ClosedRegion)"
    Err(@incremental.ReadError::ExpiredEvalContext(_)) => "Err(ExpiredEvalContext)"
    Err(@incremental.ReadError::ReentrantRootRead(_)) => "Err(ReentrantRootRead)"
    Err(@incremental.ReadError::ReadDuringTransaction(_)) => "Err(ReadDuringTransaction)"
  }
}

///|
fn observe_fresh(reads : Array[String], store : @fresh.Store, result : Result[Int, @fresh.ReadError]) -> Unit {
  reads.push("\{fresh_int(result)}@r\{store.revision().value()}")
}

///|
fn observe_inc(reads : Array[String], store : @incremental.Store, result : Result[Int, @incremental.ReadError]) -> Unit {
  reads.push("\{inc_int(result)}@r\{store.revision().value()}")
}

///| Same operation/read script as basic_incremental_script.
fn basic_fresh_script() -> ScriptResult {
  let reads : Array[String] = []
  let operations : Array[String] = []
  let store = @fresh.Store()
  let region = must_fresh_region(store.region())
  let left = must_fresh_source(region.source(1))
  let right = must_fresh_source(region.source(2))
  let unrelated = must_fresh_source(region.source(100))
  let sum = must_fresh_query(region.query((ctx, _ : Unit) => {
    match (ctx.read(left.view()), ctx.read(right.view())) {
      (Ok(a), Ok(b)) => Ok(a + b)
      (Err(error), _) => Err(error)
      (_, Err(error)) => Err(error)
    }
  }))
  observe_fresh(reads, store, store.read(sum.at(())))
  observe_fresh(reads, store, store.read(sum.at(())))
  operations.push(if store.transaction(tx => tx.set(unrelated, 101)) is Ok(_) { "commit" } else { "error" })
  observe_fresh(reads, store, store.read(sum.at(())))
  operations.push(if store.transaction(tx => tx.set(left, 5)) is Ok(_) { "commit" } else { "error" })
  observe_fresh(reads, store, store.read(sum.at(())))
  operations.push(if store.transaction(tx => tx.set(left, 5)) is Ok(_) { "equal-commit" } else { "error" })
  observe_fresh(reads, store, store.read(sum.at(())))
  operations.push(match store.transaction(_ => Ok(())) { Ok(outcome) if !outcome.advanced => "empty"; _ => "error" })
  observe_fresh(reads, store, store.read(sum.at(())))
  operations.push(if store.transaction(tx => { ignore(tx.set(right, 9)); Err(@fresh.TransactionError::CallbackRejected) }) is Err(@fresh.TransactionError::CallbackRejected) { "rollback" } else { "error" })
  observe_fresh(reads, store, store.read(sum.at(())))
  ignore(region.close())
  { reads, operation_results: operations, final_revision: store.revision().value() }
}

///| Same operation/read script as basic_fresh_script, with operational assertions.
fn basic_incremental_script() -> (ScriptResult, Bool) {
  let reads : Array[String] = []
  let operations : Array[String] = []
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let left = must_inc_source(region.source(1))
  let right = must_inc_source(region.source(2))
  let unrelated = must_inc_source(region.source(100))
  let sum = must_inc_query(region.query((ctx, _ : Unit) => {
    match (ctx.read(left.view()), ctx.read(right.view())) {
      (Ok(a), Ok(b)) => Ok(a + b)
      (Err(error), _) => Err(error)
      (_, Err(error)) => Err(error)
    }
  }))
  observe_inc(reads, store, store.read(sum.at(())))
  observe_inc(reads, store, store.read(sum.at(())))
  operations.push(if store.transaction(tx => tx.set(unrelated, 101)) is Ok(_) { "commit" } else { "error" })
  observe_inc(reads, store, store.read(sum.at(())))
  operations.push(if store.transaction(tx => tx.set(left, 5)) is Ok(_) { "commit" } else { "error" })
  observe_inc(reads, store, store.read(sum.at(())))
  operations.push(if store.transaction(tx => tx.set(left, 5)) is Ok(_) { "equal-commit" } else { "error" })
  observe_inc(reads, store, store.read(sum.at(())))
  operations.push(match store.transaction(_ => Ok(())) { Ok(outcome) if !outcome.advanced => "empty"; _ => "error" })
  observe_inc(reads, store, store.read(sum.at(())))
  operations.push(if store.transaction(tx => { ignore(tx.set(right, 9)); Err(@incremental.TransactionError::CallbackRejected) }) is Err(@incremental.TransactionError::CallbackRejected) { "rollback" } else { "error" })
  observe_inc(reads, store, store.read(sum.at(())))
  let state = sum.debug()
  let operational = state.compute_count == 3 && state.green_verifications == 1 && state.cache_hits == 3 && state.memo_count == 1
  println("basic incremental compute=\{state.compute_count} green=\{state.green_verifications} cache_hits=\{state.cache_hits} memo=\{state.memo_count}")
  ignore(region.close())
  ({ reads, operation_results: operations, final_revision: store.revision().value() }, operational)
}

///| Fresh diamond recomputes the shared invocation along both paths.
fn diamond_fresh() -> (String, Int) {
  let store = @fresh.Store()
  let region = must_fresh_region(store.region())
  let source = must_fresh_source(region.source(1))
  let shared = must_fresh_query(region.query((ctx, _ : Unit) => ctx.read(source.view())))
  let left = must_fresh_query(region.query((ctx, _ : Unit) => match ctx.read(shared.at(())) { Ok(v) => Ok(v + 1); Err(e) => Err(e) }))
  let right = must_fresh_query(region.query((ctx, _ : Unit) => match ctx.read(shared.at(())) { Ok(v) => Ok(v + 2); Err(e) => Err(e) }))
  let root = must_fresh_query(region.query((ctx, _ : Unit) => match (ctx.read(left.at(())), ctx.read(right.at(()))) { (Ok(a), Ok(b)) => Ok(a + b); (Err(e), _) => Err(e); (_, Err(e)) => Err(e) }))
  let result = fresh_int(store.read(root.at(())))
  let count = shared.debug().compute_count
  ignore(region.close())
  (result, count)
}

///| Incremental diamond shares the equal-key upstream memo in one root.
fn diamond_incremental() -> (String, Int, Bool) {
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let source = must_inc_source(region.source(1))
  let shared = must_inc_query(region.query((ctx, _ : Unit) => ctx.read(source.view())))
  let left = must_inc_query(region.query((ctx, _ : Unit) => match ctx.read(shared.at(())) { Ok(v) => Ok(v + 1); Err(e) => Err(e) }))
  let right = must_inc_query(region.query((ctx, _ : Unit) => match ctx.read(shared.at(())) { Ok(v) => Ok(v + 2); Err(e) => Err(e) }))
  let root = must_inc_query(region.query((ctx, _ : Unit) => match (ctx.read(left.at(())), ctx.read(right.at(()))) { (Ok(a), Ok(b)) => Ok(a + b); (Err(e), _) => Err(e); (_, Err(e)) => Err(e) }))
  let result = inc_int(store.read(root.at(())))
  let count = shared.debug().compute_count
  let evidence = count == 1 && shared.debug().memo_count == 1 && source.debug().read_count == 1
  ignore(region.close())
  (result, count, evidence)
}

///| Same dynamic branch script for the fresh oracle.
fn dynamic_fresh() -> Array[String] {
  let out : Array[String] = []
  let store = @fresh.Store()
  let region = must_fresh_region(store.region())
  let mode = must_fresh_source(region.source(true))
  let left = must_fresh_source(region.source(10))
  let right = must_fresh_source(region.source(20))
  let choose = must_fresh_query(region.query((ctx, _ : Unit) => match ctx.read(mode.view()) { Ok(true) => ctx.read(left.view()); Ok(false) => ctx.read(right.view()); Err(e) => Err(e) }))
  observe_fresh(out, store, store.read(choose.at(())))
  ignore(store.transaction(tx => tx.set(right, 21)))
  observe_fresh(out, store, store.read(choose.at(())))
  ignore(store.transaction(tx => tx.set(mode, false)))
  observe_fresh(out, store, store.read(choose.at(())))
  ignore(store.transaction(tx => tx.set(left, 11)))
  observe_fresh(out, store, store.read(choose.at(())))
  ignore(region.close())
  out
}

///| Same dynamic branch script with trace-replacement/green-path assertions.
fn dynamic_incremental() -> (Array[String], Bool) {
  let out : Array[String] = []
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let mode = must_inc_source(region.source(true))
  let left = must_inc_source(region.source(10))
  let right = must_inc_source(region.source(20))
  let choose = must_inc_query(region.query((ctx, _ : Unit) => match ctx.read(mode.view()) { Ok(true) => ctx.read(left.view()); Ok(false) => ctx.read(right.view()); Err(e) => Err(e) }))
  observe_inc(out, store, store.read(choose.at(())))
  ignore(store.transaction(tx => tx.set(right, 21)))
  observe_inc(out, store, store.read(choose.at(())))
  ignore(store.transaction(tx => tx.set(mode, false)))
  observe_inc(out, store, store.read(choose.at(())))
  ignore(store.transaction(tx => tx.set(left, 11)))
  observe_inc(out, store, store.read(choose.at(())))
  let memo = choose.memo_debug(())
  let state = choose.debug()
  let trace_replaced = match memo {
    Some(memo) => memo.trace_length == 2
    None => false
  }
  let evidence = state.compute_count == 2 &&
    state.green_verifications == 2 &&
    left.debug().read_count == 1 &&
    right.debug().read_count == 1 &&
    trace_replaced
  println("dynamic compute=\{state.compute_count} green=\{state.green_verifications} left_reads=\{left.debug().read_count} right_reads=\{right.debug().read_count}")
  ignore(region.close())
  (out, evidence)
}

///| Fresh lifecycle/failure script.
fn failure_fresh() -> Array[String] {
  let out : Array[String] = []
  let store = @fresh.Store()
  let live = must_fresh_region(store.region())
  let secondary = must_fresh_region(store.region())
  let mode = must_fresh_source(live.source(true))
  let old = must_fresh_source(secondary.source(7))
  let fallback = must_fresh_source(live.source(9))
  let choose = must_fresh_query(live.query((ctx, _ : Unit) => match ctx.read(mode.view()) { Ok(true) => ctx.read(old.view()); Ok(false) => ctx.read(fallback.view()); Err(e) => Err(e) }))
  observe_fresh(out, store, store.read(choose.at(())))
  ignore(secondary.close())
  observe_fresh(out, store, store.read(choose.at(())))
  ignore(store.transaction(tx => tx.set(mode, false)))
  observe_fresh(out, store, store.read(choose.at(())))
  let unopened = must_fresh_region(store.region())
  let unavailable = must_fresh_source(unopened.source(5))
  let first_failure = must_fresh_query(
    live.query((ctx, _ : Unit) => ctx.read(unavailable.view())),
  )
  ignore(unopened.close())
  observe_fresh(out, store, store.read(first_failure.at(())))
  ignore(live.close())
  observe_fresh(out, store, store.read(choose.at(())))
  out
}

///| Failure preserves only the target memo; old verification cannot decide root error.
fn failure_incremental() -> (Array[String], Bool) {
  let out : Array[String] = []
  let store = @incremental.Store()
  let live = must_inc_region(store.region())
  let secondary = must_inc_region(store.region())
  let mode = must_inc_source(live.source(true))
  let old = must_inc_source(secondary.source(7))
  let fallback = must_inc_source(live.source(9))
  let choose = must_inc_query(live.query((ctx, _ : Unit) => match ctx.read(mode.view()) { Ok(true) => ctx.read(old.view()); Ok(false) => ctx.read(fallback.view()); Err(e) => Err(e) }))
  observe_inc(out, store, store.read(choose.at(())))
  let before = choose.memo_debug(())
  ignore(secondary.close())
  observe_inc(out, store, store.read(choose.at(())))
  let after_failure = choose.memo_debug(())
  ignore(store.transaction(tx => tx.set(mode, false)))
  observe_inc(out, store, store.read(choose.at(())))
  let after_recovery = choose.memo_debug(())
  let target_preserved = match (before, after_failure) {
    (Some(a), Some(b)) => a.memo_id == b.memo_id && a.trace_length == b.trace_length && a.verified_at == b.verified_at && a.changed_at == b.changed_at
    _ => false
  }
  let recovered_same_memo = match (before, after_recovery) { (Some(a), Some(b)) => a.memo_id == b.memo_id; _ => false }
  let closed_verified = old.debug().verification_count >= 2
  let state = choose.debug()

  // An invocation with no successful history installs no entry on failure.
  let unopened = must_inc_region(store.region())
  let unavailable = must_inc_source(unopened.source(5))
  let first_failure = must_inc_query(live.query((ctx, _ : Unit) => ctx.read(unavailable.view())))
  ignore(unopened.close())
  let first_read = store.read(first_failure.at(()))
  observe_inc(out, store, first_read)
  let first_error = first_read is Err(@incremental.ReadError::ClosedRegion(_))
  let no_initial_memo = first_failure.debug().memo_count == 0
  ignore(live.close())
  let direct_closed = store.read(choose.at(()))
  observe_inc(out, store, direct_closed)

  let evidence = target_preserved && recovered_same_memo && closed_verified &&
    state.failed_recomputes == 1 && first_error && no_initial_memo &&
    direct_closed is Err(@incremental.ReadError::ClosedRegion(_)) &&
    out[1] == "Err(ClosedRegion)@r0" && out[2] == "Ok(9)@r1"
  println("failure target_preserved=\{target_preserved} recovered_same_memo=\{recovered_same_memo} old_verifications=\{old.debug().verification_count} failed=\{state.failed_recomputes} initial_memo=\{first_failure.debug().memo_count} direct_closed=\{direct_closed is Err(@incremental.ReadError::ClosedRegion(_))}")
  (out, evidence)
}

///| Fresh RevisionClock/domain script.
fn clock_fresh() -> (Array[String], String) {
  let out : Array[String] = []
  let store = @fresh.Store()
  let primary = must_fresh_region(store.region())
  let unrelated = must_fresh_region(store.region())
  let trigger = must_fresh_source(primary.source(0))
  let clock = must_fresh_query(primary.query((ctx, _ : Unit) => Ok(ctx.revision().value())))
  let constant = must_fresh_query(primary.query((_ctx, _ : Unit) => Ok(42)))
  let domain : @fresh.Query[Unit, Result[Int, String]] = must_fresh_query(primary.query((_ctx, _ : Unit) => Ok(Err("domain failure"))))
  observe_fresh(out, store, store.read(clock.at(())))
  observe_fresh(out, store, store.read(constant.at(())))
  ignore(unrelated.close())
  observe_fresh(out, store, store.read(clock.at(())))
  observe_fresh(out, store, store.read(constant.at(())))
  ignore(store.transaction(tx => tx.set(trigger, 0)))
  observe_fresh(out, store, store.read(clock.at(())))
  observe_fresh(out, store, store.read(constant.at(())))
  let domain_text = match store.read(domain.at(())) { Ok(Err(message)) => "DomainErr(\{message})"; _ => "wrong" }
  ignore(primary.close())
  (out, domain_text)
}

///| RevisionClock changes on commit but remains green on lifecycle-only epoch change.
fn clock_incremental() -> (Array[String], String, Bool) {
  let out : Array[String] = []
  let store = @incremental.Store()
  let primary = must_inc_region(store.region())
  let unrelated = must_inc_region(store.region())
  let trigger = must_inc_source(primary.source(0))
  let clock = must_inc_query(primary.query((ctx, _ : Unit) => Ok(ctx.revision().value())))
  let constant = must_inc_query(primary.query((_ctx, _ : Unit) => Ok(42)))
  let domain : @incremental.Query[Unit, Result[Int, String]] = must_inc_query(primary.query((_ctx, _ : Unit) => Ok(Err("domain failure"))))
  observe_inc(out, store, store.read(clock.at(())))
  observe_inc(out, store, store.read(constant.at(())))
  ignore(unrelated.close())
  observe_inc(out, store, store.read(clock.at(())))
  observe_inc(out, store, store.read(constant.at(())))
  ignore(store.transaction(tx => tx.set(trigger, 0)))
  observe_inc(out, store, store.read(clock.at(())))
  observe_inc(out, store, store.read(constant.at(())))
  let domain_text = match store.read(domain.at(())) { Ok(Err(message)) => "DomainErr(\{message})"; _ => "wrong" }
  let state = clock.debug()
  let constant_state = constant.debug()
  let evidence = state.compute_count == 2 &&
    state.green_verifications == 1 &&
    constant_state.compute_count == 1 &&
    constant_state.green_verifications == 2 &&
    store.revision().value() == 1 &&
    store.change_epoch().value() == 2 &&
    store.revision_changed_at().value() == 2
  println("clock compute=\{state.compute_count} green=\{state.green_verifications} constant_compute=\{constant_state.compute_count} constant_green=\{constant_state.green_verifications} revision=\{store.revision().value()} epoch=\{store.change_epoch().value()} revision_changed_at=\{store.revision_changed_at().value()}")
  ignore(primary.close())
  (out, domain_text, evidence)
}

///| Fresh side of a two-Source atomic commit and blocked intermediate read.
fn atomic_fresh() -> (Array[String], Bool) {
  let reads : Array[String] = []
  let store = @fresh.Store()
  let region = must_fresh_region(store.region())
  let left = must_fresh_source(region.source(1))
  let right = must_fresh_source(region.source(2))
  let root = must_fresh_query(region.query((ctx, _ : Unit) => {
    match (ctx.read(left.view()), ctx.read(right.view())) {
      (Ok(a), Ok(b)) => Ok((a, b, ctx.revision().value()))
      (Err(error), _) => Err(error)
      (_, Err(error)) => Err(error)
    }
  }))
  let normalize = result => match result {
    Ok((a, b, revision)) => "Ok(\{a},\{b},\{revision})"
    Err(@fresh.ReadError::ReadDuringTransaction(_)) => "Err(ReadDuringTransaction)"
    Err(_) => "Err(Other)"
  }
  reads.push(normalize(store.read(root.at(()))))
  let blocked = Ref(false)
  let commit = store.transaction(tx => {
    match tx.set(left, 10) {
      Err(error) => Err(error)
      Ok(_) => {
        blocked.val = store.read(root.at(())) is Err(@fresh.ReadError::ReadDuringTransaction(_))
        tx.set(right, 20)
      }
    }
  })
  reads.push(normalize(store.read(root.at(()))))
  let passed = blocked.val && commit is Ok(outcome) && outcome.applied_count == 2
  ignore(region.close())
  (reads, passed)
}

///| Incremental side of the identical atomic script.
fn atomic_incremental() -> (Array[String], Bool) {
  let reads : Array[String] = []
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let left = must_inc_source(region.source(1))
  let right = must_inc_source(region.source(2))
  let root = must_inc_query(region.query((ctx, _ : Unit) => {
    match (ctx.read(left.view()), ctx.read(right.view())) {
      (Ok(a), Ok(b)) => Ok((a, b, ctx.revision().value()))
      (Err(error), _) => Err(error)
      (_, Err(error)) => Err(error)
    }
  }))
  let normalize = result => match result {
    Ok((a, b, revision)) => "Ok(\{a},\{b},\{revision})"
    Err(@incremental.ReadError::ReadDuringTransaction(_)) => "Err(ReadDuringTransaction)"
    Err(_) => "Err(Other)"
  }
  reads.push(normalize(store.read(root.at(()))))
  let blocked = Ref(false)
  let commit = store.transaction(tx => {
    match tx.set(left, 10) {
      Err(error) => Err(error)
      Ok(_) => {
        blocked.val = store.read(root.at(())) is Err(@incremental.ReadError::ReadDuringTransaction(_))
        tx.set(right, 20)
      }
    }
  })
  reads.push(normalize(store.read(root.at(()))))
  let passed = blocked.val &&
    commit is Ok(outcome) && outcome.applied_count == 2 &&
    root.debug().compute_count == 2 && store.revision().value() == 1
  ignore(region.close())
  (reads, passed)
}

///| Demonstrates why mutable aliases are excluded from admissible parity scripts.
fn snapshot_contract_counterexample() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_payload = MutablePayload::{ value: Ref(10) }
  let fresh_source = must_fresh_source(fresh_region.source(fresh_payload))
  let fresh_projection = must_fresh_query(
    fresh_region.query((ctx, _ : Unit) => match ctx.read(fresh_source.view()) {
      Ok(value) => Ok(value.value.val)
      Err(error) => Err(error)
    }),
  )
  let fresh_before = fresh_store.read(fresh_projection.at(()))
  fresh_payload.value.val = 11
  let fresh_after = fresh_store.read(fresh_projection.at(()))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_payload = MutablePayload::{ value: Ref(10) }
  let inc_source = must_inc_source(inc_region.source(inc_payload))
  let inc_projection = must_inc_query(
    inc_region.query((ctx, _ : Unit) => match ctx.read(inc_source.view()) {
      Ok(value) => Ok(value.value.val)
      Err(error) => Err(error)
    }),
  )
  let inc_before = inc_store.read(inc_projection.at(()))
  inc_payload.value.val = 11
  let inc_after = inc_store.read(inc_projection.at(()))

  let mutable_result = must_inc_query(
    inc_region.query((_ctx, _ : Unit) =>
      Ok(MutableResult::{ value: Ref(20) })),
  )
  let returned_alias = inc_store.read(mutable_result.at(()))
  match returned_alias {
    Ok(value) => value.value.val = 21
    Err(_) => ()
  }
  let cached_alias_changed = match inc_store.read(mutable_result.at(())) {
    Ok(value) => value.value.val == 21
    Err(_) => false
  }
  let observed = fresh_before == Ok(10) && fresh_after == Ok(11) &&
    inc_before == Ok(10) && inc_after == Ok(10) && cached_alias_changed &&
    inc_store.revision().value() == 0
  println("excluded_snapshot_violation fresh=\{fresh_int(fresh_before)}->\{fresh_int(fresh_after)} incremental=\{inc_int(inc_before)}->\{inc_int(inc_after)} cached_alias_changed=\{cached_alias_changed} expected_divergence=\{observed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  observed
}

///| Equal keys share a typed memo even when View handles are distinct.
fn keyed_identity() -> Bool {
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let query = must_inc_query(region.query((_ctx, key : String) => Ok(key.length())))
  let first = query.at("same")
  let second = query.at("same")
  let a = store.read(first)
  let memo_a = query.memo_debug("same")
  let b = store.read(second)
  let memo_b = query.memo_debug("same")
  let same_memo = match (memo_a, memo_b) {
    (Some(x), Some(y)) => x.memo_id == y.memo_id
    _ => false
  }
  // View/session/memo allocation above must not perturb definition identity.
  let second_query = must_inc_query(
    region.query((_ctx, key : String) => Ok(key.length() + 1)),
  )
  ignore(store.read(second_query.at("same")))
  let query_local_memos = match (memo_b, second_query.memo_debug("same")) {
    (Some(first_memo), Some(second_memo)) =>
      first_memo.memo_id.sequence() == 1 &&
      second_memo.memo_id.sequence() == 1
    _ => false
  }
  let separate_allocators = second_query.id().sequence() ==
    query.id().sequence() + 1 && query_local_memos
  let passed = a == Ok(4) &&
    b == Ok(4) &&
    first.handle_id() != second.handle_id() &&
    query.debug().memo_count == 1 &&
    query.debug().compute_count == 1 &&
    same_memo && separate_allocators
  println("keyed equal_views=\{passed} memo_count=\{query.debug().memo_count} compute=\{query.debug().compute_count} separate_allocators=\{separate_allocators}")
  ignore(region.close())
  passed
}

///| Fresh side of the rejected/rollback/close script.
fn edge_fresh() -> EdgeResult {
  let operations : Array[String] = []
  let revisions : Array[Int] = []
  let store = @fresh.Store()
  let region = must_fresh_region(store.region())
  let source = must_fresh_source(region.source(1))
  let other = @fresh.Store()
  let other_region = must_fresh_region(other.region())
  let other_source = must_fresh_source(other_region.source(2))
  operations.push(if store.transaction(tx => { ignore(tx.set(other_source, 3)); Ok(()) }) is Err(@fresh.TransactionError::CrossStore(_)) { "Err(CrossStore)" } else { "wrong" })
  revisions.push(store.revision().value())
  operations.push(if store.transaction(tx => { ignore(tx.set(source, 4)); Err(@fresh.TransactionError::CallbackRejected) }) is Err(@fresh.TransactionError::CallbackRejected) { "Err(CallbackRejected)" } else { "wrong" })
  revisions.push(store.revision().value())
  operations.push(if region.close() is Ok(_) { "Ok(Close)" } else { "wrong" })
  revisions.push(store.revision().value())
  operations.push(if region.close() is Err(@fresh.RegionError::ClosedRegion(_)) { "Err(ClosedRegion)" } else { "wrong" })
  revisions.push(store.revision().value())
  ignore(other_region.close())
  { operations, revisions }
}

///| Incremental side; rejected/duplicate transitions preserve ChangeEpoch.
fn edge_incremental() -> (EdgeResult, Bool) {
  let operations : Array[String] = []
  let revisions : Array[Int] = []
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let source = must_inc_source(region.source(1))
  let other = @incremental.Store()
  let other_region = must_inc_region(other.region())
  let other_source = must_inc_source(other_region.source(2))
  let before = (store.revision(), store.change_epoch())
  operations.push(if store.transaction(tx => { ignore(tx.set(other_source, 3)); Ok(()) }) is Err(@incremental.TransactionError::CrossStore(_)) { "Err(CrossStore)" } else { "wrong" })
  revisions.push(store.revision().value())
  let after_rejected = (store.revision(), store.change_epoch())
  operations.push(if store.transaction(tx => { ignore(tx.set(source, 4)); Err(@incremental.TransactionError::CallbackRejected) }) is Err(@incremental.TransactionError::CallbackRejected) { "Err(CallbackRejected)" } else { "wrong" })
  revisions.push(store.revision().value())
  let after_rollback = (store.revision(), store.change_epoch())
  operations.push(if region.close() is Ok(_) { "Ok(Close)" } else { "wrong" })
  revisions.push(store.revision().value())
  let after_close = (store.revision(), store.change_epoch())
  operations.push(if region.close() is Err(@incremental.RegionError::ClosedRegion(_)) { "Err(ClosedRegion)" } else { "wrong" })
  revisions.push(store.revision().value())
  let after_duplicate = (store.revision(), store.change_epoch())
  ignore(other_region.close())
  let clocks = before == after_rejected &&
    before == after_rollback &&
    after_close.0 == before.0 &&
    after_close.1.value() == before.1.value() + 1 &&
    after_duplicate == after_close
  println("edges rejected/rollback unchanged=\{before == after_rejected && before == after_rollback} close_epoch=\{after_close.1.value()} duplicate_unchanged=\{after_duplicate == after_close}")
  ({ operations, revisions }, clocks)
}

///|
fn main {
  println("INCR NEXT — #462 VERIFYING-TRACE PARITY")
  let fresh_basic = basic_fresh_script()
  let inc_basic = basic_incremental_script()
  let basic_parity = fresh_basic.reads == inc_basic.0.reads && fresh_basic.operation_results == inc_basic.0.operation_results && fresh_basic.final_revision == inc_basic.0.final_revision
  println("basic reads fresh=\{fresh_basic.reads.join(",")} incremental=\{inc_basic.0.reads.join(",")} parity=\{basic_parity}")

  let fresh_diamond = diamond_fresh()
  let inc_diamond = diamond_incremental()
  let diamond = fresh_diamond.0 == inc_diamond.0 && fresh_diamond.1 == 2 && inc_diamond.1 == 1 && inc_diamond.2
  println("diamond outcome=\{fresh_diamond.0} fresh_shared=\{fresh_diamond.1} incremental_shared=\{inc_diamond.1} parity=\{diamond}")

  let fresh_dynamic = dynamic_fresh()
  let inc_dynamic = dynamic_incremental()
  let dynamic = fresh_dynamic == inc_dynamic.0 && inc_dynamic.1
  println("dynamic fresh=\{fresh_dynamic.join(",")} incremental=\{inc_dynamic.0.join(",")} parity=\{dynamic}")

  let fresh_failure = failure_fresh()
  let inc_failure = failure_incremental()
  let failure = fresh_failure == inc_failure.0 && inc_failure.1
  println("failure fresh=\{fresh_failure.join(",")} incremental=\{inc_failure.0.join(",")} parity=\{failure}")

  let fresh_clock = clock_fresh()
  let inc_clock = clock_incremental()
  let clock = fresh_clock.0 == inc_clock.0 && fresh_clock.1 == inc_clock.1 && inc_clock.2
  println("clock fresh=\{fresh_clock.0.join(",")} incremental=\{inc_clock.0.join(",")} domain=\{inc_clock.1} parity=\{clock}")

  let fresh_atomic = atomic_fresh()
  let inc_atomic = atomic_incremental()
  let atomic_parity = fresh_atomic.0 == inc_atomic.0 &&
    fresh_atomic.1 && inc_atomic.1
  println("atomic fresh=\{fresh_atomic.0.join(",")} incremental=\{inc_atomic.0.join(",")} parity=\{atomic_parity}")

  let excluded_contract_violation = snapshot_contract_counterexample()
  let keyed = keyed_identity()
  let fresh_edges = edge_fresh()
  let inc_edges = edge_incremental()
  let edges = fresh_edges.operations == inc_edges.0.operations &&
    fresh_edges.revisions == inc_edges.0.revisions && inc_edges.1
  println("edges fresh=\{fresh_edges.operations.join(",")} incremental=\{inc_edges.0.operations.join(",")} parity=\{edges}")
  let passed = basic_parity && inc_basic.1 && diamond && dynamic && failure &&
    clock && atomic_parity && excluded_contract_violation && keyed && edges
  println("full_state basic=\{basic_parity && inc_basic.1} diamond=\{diamond} dynamic=\{dynamic} failure=\{failure} clock=\{clock} atomic=\{atomic_parity} excluded_contract_violation=\{excluded_contract_violation} keyed=\{keyed} edges=\{edges}")
  println("constrained verdict: \{if passed { "PASS" } else { "FAIL" }}")
  if !passed { abort("incremental parity evidence failed") }
}
