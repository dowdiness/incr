///|
/// A consumer can read A without knowing the hidden key type K.
fn[V] consume(
  store : @provider.Store,
  view : @provider.View[V],
) -> Result[V, @provider.ReadError] {
  store.read(view)
}

///|
/// B necessarily retains K in the consumer signature.
fn[K : Hash + Eq, V] consume_explicit(
  store : @provider.Store,
  view : @provider.ExplicitView[K, V],
) -> Result[V, @provider.ReadError] {
  store.read_explicit(view)
}

///|
/// Prints one QueryId in a stable compact form.
fn query_id_text(id : @provider.QueryId) -> String {
  "store=\{id.store_id().value()}/query=\{id.sequence()}"
}

///|
/// Prints one ViewHandleId in a stable compact form.
fn view_id_text(id : @provider.ViewHandleId) -> String {
  "store=\{id.store_id().value()}/view=\{id.sequence()}"
}

///|
/// Formats the prototype's structured errors without a Show contract.
fn read_error_text(error : @provider.ReadError) -> String {
  match error {
    @provider.ReadError::CrossStore(view_store~, reader_store~) =>
      "CrossStore(view=\{view_store.value()},reader=\{reader_store.value()})"
    @provider.ReadError::ClosedRegion(generation~) =>
      "ClosedRegion(region=\{generation.region_id().sequence()},epoch=\{generation.epoch()})"
  }
}

///|
/// Formats the Int-valued reads used by the evidence shell.
fn int_result_text(result : Result[Int, @provider.ReadError]) -> String {
  match result {
    Ok(value) => "Ok(\{value})"
    Err(error) => "Err(\{read_error_text(error)})"
  }
}

///|
/// Proves lazy at, shared A/B memo identity, eviction, and rematerialization.
fn probe_recipe_and_memo() -> Bool {
  let store = @provider.Store()
  let region = store.region()
  let compute_runs = Ref(0)
  let query = region.query((key : Int) => {
    compute_runs.val = compute_runs.val + 1
    key * 2
  })
  let first = query.at(3)
  let second = query.at(3)
  let explicit = query.at_explicit(3)
  let before = query.debug()
  let first_value = consume(store, first)
  let second_value = consume(store, second)
  let explicit_value = consume_explicit(store, explicit)
  let shared = query.debug()
  let first_memo = query.memo_id(3)
  query.evict(3)
  let rematerialized_value = consume(store, first)
  let second_memo = query.memo_id(3)
  let after = query.debug()
  let memo_changed = match (first_memo, second_memo) {
    (Some(old_id), Some(new_id)) =>
      old_id != new_id &&
      old_id.query_id() == query.debug().query_id &&
      new_id.query_id() == query.debug().query_id
    _ => false
  }
  let passed = before.memo_count == 0 &&
    before.lookup_count == 0 &&
    before.materialization_count == 0 &&
    first.query_id() == before.query_id &&
    explicit.query_id() == before.query_id &&
    first.handle_id() != second.handle_id() &&
    first_value == Ok(6) &&
    second_value == Ok(6) &&
    explicit_value == Ok(6) &&
    shared.memo_count == 1 &&
    shared.materialization_count == 1 &&
    compute_runs.val == 2 &&
    memo_changed &&
    rematerialized_value == Ok(6) &&
    after.memo_count == 1 &&
    after.materialization_count == 2 &&
    after.eviction_count == 1
  println("scenario=recipe_and_memo")
  println("  query_id=\{query_id_text(before.query_id)}")
  println(
    "  view_handles=[\{view_id_text(first.handle_id())}, \{view_id_text(second.handle_id())}, \{view_id_text(explicit.handle_id())}]",
  )
  println(
    "  at_state=memos:\{before.memo_count},lookups:\{before.lookup_count},materializations:\{before.materialization_count}",
  )
  println(
    "  shared_state=memos:\{shared.memo_count},materializations:\{shared.materialization_count},compute_runs_before_evict:1",
  )
  println(
    "  rematerialized_state=memos:\{after.memo_count},materializations:\{after.materialization_count},evictions:\{after.eviction_count},compute_runs:\{compute_runs.val}",
  )
  println("  memo_identity_changed=\{memo_changed} passed=\{passed}")
  region.close()
  passed
}

///|
/// A single View[V] consumer accepts invocations whose hidden K types differ.
fn probe_key_erasure_a_and_b_baseline() -> Bool {
  let store = @provider.Store()
  let region = store.region()
  let int_key_query = region.query((key : Int) => key + 10)
  let string_key_query = region.query((key : String) => key.length())
  let erased : Array[@provider.View[Int]] = [
    int_key_query.at(2),
    string_key_query.at("abc"),
  ]
  let erased_values = erased.map(view => consume(store, view))
  let int_explicit = int_key_query.at_explicit(2)
  let string_explicit = string_key_query.at_explicit("abc")
  let explicit_values = (
    consume_explicit(store, int_explicit),
    consume_explicit(store, string_explicit),
  )
  let passed = erased_values == [Ok(12), Ok(3)] &&
    explicit_values == (Ok(12), Ok(3))
  println("scenario=key_erasure")
  let erased_text = erased_values.map(int_result_text).join(",")
  let explicit_text = "\{int_result_text(explicit_values.0)},\{int_result_text(explicit_values.1)}"
  println(
    "  A_public_type=Array[View[Int]] hidden_key_types=[Int,String] values=[\{erased_text}]",
  )
  println(
    "  B_public_types=[ExplicitView[Int,Int],ExplicitView[String,Int]] values=[\{explicit_text}]",
  )
  println("  passed=\{passed}")
  region.close()
  passed
}

///|
/// Cross-store rejection precedes A recipe invocation and Query lookup.
fn probe_cross_store_metadata_first() -> Bool {
  let left = @provider.Store()
  let left_region = left.region()
  let right = @provider.Store()
  let query = left_region.query((key : Int) => key + 1)
  let view = query.at(41)
  let query_before = query.debug()
  let right_before = right.debug()
  let result = right.read(view)
  let query_after = query.debug()
  let right_after = right.debug()
  let passed = match result {
    Err(@provider.ReadError::CrossStore(view_store~, reader_store~)) =>
      view_store != reader_store &&
      query_before.lookup_count == query_after.lookup_count &&
      query_before.materialization_count == query_after.materialization_count &&
      right_before.recipe_invocations == right_after.recipe_invocations &&
      right_after.cross_store_rejections == 1
    _ => false
  }
  println("scenario=cross_store_metadata_first")
  let result_text = match result {
    Ok(value) => "Ok(\{value})"
    Err(error) => "Err(\{read_error_text(error)})"
  }
  println("  result=\{result_text}")
  println(
    "  query_lookup_before_after=\{query_before.lookup_count}/\{query_after.lookup_count}",
  )
  println(
    "  recipe_invocations_before_after=\{right_before.recipe_invocations}/\{right_after.recipe_invocations}",
  )
  println("  rejections=\{right_after.cross_store_rejections} passed=\{passed}")
  left_region.close()
  passed
}

///|
/// Region close invalidates a surviving View and clears Query state.
fn probe_close_with_surviving_view() -> Bool {
  let store = @provider.Store()
  let region = store.region()
  let query = region.query((key : Int) => key * 3)
  let view = query.at(7)
  let explicit = query.at_explicit(7)
  ignore(store.read(view))
  ignore(store.read_explicit(explicit))
  let before = query.debug()
  region.close()
  let after = query.debug()
  let store_before_read = store.debug()
  let result = store.read(view)
  let explicit_result = store.read_explicit(explicit)
  let store_after_read = store.debug()
  let a_closed = match result {
    Err(@provider.ReadError::ClosedRegion(generation~)) =>
      generation == before.creation_generation
    _ => false
  }
  let b_closed = match explicit_result {
    Err(@provider.ReadError::ClosedRegion(generation~)) =>
      generation == before.creation_generation
    _ => false
  }
  let passed = before.memo_count == 1 &&
    after.closed &&
    after.memo_count == 0 &&
    a_closed &&
    b_closed &&
    store_before_read.recipe_invocations == store_after_read.recipe_invocations &&
    store_after_read.closed_region_rejections == 2
  println("scenario=region_close")
  println(
    "  generation=region:\{before.creation_generation.region_id().sequence()}/epoch:\{before.creation_generation.epoch()}",
  )
  println("  before=memos:\{before.memo_count},closed:\{before.closed}")
  println("  after=memos:\{after.memo_count},closed:\{after.closed}")
  println(
    "  surviving_A_result=\{int_result_text(result)} surviving_B_result=\{int_result_text(explicit_result)}",
  )
  println(
    "  recipe_invocations_unchanged=\{store_before_read.recipe_invocations == store_after_read.recipe_invocations} passed=\{passed}",
  )
  passed
}

///|
/// Both representations expose the same hash/equality stability requirement.
fn probe_mutable_key_counterexample() -> Bool {
  let store_a = @provider.Store()
  let region_a = store_a.region()
  let key_a = @provider.MutableKey(1)
  let query_a = region_a.query((key : @provider.MutableKey) => key.value())
  let view_a = query_a.at(key_a)
  let a_before_value = store_a.read(view_a)
  let a_before = query_a.debug()
  key_a.set(2)
  let a_after_value = store_a.read(view_a)
  let a_after = query_a.debug()

  let store_b = @provider.Store()
  let region_b = store_b.region()
  let key_b = @provider.MutableKey(1)
  let query_b = region_b.query((key : @provider.MutableKey) => key.value())
  let view_b = query_b.at_explicit(key_b)
  let b_before_value = store_b.read_explicit(view_b)
  let b_before = query_b.debug()
  key_b.set(2)
  let b_after_value = store_b.read_explicit(view_b)
  let b_after = query_b.debug()

  let a_instability = a_before_value == Ok(1) &&
    a_after_value == Ok(2) &&
    a_before.materialization_count == 1 &&
    a_after.materialization_count == 2
  let b_instability = b_before_value == Ok(1) &&
    b_after_value == Ok(2) &&
    b_before.materialization_count == 1 &&
    b_after.materialization_count == 2
  let passed = a_instability && b_instability
  println("scenario=mutable_key_counterexample")
  println(
    "  A=value:\{int_result_text(a_before_value)}->\{int_result_text(a_after_value)},memos:\{a_before.memo_count}->\{a_after.memo_count},materializations:\{a_before.materialization_count}->\{a_after.materialization_count}",
  )
  println(
    "  B=value:\{int_result_text(b_before_value)}->\{int_result_text(b_after_value)},memos:\{b_before.memo_count}->\{b_after.memo_count},materializations:\{b_before.materialization_count}->\{b_after.materialization_count}",
  )
  println(
    "  observation=mutating Hash/Eq after insertion rematerialized both recipes; behavior is outside contract passed=\{passed}",
  )
  region_a.close()
  region_b.close()
  passed
}

///|
/// EvalCtx uses the same explicit read seam as Store.
fn probe_eval_ctx() -> Bool {
  let store = @provider.Store()
  let region = store.region()
  let query = region.query((key : String) => key.length())
  let view = query.at("eval")
  let result = @provider.EvalCtx(store).read(view)
  let passed = result == Ok(4)
  println(
    "scenario=eval_ctx result=\{int_result_text(result)} passed=\{passed}",
  )
  region.close()
  passed
}

///|
/// Runs all target-independent behavior under native and wasm-gc.
fn main {
  println("INCR NEXT KEYED VIEW RECIPE — POSITIVE CONSUMER")
  let recipe = probe_recipe_and_memo()
  let key_erasure = probe_key_erasure_a_and_b_baseline()
  let cross_store = probe_cross_store_metadata_first()
  let close = probe_close_with_surviving_view()
  let mutable_key = probe_mutable_key_counterexample()
  let eval_ctx = probe_eval_ctx()
  let passed = recipe &&
    key_erasure &&
    cross_store &&
    close &&
    mutable_key &&
    eval_ctx
  println(
    "full_state recipe=\{recipe} key_erasure=\{key_erasure} cross_store=\{cross_store} close=\{close} mutable_key=\{mutable_key} eval_ctx=\{eval_ctx}",
  )
  println("constrained verdict: \{if passed { "PASS" } else { "FAIL" }}")
  if !passed {
    abort("positive consumer evidence failed")
  }
}
