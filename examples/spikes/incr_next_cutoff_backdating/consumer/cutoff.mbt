///| Value whose contract permits only root readers to inspect generation.
struct SemanticDoc {
  semantic : Int
  generation : Int
}

impl @fresh.CutoffEq for SemanticDoc with fn cutoff_equal(self, other) {
  self.semantic == other.semantic
}

impl @incremental.CutoffEq for SemanticDoc with fn cutoff_equal(self, other) {
  self.semantic == other.semantic
}

///| Non-Eq result whose downstream contract excludes operational generation.
struct PatternLike {
  value_revision : Int
  fingerprint_revision : Int
  generation : Int
  render : (Int) -> Int
}

impl @fresh.CutoffEq for PatternLike with fn cutoff_equal(self, other) {
  self.value_revision == other.value_revision &&
  self.fingerprint_revision == other.fingerprint_revision
}

impl @incremental.CutoffEq for PatternLike with fn cutoff_equal(self, other) {
  self.value_revision == other.value_revision &&
  self.fingerprint_revision == other.fingerprint_revision
}

///| Custom Eq is intentionally unsound for a downstream reading generation.
struct UnsoundEqValue {
  semantic : Int
  generation : Int
}

impl Eq for UnsoundEqValue with fn equal(self, other) {
  self.semantic == other.semantic
}

///| Deliberately non-transitive local-nearness relation.
struct NearValue {
  value : Int
}

impl @fresh.CutoffEq for NearValue with fn cutoff_equal(self, other) {
  let delta = self.value - other.value
  delta >= -1 && delta <= 1
}

impl @incremental.CutoffEq for NearValue with fn cutoff_equal(self, other) {
  let delta = self.value - other.value
  delta >= -1 && delta <= 1
}

///|
fn[T] must_fresh_read(result : Result[T, @fresh.ReadError]) -> T {
  match result { Ok(value) => value; Err(_) => abort("fresh cutoff read") }
}

///|
fn[T] must_inc_read(result : Result[T, @incremental.ReadError]) -> T {
  match result { Ok(value) => value; Err(_) => abort("incremental cutoff read") }
}

///|
fn int_values(values : Array[Int]) -> String {
  values.map(value => value.to_string()).join(",")
}

///|
fn same_memo(
  left : @incremental.MemoDebug,
  right : @incremental.MemoDebug,
) -> Bool {
  left.memo_id == right.memo_id && left.trace_length == right.trace_length &&
  left.verified_at == right.verified_at && left.changed_at == right.changed_at
}

///|
fn eq_backdating_fresh() -> Array[Int] {
  let store = @fresh.Store()
  let region = must_fresh_region(store.region())
  let input = must_fresh_source(region.source(2))
  let unrelated = must_fresh_source(region.source(100))
  let parity = must_fresh_query(region.query_eq((ctx, _ : Unit) =>
    match ctx.read(input.view()) { Ok(value) => Ok(value % 2); Err(error) => Err(error) }))
  let parent = must_fresh_query(region.query_always_changed((ctx, _ : Unit) =>
    ctx.read(parity.at(()))))
  let values = [must_fresh_read(store.read(parent.at(())))]
  values.push(must_fresh_read(store.read(parent.at(()))))
  ignore(store.transaction(tx => tx.set(unrelated, 101)))
  values.push(must_fresh_read(store.read(parent.at(()))))
  ignore(store.transaction(tx => tx.set(input, 4)))
  values.push(must_fresh_read(store.read(parent.at(()))))
  ignore(store.transaction(tx => tx.set(input, 5)))
  values.push(must_fresh_read(store.read(parent.at(()))))
  ignore(region.close())
  values
}

///|
fn eq_backdating_incremental() -> (Array[Int], Bool) {
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let input = must_inc_source(region.source(2))
  let unrelated = must_inc_source(region.source(100))
  let parity = must_inc_query(region.query_eq((ctx, _ : Unit) =>
    match ctx.read(input.view()) { Ok(value) => Ok(value % 2); Err(error) => Err(error) }))
  let parent = must_inc_query(region.query_always_changed((ctx, _ : Unit) =>
    ctx.read(parity.at(()))))
  let values = [must_inc_read(store.read(parent.at(())))]
  let initial = match parity.memo_debug(()) { Some(value) => value; None => abort("initial parity memo") }
  values.push(must_inc_read(store.read(parent.at(()))))
  ignore(store.transaction(tx => tx.set(unrelated, 101)))
  values.push(must_inc_read(store.read(parent.at(()))))
  let after_green = parity.debug()
  ignore(store.transaction(tx => tx.set(input, 4)))
  values.push(must_inc_read(store.read(parent.at(()))))
  let equivalent = match parity.memo_debug(()) { Some(value) => value; None => abort("equivalent parity memo") }
  let after_equivalent = parity.debug()
  let parent_after_equivalent = parent.debug()
  ignore(store.transaction(tx => tx.set(input, 5)))
  values.push(must_inc_read(store.read(parent.at(()))))
  let changed = match parity.memo_debug(()) { Some(value) => value; None => abort("changed parity memo") }
  let after_changed = parity.debug()
  let parent_after_changed = parent.debug()
  let passed = initial.memo_id == equivalent.memo_id &&
    equivalent.verified_at.value() > initial.verified_at.value() &&
    equivalent.changed_at == initial.changed_at &&
    changed.memo_id == initial.memo_id &&
    changed.changed_at.value() > equivalent.changed_at.value() &&
    after_green.compute_count == 1 && after_green.cutoff_calls == 0 &&
    after_green.green_verifications == 1 &&
    after_equivalent.compute_count == 2 &&
    after_equivalent.cutoff_calls == 1 &&
    parent_after_equivalent.compute_count == 1 &&
    after_changed.compute_count == 3 &&
    after_changed.cutoff_calls == 2 &&
    parent_after_changed.compute_count == 2
  println("cutoff_eq values=\{int_values(values)} q_compute=\{after_changed.compute_count} cutoff=\{after_changed.cutoff_calls} parent=\{parent_after_changed.compute_count} passed=\{passed}")
  ignore(region.close())
  (values, passed)
}

///| AlwaysChanged preserves #463 propagation even for equal outputs.
fn always_changed_policy() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_input = must_fresh_source(fresh_region.source(2))
  let fresh_q = must_fresh_query(fresh_region.query_always_changed((ctx, _ : Unit) =>
    match ctx.read(fresh_input.view()) { Ok(value) => Ok(value % 2); Err(error) => Err(error) }))
  let fresh_parent = must_fresh_query(fresh_region.query_always_changed((ctx, _ : Unit) =>
    ctx.read(fresh_q.at(()))))
  let fresh_values = [must_fresh_read(fresh_store.read(fresh_parent.at(())))]
  ignore(fresh_store.transaction(tx => tx.set(fresh_input, 4)))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_parent.at(()))))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_input = must_inc_source(inc_region.source(2))
  let inc_q = must_inc_query(inc_region.query_always_changed((ctx, _ : Unit) =>
    match ctx.read(inc_input.view()) { Ok(value) => Ok(value % 2); Err(error) => Err(error) }))
  let inc_parent = must_inc_query(inc_region.query_always_changed((ctx, _ : Unit) =>
    ctx.read(inc_q.at(()))))
  let inc_values = [must_inc_read(inc_store.read(inc_parent.at(())))]
  let before = match inc_q.memo_debug(()) { Some(value) => value; None => abort("always memo") }
  ignore(inc_store.transaction(tx => tx.set(inc_input, 4)))
  inc_values.push(must_inc_read(inc_store.read(inc_parent.at(()))))
  let after = match inc_q.memo_debug(()) { Some(value) => value; None => abort("always memo after") }
  let passed = fresh_values == inc_values && inc_q.debug().cutoff_calls == 1 &&
    inc_q.debug().compute_count == 2 && inc_parent.debug().compute_count == 2 &&
    after.changed_at.value() > before.changed_at.value()
  println("cutoff_always q=\{inc_q.debug().compute_count} parent=\{inc_parent.debug().compute_count} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| Backdating replaces a dynamic trace even while preserving changed_at.
fn dynamic_trace_backdating() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_mode = must_fresh_source(fresh_region.source(0))
  let fresh_left = must_fresh_source(fresh_region.source(2))
  let fresh_right = must_fresh_source(fresh_region.source(4))
  let fresh_q = must_fresh_query(fresh_region.query_eq((ctx, _ : Unit) =>
    match ctx.read(fresh_mode.view()) {
      Err(error) => Err(error)
      Ok(mode) => if mode == 0 {
        match ctx.read(fresh_left.view()) { Ok(value) => Ok(value % 2); Err(error) => Err(error) }
      } else {
        match ctx.read(fresh_right.view()) { Ok(value) => Ok(value % 2); Err(error) => Err(error) }
      }
    }))
  let fresh_parent = must_fresh_query(fresh_region.query_always_changed((ctx, _ : Unit) => ctx.read(fresh_q.at(()))))
  let fresh_values = [must_fresh_read(fresh_store.read(fresh_parent.at(())))]
  ignore(fresh_store.transaction(tx => tx.set(fresh_mode, 1)))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_parent.at(()))))
  ignore(fresh_store.transaction(tx => tx.set(fresh_left, 3)))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_parent.at(()))))
  ignore(fresh_store.transaction(tx => tx.set(fresh_right, 5)))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_parent.at(()))))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_mode = must_inc_source(inc_region.source(0))
  let inc_left = must_inc_source(inc_region.source(2))
  let inc_right = must_inc_source(inc_region.source(4))
  let inc_q = must_inc_query(inc_region.query_eq((ctx, _ : Unit) =>
    match ctx.read(inc_mode.view()) {
      Err(error) => Err(error)
      Ok(mode) => if mode == 0 {
        match ctx.read(inc_left.view()) { Ok(value) => Ok(value % 2); Err(error) => Err(error) }
      } else {
        match ctx.read(inc_right.view()) { Ok(value) => Ok(value % 2); Err(error) => Err(error) }
      }
    }))
  let inc_parent = must_inc_query(inc_region.query_always_changed((ctx, _ : Unit) => ctx.read(inc_q.at(()))))
  let inc_values = [must_inc_read(inc_store.read(inc_parent.at(())))]
  let initial = match inc_q.memo_debug(()) { Some(value) => value; None => abort("dynamic initial") }
  ignore(inc_store.transaction(tx => tx.set(inc_mode, 1)))
  inc_values.push(must_inc_read(inc_store.read(inc_parent.at(()))))
  let switched = match inc_q.memo_debug(()) { Some(value) => value; None => abort("dynamic switched") }
  let compute_after_switch = inc_q.debug().compute_count
  ignore(inc_store.transaction(tx => tx.set(inc_left, 3)))
  inc_values.push(must_inc_read(inc_store.read(inc_parent.at(()))))
  let compute_after_left = inc_q.debug().compute_count
  ignore(inc_store.transaction(tx => tx.set(inc_right, 5)))
  inc_values.push(must_inc_read(inc_store.read(inc_parent.at(()))))
  let passed = fresh_values == inc_values && switched.changed_at == initial.changed_at &&
    switched.verified_at.value() > initial.verified_at.value() &&
    switched.trace_length == 2 && compute_after_switch == 2 &&
    compute_after_left == 2 && inc_q.debug().compute_count == 3 &&
    inc_q.debug().cutoff_calls == 2 && inc_parent.debug().compute_count == 2
  println("cutoff_dynamic values=\{int_values(inc_values)} q=\{inc_q.debug().compute_count} left_green=\{compute_after_left == compute_after_switch} parent=\{inc_parent.debug().compute_count} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| Under a restricted observer contract, equivalent values replace memo.value.
fn newest_value_and_consecutive_backdating() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_input = must_fresh_source(fresh_region.source(SemanticDoc::{ semantic: 7, generation: 0 }))
  let fresh_q = must_fresh_query(fresh_region.query_type_owned((ctx, _ : Unit) => ctx.read(fresh_input.view())))
  let fresh_parent = must_fresh_query(fresh_region.query_always_changed((ctx, _ : Unit) =>
    match ctx.read(fresh_q.at(())) { Ok(value) => Ok(value.semantic); Err(error) => Err(error) }))
  let fresh_values = [must_fresh_read(fresh_store.read(fresh_parent.at(())))]
  for generation = 1; generation <= 3; generation = generation + 1 {
    ignore(fresh_store.transaction(tx => tx.set(fresh_input, SemanticDoc::{ semantic: 7, generation })))
    fresh_values.push(must_fresh_read(fresh_store.read(fresh_parent.at(()))))
  }
  let fresh_latest = must_fresh_read(fresh_store.read(fresh_q.at(()))).generation
  ignore(fresh_store.transaction(tx => tx.set(fresh_input, SemanticDoc::{ semantic: 8, generation: 4 })))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_parent.at(()))))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_input = must_inc_source(inc_region.source(SemanticDoc::{ semantic: 7, generation: 0 }))
  let inc_q = must_inc_query(inc_region.query_type_owned((ctx, _ : Unit) => ctx.read(inc_input.view())))
  let inc_parent = must_inc_query(inc_region.query_always_changed((ctx, _ : Unit) =>
    match ctx.read(inc_q.at(())) { Ok(value) => Ok(value.semantic); Err(error) => Err(error) }))
  let inc_values = [must_inc_read(inc_store.read(inc_parent.at(())))]
  let initial = match inc_q.memo_debug(()) { Some(value) => value; None => abort("doc initial") }
  for generation = 1; generation <= 3; generation = generation + 1 {
    ignore(inc_store.transaction(tx => tx.set(inc_input, SemanticDoc::{ semantic: 7, generation })))
    inc_values.push(must_inc_read(inc_store.read(inc_parent.at(()))))
  }
  let equivalent = match inc_q.memo_debug(()) { Some(value) => value; None => abort("doc equivalent") }
  let inc_latest = must_inc_read(inc_store.read(inc_q.at(()))).generation
  ignore(inc_store.transaction(tx => tx.set(inc_input, SemanticDoc::{ semantic: 8, generation: 4 })))
  inc_values.push(must_inc_read(inc_store.read(inc_parent.at(()))))
  let changed = match inc_q.memo_debug(()) { Some(value) => value; None => abort("doc changed") }
  let passed = fresh_values == inc_values && fresh_latest == 3 && inc_latest == 3 &&
    equivalent.changed_at == initial.changed_at &&
    equivalent.verified_at.value() > initial.verified_at.value() &&
    equivalent.memo_id == initial.memo_id && changed.memo_id == initial.memo_id &&
    changed.changed_at.value() > equivalent.changed_at.value() &&
    inc_q.debug().compute_count == 5 && inc_q.debug().cutoff_calls == 4 &&
    inc_parent.debug().compute_count == 2
  println("cutoff_latest generation=\{inc_latest} q=\{inc_q.debug().compute_count} parent=\{inc_parent.debug().compute_count} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| A restricted-observer non-Eq value uses two revisions without HasChangedAt.
fn type_owned_non_eq() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_input = must_fresh_source(fresh_region.source(PatternLike::{
    value_revision: 1, fingerprint_revision: 10, generation: 0, render: value => value + 10,
  }))
  let fresh_q = must_fresh_query(fresh_region.query_type_owned((ctx, _ : Unit) => ctx.read(fresh_input.view())))
  let fresh_parent = must_fresh_query(fresh_region.query_always_changed((ctx, _ : Unit) =>
    match ctx.read(fresh_q.at(())) { Ok(value) => Ok((value.render)(0)); Err(error) => Err(error) }))
  let fresh_values = [must_fresh_read(fresh_store.read(fresh_parent.at(())))]
  ignore(fresh_store.transaction(tx => tx.set(fresh_input, PatternLike::{
    value_revision: 1, fingerprint_revision: 10, generation: 1, render: value => value + 10,
  })))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_parent.at(()))))
  let fresh_generation = must_fresh_read(fresh_store.read(fresh_q.at(()))).generation
  ignore(fresh_store.transaction(tx => tx.set(fresh_input, PatternLike::{
    value_revision: 1, fingerprint_revision: 11, generation: 2, render: value => value + 11,
  })))
  fresh_values.push(must_fresh_read(fresh_store.read(fresh_parent.at(()))))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_input = must_inc_source(inc_region.source(PatternLike::{
    value_revision: 1, fingerprint_revision: 10, generation: 0, render: value => value + 10,
  }))
  let inc_q = must_inc_query(inc_region.query_type_owned((ctx, _ : Unit) => ctx.read(inc_input.view())))
  let inc_parent = must_inc_query(inc_region.query_always_changed((ctx, _ : Unit) =>
    match ctx.read(inc_q.at(())) { Ok(value) => Ok((value.render)(0)); Err(error) => Err(error) }))
  let inc_values = [must_inc_read(inc_store.read(inc_parent.at(())))]
  let initial = match inc_q.memo_debug(()) { Some(value) => value; None => abort("pattern initial") }
  ignore(inc_store.transaction(tx => tx.set(inc_input, PatternLike::{
    value_revision: 1, fingerprint_revision: 10, generation: 1, render: value => value + 10,
  })))
  inc_values.push(must_inc_read(inc_store.read(inc_parent.at(()))))
  let equivalent = match inc_q.memo_debug(()) { Some(value) => value; None => abort("pattern equivalent") }
  let inc_generation = must_inc_read(inc_store.read(inc_q.at(()))).generation
  ignore(inc_store.transaction(tx => tx.set(inc_input, PatternLike::{
    value_revision: 1, fingerprint_revision: 11, generation: 2, render: value => value + 11,
  })))
  inc_values.push(must_inc_read(inc_store.read(inc_parent.at(()))))
  let changed = match inc_q.memo_debug(()) { Some(value) => value; None => abort("pattern changed") }
  let passed = fresh_values == inc_values && fresh_generation == 1 && inc_generation == 1 &&
    equivalent.changed_at == initial.changed_at &&
    changed.changed_at.value() > equivalent.changed_at.value() &&
    inc_q.debug().cutoff_calls == 2 && inc_parent.debug().compute_count == 2
  println("cutoff_type_owned values=\{int_values(inc_values)} generation=\{inc_generation} passed=\{passed}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  passed
}

///| Cycle and ReadError exits never evaluate cutoff or mutate an old memo.
fn cutoff_cycle_and_failure() -> Bool {
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let initial_cycle_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let initial_cycle_query = must_inc_query(region.query_eq((ctx, _ : Unit) =>
    match initial_cycle_ref.val { Some(self) => ctx.read(self.at(())); None => Ok(-1) }))
  initial_cycle_ref.val = Some(initial_cycle_query)
  let initial_cycle = store.read(initial_cycle_query.at(()))
  let initial_cycle_clean = initial_cycle is Err(@incremental.ReadError::Cycle(_)) &&
    initial_cycle_query.debug().memo_count == 0 && initial_cycle_query.debug().cutoff_calls == 0
  let cycle_mode = must_inc_source(region.source(false))
  let cycle_value = must_inc_source(region.source(2))
  let query_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let query = must_inc_query(region.query_eq((ctx, _ : Unit) =>
    match ctx.read(cycle_mode.view()) {
      Err(error) => Err(error)
      Ok(true) => match query_ref.val { Some(self) => ctx.read(self.at(())); None => Ok(-1) }
      Ok(false) => match ctx.read(cycle_value.view()) { Ok(value) => Ok(value % 2); Err(error) => Err(error) }
    }))
  query_ref.val = Some(query)
  let initial_value = must_inc_read(store.read(query.at(())))
  let initial_memo = match query.memo_debug(()) { Some(value) => value; None => abort("cycle cutoff initial") }
  let initial_calls = query.debug().cutoff_calls
  ignore(store.transaction(tx => tx.set(cycle_mode, true)))
  let cycle = store.read(query.at(()))
  let cycle_memo = match query.memo_debug(()) { Some(value) => value; None => abort("cycle cutoff preserved") }
  let cycle_debug = query.debug()
  ignore(store.transaction(tx => {
    ignore(tx.set(cycle_mode, false))
    tx.set(cycle_value, 4)
  }))
  let recovered_value = must_inc_read(store.read(query.at(())))
  let recovered_memo = match query.memo_debug(()) { Some(value) => value; None => abort("cycle cutoff recovered") }

  let fail_mode = must_inc_source(region.source(true))
  let fail_query = must_inc_query(region.query_eq((ctx, _ : Unit) =>
    match ctx.read(fail_mode.view()) {
      Err(error) => Err(error)
      Ok(true) => Err(@incremental.ReadError::ClosedRegion(generation=region.generation()))
      Ok(false) => Ok(7)
    }))
  let initial_failure = store.read(fail_query.at(()))
  let initial_failure_clean = fail_query.debug().memo_count == 0 && fail_query.debug().cutoff_calls == 0
  ignore(store.transaction(tx => tx.set(fail_mode, false)))
  let success = store.read(fail_query.at(()))
  let success_memo = match fail_query.memo_debug(()) { Some(value) => value; None => abort("failure cutoff success") }
  ignore(store.transaction(tx => tx.set(fail_mode, true)))
  let failed_recompute = store.read(fail_query.at(()))
  let failed_memo = match fail_query.memo_debug(()) { Some(value) => value; None => abort("failure cutoff preserved") }
  let passed = initial_cycle_clean && initial_value == 0 && cycle is Err(@incremental.ReadError::Cycle(_)) &&
    same_memo(cycle_memo, initial_memo) && cycle_debug.cutoff_calls == initial_calls &&
    recovered_value == 0 && recovered_memo.memo_id == initial_memo.memo_id &&
    recovered_memo.changed_at == initial_memo.changed_at && query.debug().cutoff_calls == initial_calls + 1 &&
    initial_failure is Err(@incremental.ReadError::ClosedRegion(_)) && initial_failure_clean &&
    success is Ok(7) && failed_recompute is Err(@incremental.ReadError::ClosedRegion(_)) &&
    same_memo(failed_memo, success_memo) && fail_query.debug().cutoff_calls == 0
  println("cutoff_errors cycle_calls=\{query.debug().cutoff_calls} failure_calls=\{fail_query.debug().cutoff_calls} passed=\{passed}")
  ignore(region.close())
  passed
}

///| Unsound relations are expected Fresh/Incremental divergences, not passes.
fn unsound_cutoff_counterexamples() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = must_fresh_region(fresh_store.region())
  let fresh_value = must_fresh_source(fresh_region.source(UnsoundEqValue::{ semantic: 1, generation: 0 }))
  let fresh_q = must_fresh_query(fresh_region.query_eq((ctx, _ : Unit) => ctx.read(fresh_value.view())))
  let fresh_parent = must_fresh_query(fresh_region.query_always_changed((ctx, _ : Unit) =>
    match ctx.read(fresh_q.at(())) { Ok(value) => Ok(value.generation); Err(error) => Err(error) }))
  ignore(fresh_store.read(fresh_parent.at(())))
  ignore(fresh_store.transaction(tx => tx.set(fresh_value, UnsoundEqValue::{ semantic: 1, generation: 1 })))
  let fresh_generation = must_fresh_read(fresh_store.read(fresh_parent.at(())))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_value = must_inc_source(inc_region.source(UnsoundEqValue::{ semantic: 1, generation: 0 }))
  let inc_q = must_inc_query(inc_region.query_eq((ctx, _ : Unit) => ctx.read(inc_value.view())))
  let inc_parent = must_inc_query(inc_region.query_always_changed((ctx, _ : Unit) =>
    match ctx.read(inc_q.at(())) { Ok(value) => Ok(value.generation); Err(error) => Err(error) }))
  ignore(inc_store.read(inc_parent.at(())))
  ignore(inc_store.transaction(tx => tx.set(inc_value, UnsoundEqValue::{ semantic: 1, generation: 1 })))
  let inc_generation = must_inc_read(inc_store.read(inc_parent.at(())))

  let near_fresh_store = @fresh.Store()
  let near_fresh_region = must_fresh_region(near_fresh_store.region())
  let near_fresh_source = must_fresh_source(near_fresh_region.source(NearValue::{ value: 0 }))
  let near_fresh_q = must_fresh_query(near_fresh_region.query_type_owned((ctx, _ : Unit) => ctx.read(near_fresh_source.view())))
  let near_fresh_parent = must_fresh_query(near_fresh_region.query_always_changed((ctx, _ : Unit) =>
    match ctx.read(near_fresh_q.at(())) { Ok(value) => Ok(value.value); Err(error) => Err(error) }))
  let near_fresh = [must_fresh_read(near_fresh_store.read(near_fresh_parent.at(())))]
  for value = 1; value <= 2; value = value + 1 {
    ignore(near_fresh_store.transaction(tx => tx.set(near_fresh_source, NearValue::{ value })))
    near_fresh.push(must_fresh_read(near_fresh_store.read(near_fresh_parent.at(()))))
  }

  let near_inc_store = @incremental.Store()
  let near_inc_region = must_inc_region(near_inc_store.region())
  let near_inc_source = must_inc_source(near_inc_region.source(NearValue::{ value: 0 }))
  let near_inc_q = must_inc_query(near_inc_region.query_type_owned((ctx, _ : Unit) => ctx.read(near_inc_source.view())))
  let near_inc_parent = must_inc_query(near_inc_region.query_always_changed((ctx, _ : Unit) =>
    match ctx.read(near_inc_q.at(())) { Ok(value) => Ok(value.value); Err(error) => Err(error) }))
  let near_inc = [must_inc_read(near_inc_store.read(near_inc_parent.at(())))]
  for value = 1; value <= 2; value = value + 1 {
    ignore(near_inc_store.transaction(tx => tx.set(near_inc_source, NearValue::{ value })))
    near_inc.push(must_inc_read(near_inc_store.read(near_inc_parent.at(()))))
  }
  let expected = fresh_generation == 1 && inc_generation == 0 &&
    near_fresh == [0, 1, 2] && near_inc == [0, 0, 0]
  println("excluded_unsound_cutoff ignored_field=\{fresh_generation}->\{inc_generation} near_fresh=\{int_values(near_fresh)} near_incremental=\{int_values(near_inc)} expected_divergence=\{expected}")
  ignore(fresh_region.close())
  ignore(inc_region.close())
  ignore(near_fresh_region.close())
  ignore(near_inc_region.close())
  expected
}

///| Runs typed cutoff, failure, cycle, and excluded unsound evidence.
fn run_cutoff_scenarios() -> Bool {
  let fresh = eq_backdating_fresh()
  let incremental = eq_backdating_incremental()
  let eq = fresh == incremental.0 && incremental.1
  let always = always_changed_policy()
  let dynamic = dynamic_trace_backdating()
  let latest = newest_value_and_consecutive_backdating()
  let type_owned = type_owned_non_eq()
  let errors = cutoff_cycle_and_failure()
  let excluded_unsound = unsound_cutoff_counterexamples()
  let passed = eq && always && dynamic && latest && type_owned && errors && excluded_unsound
  println("cutoff_state eq=\{eq} always=\{always} dynamic=\{dynamic} latest=\{latest} type_owned=\{type_owned} errors=\{errors} excluded_unsound=\{excluded_unsound}")
  passed
}
