///| Normalizes one cycle-aware fresh Int read through scenario-local names.
fn normalize_fresh_cycle(
  result : Result[Int, @fresh.ReadError],
  name : (@fresh.QueryId) -> String,
) -> String {
  match result {
    Ok(value) => "Ok(\{value})"
    Err(@fresh.ReadError::Cycle(witness)) =>
      "Cycle(\{witness.path.map(name).join(">")})"
    Err(@fresh.ReadError::CrossStore(_)) => "Err(CrossStore)"
    Err(@fresh.ReadError::ClosedRegion(_)) => "Err(ClosedRegion)"
    Err(@fresh.ReadError::ExpiredEvalContext(_)) => "Err(ExpiredEvalContext)"
    Err(@fresh.ReadError::ReentrantRootRead(_)) => "Err(ReentrantRootRead)"
    Err(@fresh.ReadError::ReadDuringTransaction(_)) =>
      "Err(ReadDuringTransaction)"
  }
}

///| Normalizes one cycle-aware incremental Int read through logical names.
fn normalize_incremental_cycle(
  result : Result[Int, @incremental.ReadError],
  name : (@incremental.QueryId) -> String,
) -> String {
  match result {
    Ok(value) => "Ok(\{value})"
    Err(@incremental.ReadError::Cycle(witness)) =>
      "Cycle(\{witness.path.map(name).join(">")})"
    Err(@incremental.ReadError::CrossStore(_)) => "Err(CrossStore)"
    Err(@incremental.ReadError::ClosedRegion(_)) => "Err(ClosedRegion)"
    Err(@incremental.ReadError::ExpiredEvalContext(_)) =>
      "Err(ExpiredEvalContext)"
    Err(@incremental.ReadError::ReentrantRootRead(_)) =>
      "Err(ReentrantRootRead)"
    Err(@incremental.ReadError::ReadDuringTransaction(_)) =>
      "Err(ReadDuringTransaction)"
  }
}

///| Direct self-cycle is detected afresh on every read and leaves no active state.
fn cycle_direct_self() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let fresh_query = must_fresh_query(
    fresh_region.query((ctx, _ : Unit) => match fresh_ref.val {
      Some(self) => ctx.read(self.at(()))
      None => Ok(-1)
    }),
  )
  fresh_ref.val = Some(fresh_query)
  let fresh_name = id => if id == fresh_query.id() { "A" } else { "?" }
  let fresh_first = normalize_fresh_cycle(
    fresh_store.read(fresh_query.at(())),
    fresh_name,
  )
  let fresh_second = normalize_fresh_cycle(
    fresh_store.read(fresh_query.at(())),
    fresh_name,
  )

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let inc_query = must_inc_query(
    inc_region.query((ctx, _ : Unit) => match inc_ref.val {
      Some(self) => ctx.read(self.at(()))
      None => Ok(-1)
    }),
  )
  inc_ref.val = Some(inc_query)
  let inc_name = id => if id == inc_query.id() { "A" } else { "?" }
  let inc_first = normalize_incremental_cycle(
    inc_store.read(inc_query.at(())),
    inc_name,
  )
  let inc_second = normalize_incremental_cycle(
    inc_store.read(inc_query.at(())),
    inc_name,
  )
  let expected = fresh_first == "Cycle(A>A)" && fresh_second == fresh_first
  let clean = fresh_query.debug().active_count == 0 &&
    inc_query.debug().active_count == 0 &&
    inc_query.debug().memo_count == 0 &&
    fresh_store.debug().last_finished_active_depth == 0 &&
    inc_store.debug().last_finished_active_depth == 0 &&
    inc_query.debug().compute_count == 2
  let passed = expected && fresh_first == inc_first && fresh_second == inc_second && clean
  println("cycle_direct fresh=\{fresh_first},\{fresh_second} incremental=\{inc_first},\{inc_second} clean=\{clean} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| QueryId repetition alone is not a cycle when each recursive key differs.
fn cycle_finite_recursion() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_ref : Ref[@fresh.Query[Int, Int]?] = Ref(None)
  let fresh_query = must_fresh_query(
    fresh_region.query((ctx, key : Int) =>
      if key == 0 {
        Ok(0)
      } else {
        match fresh_ref.val {
          Some(self) => match ctx.read(self.at(key - 1)) {
            Ok(value) => Ok(value + 1)
            Err(error) => Err(error)
          }
          None => Ok(-1)
        }
      }),
  )
  fresh_ref.val = Some(fresh_query)
  let fresh_value = fresh_store.read(fresh_query.at(3))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_ref : Ref[@incremental.Query[Int, Int]?] = Ref(None)
  let inc_query = must_inc_query(
    inc_region.query((ctx, key : Int) =>
      if key == 0 {
        Ok(0)
      } else {
        match inc_ref.val {
          Some(self) => match ctx.read(self.at(key - 1)) {
            Ok(value) => Ok(value + 1)
            Err(error) => Err(error)
          }
          None => Ok(-1)
        }
      }),
  )
  inc_ref.val = Some(inc_query)
  let inc_value = inc_store.read(inc_query.at(3))
  let inc_again = inc_store.read(inc_query.at(3))
  let clean = fresh_query.debug().active_count == 0 &&
    inc_query.debug().active_count == 0 &&
    inc_query.debug().memo_count == 4 &&
    inc_query.debug().compute_count == 4 &&
    inc_store.debug().last_finished_active_depth == 0
  let passed = fresh_value == Ok(3) && inc_value == Ok(3) &&
    inc_again == Ok(3) && clean
  println("cycle_finite fresh=\{fresh_value is Ok(3)} incremental=\{inc_value is Ok(3)} memos=\{inc_query.debug().memo_count} clean=\{clean} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| Same QueryCore re-entry becomes a cycle only when K::Eq matches an active key.
fn cycle_same_query_keys() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_ref : Ref[@fresh.Query[Int, Int]?] = Ref(None)
  let fresh_query = must_fresh_query(
    fresh_region.query((ctx, key : Int) => match fresh_ref.val {
      Some(self) => ctx.read(self.at(if key == 0 { 1 } else { 0 }))
      None => Ok(-1)
    }),
  )
  fresh_ref.val = Some(fresh_query)
  let fresh_out = normalize_fresh_cycle(
    fresh_store.read(fresh_query.at(0)),
    id => if id == fresh_query.id() { "Q" } else { "?" },
  )

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_ref : Ref[@incremental.Query[Int, Int]?] = Ref(None)
  let inc_query = must_inc_query(
    inc_region.query((ctx, key : Int) => match inc_ref.val {
      Some(self) => ctx.read(self.at(if key == 0 { 1 } else { 0 }))
      None => Ok(-1)
    }),
  )
  inc_ref.val = Some(inc_query)
  let inc_out = normalize_incremental_cycle(
    inc_store.read(inc_query.at(0)),
    id => if id == inc_query.id() { "Q" } else { "?" },
  )
  let clean = fresh_query.debug().active_count == 0 &&
    inc_query.debug().active_count == 0 && inc_query.debug().memo_count == 0
  let passed = fresh_out == "Cycle(Q>Q>Q)" && fresh_out == inc_out && clean
  println("cycle_same_query fresh=\{fresh_out} incremental=\{inc_out} clean=\{clean} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| Two Query definitions produce the copied logical witness A>B>A.
fn cycle_mutual() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_a_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let fresh_b_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let fresh_a = must_fresh_query(
    fresh_region.query((ctx, _ : Unit) => match fresh_b_ref.val {
      Some(value) => ctx.read(value.at(()))
      None => Ok(-1)
    }),
  )
  let fresh_b = must_fresh_query(
    fresh_region.query((ctx, _ : Unit) => match fresh_a_ref.val {
      Some(value) => ctx.read(value.at(()))
      None => Ok(-1)
    }),
  )
  fresh_a_ref.val = Some(fresh_a)
  fresh_b_ref.val = Some(fresh_b)
  let fresh_out = normalize_fresh_cycle(
    fresh_store.read(fresh_a.at(())),
    id => if id == fresh_a.id() { "A" } else if id == fresh_b.id() { "B" } else { "?" },
  )

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_a_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let inc_b_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let inc_a = must_inc_query(
    inc_region.query((ctx, _ : Unit) => match inc_b_ref.val {
      Some(value) => ctx.read(value.at(()))
      None => Ok(-1)
    }),
  )
  let inc_b = must_inc_query(
    inc_region.query((ctx, _ : Unit) => match inc_a_ref.val {
      Some(value) => ctx.read(value.at(()))
      None => Ok(-1)
    }),
  )
  inc_a_ref.val = Some(inc_a)
  inc_b_ref.val = Some(inc_b)
  let inc_out = normalize_incremental_cycle(
    inc_store.read(inc_a.at(())),
    id => if id == inc_a.id() { "A" } else if id == inc_b.id() { "B" } else { "?" },
  )
  let clean = fresh_a.debug().active_count + fresh_b.debug().active_count == 0 &&
    inc_a.debug().active_count + inc_b.debug().active_count == 0 &&
    inc_a.debug().memo_count + inc_b.debug().memo_count == 0
  let passed = fresh_out == "Cycle(A>B>A)" && fresh_out == inc_out && clean
  println("cycle_mutual fresh=\{fresh_out} incremental=\{inc_out} clean=\{clean} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| Existing A memo survives introduced cycles, then recovers with the same MemoId.
fn cycle_introduction_and_recovery() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_mode = must_fresh_source(fresh_region.source(0))
  let fresh_value = must_fresh_source(fresh_region.source(7))
  let fresh_a_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let fresh_b_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let fresh_a = must_fresh_query(
    fresh_region.query((ctx, _ : Unit) => match ctx.read(fresh_mode.view()) {
      Err(error) => Err(error)
      Ok(0) => ctx.read(fresh_value.view())
      Ok(_) => match fresh_b_ref.val { Some(b) => ctx.read(b.at(())); None => Ok(-1) }
    }),
  )
  let fresh_b = must_fresh_query(
    fresh_region.query((ctx, _ : Unit) => match fresh_a_ref.val {
      Some(a) => ctx.read(a.at(()))
      None => Ok(-1)
    }),
  )
  fresh_a_ref.val = Some(fresh_a)
  fresh_b_ref.val = Some(fresh_b)
  let fresh_name = id => if id == fresh_a.id() { "A" } else if id == fresh_b.id() { "B" } else { "?" }
  let fresh_results : Array[String] = []
  fresh_results.push(normalize_fresh_cycle(fresh_store.read(fresh_a.at(())), fresh_name))
  ignore(fresh_store.transaction(tx => tx.set(fresh_mode, 1)))
  fresh_results.push(normalize_fresh_cycle(fresh_store.read(fresh_a.at(())), fresh_name))
  fresh_results.push(normalize_fresh_cycle(fresh_store.read(fresh_a.at(())), fresh_name))
  ignore(fresh_store.transaction(tx => tx.set(fresh_mode, 0)))
  fresh_results.push(normalize_fresh_cycle(fresh_store.read(fresh_a.at(())), fresh_name))
  fresh_results.push(normalize_fresh_cycle(fresh_store.read(fresh_b.at(())), fresh_name))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_mode = must_inc_source(inc_region.source(0))
  let inc_value = must_inc_source(inc_region.source(7))
  let inc_a_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let inc_b_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let inc_a = must_inc_query(
    inc_region.query((ctx, _ : Unit) => match ctx.read(inc_mode.view()) {
      Err(error) => Err(error)
      Ok(0) => ctx.read(inc_value.view())
      Ok(_) => match inc_b_ref.val { Some(b) => ctx.read(b.at(())); None => Ok(-1) }
    }),
  )
  let inc_b = must_inc_query(
    inc_region.query((ctx, _ : Unit) => match inc_a_ref.val {
      Some(a) => ctx.read(a.at(()))
      None => Ok(-1)
    }),
  )
  inc_a_ref.val = Some(inc_a)
  inc_b_ref.val = Some(inc_b)
  let inc_name = id => if id == inc_a.id() { "A" } else if id == inc_b.id() { "B" } else { "?" }
  let inc_results : Array[String] = []
  inc_results.push(normalize_incremental_cycle(inc_store.read(inc_a.at(())), inc_name))
  let before = inc_a.memo_debug(())
  ignore(inc_store.transaction(tx => tx.set(inc_mode, 1)))
  inc_results.push(normalize_incremental_cycle(inc_store.read(inc_a.at(())), inc_name))
  let after_cycle = inc_a.memo_debug(())
  inc_results.push(normalize_incremental_cycle(inc_store.read(inc_a.at(())), inc_name))
  ignore(inc_store.transaction(tx => tx.set(inc_mode, 0)))
  inc_results.push(normalize_incremental_cycle(inc_store.read(inc_a.at(())), inc_name))
  let after_recovery = inc_a.memo_debug(())
  inc_results.push(normalize_incremental_cycle(inc_store.read(inc_b.at(())), inc_name))
  let b_first_memo = inc_b.memo_debug(())
  let preserved = match (before, after_cycle, after_recovery) {
    (Some(a), Some(b), Some(c)) => a.memo_id == b.memo_id && b.memo_id == c.memo_id &&
      a.trace_length == b.trace_length && a.verified_at == b.verified_at &&
      a.changed_at == b.changed_at
    _ => false
  }
  let first_b_after_recovery = match b_first_memo {
    Some(memo) => memo.memo_id.sequence() == 1
    None => false
  }
  let expected = ["Ok(7)", "Cycle(A>B>A)", "Cycle(A>B>A)", "Ok(7)", "Ok(7)"]
  let clean = inc_a.debug().active_count + inc_b.debug().active_count == 0 &&
    inc_store.debug().last_finished_active_depth == 0
  let passed = fresh_results == expected && inc_results == expected &&
    preserved && first_b_after_recovery && clean
  println("cycle_recovery fresh=\{fresh_results.join(",")} incremental=\{inc_results.join(",")} preserved=\{preserved} b_first_memo=\{first_b_after_recovery} clean=\{clean} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| Old-trace Cycle is only RecomputeRequired when the current branch is acyclic.
fn cycle_old_trace_branch_away() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_phase = must_fresh_source(fresh_region.source(0))
  let fresh_value = must_fresh_source(fresh_region.source(5))
  let fresh_a_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let fresh_b_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let fresh_a = must_fresh_query(fresh_region.query((ctx, _ : Unit) => match ctx.read(fresh_phase.view()) {
    Err(error) => Err(error)
    Ok(0) => ctx.read(fresh_value.view())
    Ok(_) => match fresh_b_ref.val { Some(b) => ctx.read(b.at(())); None => Ok(-1) }
  }))
  let fresh_b = must_fresh_query(fresh_region.query((ctx, _ : Unit) => match ctx.read(fresh_phase.view()) {
    Err(error) => Err(error)
    Ok(0) => match fresh_a_ref.val { Some(a) => ctx.read(a.at(())); None => Ok(-1) }
    Ok(_) => ctx.read(fresh_value.view())
  }))
  fresh_a_ref.val = Some(fresh_a)
  fresh_b_ref.val = Some(fresh_b)
  let fresh_initial = (fresh_store.read(fresh_a.at(())), fresh_store.read(fresh_b.at(())))
  ignore(fresh_store.transaction(tx => tx.set(fresh_phase, 1)))
  let fresh_after = fresh_store.read(fresh_a.at(()))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_phase = must_inc_source(inc_region.source(0))
  let inc_value = must_inc_source(inc_region.source(5))
  let inc_a_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let inc_b_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let inc_a = must_inc_query(inc_region.query((ctx, _ : Unit) => match ctx.read(inc_phase.view()) {
    Err(error) => Err(error)
    Ok(0) => ctx.read(inc_value.view())
    Ok(_) => match inc_b_ref.val { Some(b) => ctx.read(b.at(())); None => Ok(-1) }
  }))
  let inc_b = must_inc_query(inc_region.query((ctx, _ : Unit) => match ctx.read(inc_phase.view()) {
    Err(error) => Err(error)
    Ok(0) => match inc_a_ref.val { Some(a) => ctx.read(a.at(())); None => Ok(-1) }
    Ok(_) => ctx.read(inc_value.view())
  }))
  inc_a_ref.val = Some(inc_a)
  inc_b_ref.val = Some(inc_b)
  let inc_initial = (inc_store.read(inc_a.at(())), inc_store.read(inc_b.at(())))
  ignore(inc_store.transaction(tx => tx.set(inc_phase, 1)))
  let inc_after = inc_store.read(inc_a.at(()))
  let clean = inc_a.debug().active_count + inc_b.debug().active_count == 0 &&
    inc_store.debug().last_finished_active_depth == 0
  let passed = fresh_initial == (Ok(5), Ok(5)) &&
    inc_initial == (Ok(5), Ok(5)) && fresh_after == Ok(5) &&
    inc_after == Ok(5) && clean &&
    inc_b.debug().compute_count == 2
  println("cycle_old_trace_branch fresh=\{fresh_after is Ok(5)} incremental=\{inc_after is Ok(5)} b_recomputed=\{inc_b.debug().compute_count == 2} clean=\{clean} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| The same old graph can transition to a current A>B>A cycle.
fn cycle_current_transition() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_phase = must_fresh_source(fresh_region.source(0))
  let fresh_value = must_fresh_source(fresh_region.source(5))
  let fresh_a_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let fresh_b_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let fresh_a = must_fresh_query(fresh_region.query((ctx, _ : Unit) => match ctx.read(fresh_phase.view()) {
    Err(error) => Err(error)
    Ok(0) => ctx.read(fresh_value.view())
    Ok(_) => match fresh_b_ref.val { Some(b) => ctx.read(b.at(())); None => Ok(-1) }
  }))
  let fresh_b = must_fresh_query(fresh_region.query((ctx, _ : Unit) => match fresh_a_ref.val {
    Some(a) => ctx.read(a.at(()))
    None => Ok(-1)
  }))
  fresh_a_ref.val = Some(fresh_a)
  fresh_b_ref.val = Some(fresh_b)
  ignore(fresh_store.read(fresh_a.at(())))
  ignore(fresh_store.read(fresh_b.at(())))
  ignore(fresh_store.transaction(tx => tx.set(fresh_phase, 1)))
  let fresh_out = normalize_fresh_cycle(
    fresh_store.read(fresh_a.at(())),
    id => if id == fresh_a.id() { "A" } else if id == fresh_b.id() { "B" } else { "?" },
  )

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_phase = must_inc_source(inc_region.source(0))
  let inc_value = must_inc_source(inc_region.source(5))
  let inc_a_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let inc_b_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let inc_a = must_inc_query(inc_region.query((ctx, _ : Unit) => match ctx.read(inc_phase.view()) {
    Err(error) => Err(error)
    Ok(0) => ctx.read(inc_value.view())
    Ok(_) => match inc_b_ref.val { Some(b) => ctx.read(b.at(())); None => Ok(-1) }
  }))
  let inc_b = must_inc_query(inc_region.query((ctx, _ : Unit) => match inc_a_ref.val {
    Some(a) => ctx.read(a.at(()))
    None => Ok(-1)
  }))
  inc_a_ref.val = Some(inc_a)
  inc_b_ref.val = Some(inc_b)
  ignore(inc_store.read(inc_a.at(())))
  ignore(inc_store.read(inc_b.at(())))
  let before_a = inc_a.memo_debug(())
  let before_b = inc_b.memo_debug(())
  let b_compute_before = inc_b.debug().compute_count
  ignore(inc_store.transaction(tx => tx.set(inc_phase, 1)))
  let inc_out = normalize_incremental_cycle(
    inc_store.read(inc_a.at(())),
    id => if id == inc_a.id() { "A" } else if id == inc_b.id() { "B" } else { "?" },
  )
  let after_a = inc_a.memo_debug(())
  let after_b = inc_b.memo_debug(())
  let a_preserved = match (before_a, after_a) {
    (Some(a), Some(b)) => a.memo_id == b.memo_id &&
      a.verified_at == b.verified_at && a.changed_at == b.changed_at &&
      a.trace_length == b.trace_length
    _ => false
  }
  let b_preserved = match (before_b, after_b) {
    (Some(a), Some(b)) => a.memo_id == b.memo_id &&
      a.verified_at == b.verified_at && a.changed_at == b.changed_at &&
      a.trace_length == b.trace_length
    _ => false
  }
  let b_current_recompute_reached = inc_b.debug().compute_count ==
    b_compute_before + 1 && inc_b.debug().failed_recomputes >= 1
  let clean = inc_a.debug().active_count + inc_b.debug().active_count == 0 &&
    inc_store.debug().last_finished_active_depth == 0
  let passed = fresh_out == "Cycle(A>B>A)" && fresh_out == inc_out &&
    a_preserved && b_preserved && b_current_recompute_reached && clean
  println("cycle_current fresh=\{fresh_out} incremental=\{inc_out} a_preserved=\{a_preserved} b_preserved=\{b_preserved} b_recomputed=\{b_current_recompute_reached} clean=\{clean} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| Cross-Query return to the same QueryCore is allowed when the key differs.
fn cycle_cross_query_unequal_key() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_a_ref : Ref[@fresh.Query[Int, Int]?] = Ref(None)
  let fresh_b_ref : Ref[@fresh.Query[Int, Int]?] = Ref(None)
  let fresh_a = must_fresh_query(
    fresh_region.query((ctx, key : Int) =>
      if key == 0 {
        match fresh_b_ref.val {
          Some(b) => ctx.read(b.at(0))
          None => Ok(-1)
        }
      } else {
        Ok(key)
      }),
  )
  let fresh_b = must_fresh_query(
    fresh_region.query((ctx, _ : Int) => match fresh_a_ref.val {
      Some(a) => ctx.read(a.at(1))
      None => Ok(-1)
    }),
  )
  fresh_a_ref.val = Some(fresh_a)
  fresh_b_ref.val = Some(fresh_b)
  let fresh_value = fresh_store.read(fresh_a.at(0))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_a_ref : Ref[@incremental.Query[Int, Int]?] = Ref(None)
  let inc_b_ref : Ref[@incremental.Query[Int, Int]?] = Ref(None)
  let inc_a = must_inc_query(
    inc_region.query((ctx, key : Int) =>
      if key == 0 {
        match inc_b_ref.val {
          Some(b) => ctx.read(b.at(0))
          None => Ok(-1)
        }
      } else {
        Ok(key)
      }),
  )
  let inc_b = must_inc_query(
    inc_region.query((ctx, _ : Int) => match inc_a_ref.val {
      Some(a) => ctx.read(a.at(1))
      None => Ok(-1)
    }),
  )
  inc_a_ref.val = Some(inc_a)
  inc_b_ref.val = Some(inc_b)
  let inc_value = inc_store.read(inc_a.at(0))
  let clean = inc_a.debug().active_count + inc_b.debug().active_count == 0 &&
    inc_store.debug().last_finished_active_depth == 0
  let passed = fresh_value == Ok(1) && inc_value == Ok(1) &&
    inc_a.debug().memo_count == 2 && inc_b.debug().memo_count == 1 && clean
  println("cycle_cross_query_unequal fresh=\{fresh_value is Ok(1)} incremental=\{inc_value is Ok(1)} a_memos=\{inc_a.debug().memo_count} b_memos=\{inc_b.debug().memo_count} clean=\{clean} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| Sequential duplicate reads and dead cycle branches are not active re-entry.
fn cycle_non_cycles() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_source = must_fresh_source(fresh_region.source(2))
  let fresh_child = must_fresh_query(fresh_region.query((ctx, _ : Unit) => ctx.read(fresh_source.view())))
  let fresh_parent = must_fresh_query(fresh_region.query((ctx, _ : Unit) => match (ctx.read(fresh_child.at(())), ctx.read(fresh_child.at(()))) {
    (Ok(a), Ok(b)) => Ok(a + b)
    (Err(error), _) => Err(error)
    (_, Err(error)) => Err(error)
  }))
  let fresh_cycle_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let fresh_cycle = must_fresh_query(fresh_region.query((ctx, _ : Unit) => match fresh_cycle_ref.val { Some(self) => ctx.read(self.at(())); None => Ok(-1) }))
  fresh_cycle_ref.val = Some(fresh_cycle)
  let fresh_dead = must_fresh_query(fresh_region.query((ctx, _ : Unit) => if false { ctx.read(fresh_cycle.at(())) } else { Ok(9) }))
  let fresh_values = (fresh_store.read(fresh_parent.at(())), fresh_store.read(fresh_dead.at(())))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_source = must_inc_source(inc_region.source(2))
  let inc_child = must_inc_query(inc_region.query((ctx, _ : Unit) => ctx.read(inc_source.view())))
  let inc_parent = must_inc_query(inc_region.query((ctx, _ : Unit) => match (ctx.read(inc_child.at(())), ctx.read(inc_child.at(()))) {
    (Ok(a), Ok(b)) => Ok(a + b)
    (Err(error), _) => Err(error)
    (_, Err(error)) => Err(error)
  }))
  let inc_cycle_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let inc_cycle = must_inc_query(inc_region.query((ctx, _ : Unit) => match inc_cycle_ref.val { Some(self) => ctx.read(self.at(())); None => Ok(-1) }))
  inc_cycle_ref.val = Some(inc_cycle)
  let inc_dead = must_inc_query(inc_region.query((ctx, _ : Unit) => if false { ctx.read(inc_cycle.at(())) } else { Ok(9) }))
  let inc_values = (inc_store.read(inc_parent.at(())), inc_store.read(inc_dead.at(())))
  let clean = inc_child.debug().active_count + inc_parent.debug().active_count +
    inc_cycle.debug().active_count + inc_dead.debug().active_count == 0
  let passed = fresh_values == (Ok(4), Ok(9)) &&
    inc_values == (Ok(4), Ok(9)) && inc_child.debug().compute_count == 1 &&
    clean
  println("cycle_non_cycles sequential=\{inc_values.0 is Ok(4)} dead_branch=\{inc_values.1 is Ok(9)} child_compute=\{inc_child.debug().compute_count} clean=\{clean} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| Store/Region validation precedes recipe invocation and active lookup.
fn cycle_error_precedence() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_other = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let fresh_query = must_fresh_query(fresh_region.query((ctx, _ : Unit) => match fresh_ref.val { Some(self) => ctx.read(self.at(())); None => Ok(-1) }))
  fresh_ref.val = Some(fresh_query)
  let fresh_view = fresh_query.at(())
  let fresh_cross = normalize_fresh_cycle(fresh_other.read(fresh_view), _ => "Q")
  ignore(fresh_region.close())
  let fresh_closed = normalize_fresh_cycle(fresh_store.read(fresh_view), _ => "Q")

  let inc_store = @incremental.Store()
  let inc_other = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let inc_query = must_inc_query(inc_region.query((ctx, _ : Unit) => match inc_ref.val { Some(self) => ctx.read(self.at(())); None => Ok(-1) }))
  inc_ref.val = Some(inc_query)
  let inc_view = inc_query.at(())
  let inc_cross = normalize_incremental_cycle(inc_other.read(inc_view), _ => "Q")
  ignore(inc_region.close())
  let inc_closed = normalize_incremental_cycle(inc_store.read(inc_view), _ => "Q")
  let passed = fresh_cross == "Err(CrossStore)" && fresh_cross == inc_cross &&
    fresh_closed == "Err(ClosedRegion)" && fresh_closed == inc_closed &&
    inc_query.debug().active_count == 0 && inc_query.debug().compute_count == 0
  println("cycle_precedence cross=\{inc_cross} closed=\{inc_closed} compute=\{inc_query.debug().compute_count} passed=\{passed}")
  passed
}

///| Runs only the cycle-variable evidence; main.mbt already runs #462 acyclic parity.
fn run_cycle_scenarios() -> Bool {
  let direct = cycle_direct_self()
  let finite = cycle_finite_recursion()
  let same_query = cycle_same_query_keys()
  let mutual = cycle_mutual()
  let recovery = cycle_introduction_and_recovery()
  let old_trace = cycle_old_trace_branch_away()
  let current = cycle_current_transition()
  let unequal_key = cycle_cross_query_unequal_key()
  let non_cycles = cycle_non_cycles()
  let precedence = cycle_error_precedence()
  let passed = direct && finite && same_query && mutual && recovery &&
    old_trace && current && unequal_key && non_cycles && precedence
  println("cycle_state direct=\{direct} finite=\{finite} same_query=\{same_query} mutual=\{mutual} recovery=\{recovery} old_trace=\{old_trace} current=\{current} unequal_key=\{unequal_key} non_cycles=\{non_cycles} precedence=\{precedence}")
  println("cycle constrained verdict: \{if passed { "PASS" } else { "FAIL" }}")
  passed
}
