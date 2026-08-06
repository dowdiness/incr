///|
struct Stamped {
  value : Int
  stamp : @incr.Revision
}

///|
impl @incr.HasChangedAt for Stamped with fn changed_at(self) {
  self.stamp
}

///|
impl @incr.BackdateEq for Stamped with fn backdate_equal(self, other) {
  self.stamp == other.stamp
}

///|
struct RawValue {
  value : Int
}

///|
fn require(condition : Bool, message : String) -> Unit {
  guard condition else { abort(message) }
}

///|
fn[T] read_view(view : @provider.View[T]) -> T {
  view() catch {
    _ => abort("unexpected prototype read failure")
  }
}

///|
fn scenario_independent_producers() -> Unit raise Failure {
  let store = @provider.Store()
  let accumulator : @provider.Accumulator[Int] = store.accumulator(
    label="ordered",
  )
  let (left, left_write) = store.input(10, label="left")
  let (right, right_write) = store.input(20, label="right")
  let (left_value, left_contribution) = accumulator.derived(
    store,
    () => {
      let value = left()
      accumulator.push(value)
      value
    },
    label="left_producer",
  )
  let (right_value, right_contribution) = accumulator.derived(
    store,
    () => {
      let value = right()
      accumulator.push(value)
      value
    },
    label="right_producer",
  )
  ignore(left_write)
  ignore(right_write)
  require(read_view(left_value) == 10, "left producer value")
  require(read_view(right_value) == 20, "right producer value")
  require(left_contribution.peek() == [10], "left contribution")
  require(right_contribution.peek() == [20], "right contribution")
  println(
    "scenario=independent left=\{to_repr(left_contribution.peek())} right=\{to_repr(right_contribution.peek())}",
  )
  store.close()
}

///|
fn scenario_changed_set_invalidates() -> Unit raise Failure {
  let store = @provider.Store()
  let accumulator : @provider.Accumulator[Int] = store.accumulator(
    label="changed",
  )
  let (source, write) = store.input(1, label="source")
  let (producer, contribution) = accumulator.derived(
    store,
    () => {
      accumulator.push(source())
      7
    },
    label="constant_producer",
  )
  let values = contribution.view()
  let consumer_runs = Ref(0)
  let consumer = store.derived(
    () => {
      consumer_runs.val += 1
      values()[0]
    },
    label="contribution_consumer",
  )
  require(read_view(producer) == 7, "producer prime")
  require(read_view(consumer) == 1, "consumer prime")
  require(consumer_runs.val == 1, "consumer prime count")
  write.set(2)
  require(read_view(producer) == 7, "ordinary producer output changed")
  require(read_view(consumer) == 2, "changed contribution not observed")
  require(consumer_runs.val == 2, "changed contribution did not invalidate")
  println(
    "scenario=changed_set producer=\{read_view(producer)} values=\{to_repr(contribution.peek())} consumer_runs=\{consumer_runs.val}",
  )
  store.close()
}

///|
fn scenario_same_set_backdates() -> Unit raise Failure {
  let store = @provider.Store()
  let accumulator : @provider.Accumulator[Int] = store.accumulator(
    label="stable",
  )
  let (source, write) = store.input(1, label="source")
  let (_, contribution) = accumulator.derived(
    store,
    () => {
      accumulator.push(42)
      source()
    },
    label="stable_producer",
  )
  let values = contribution.view()
  let consumer_runs = Ref(0)
  let consumer = store.derived(
    () => {
      consumer_runs.val += 1
      values()[0]
    },
    label="stable_consumer",
  )
  require(read_view(consumer) == 42, "stable consumer prime")
  require(consumer_runs.val == 1, "stable consumer prime count")
  write.set(2)
  require(read_view(consumer) == 42, "stable contribution changed")
  require(consumer_runs.val == 1, "unchanged contribution recomputed consumer")
  println(
    "scenario=same_set values=\{to_repr(contribution.peek())} consumer_runs=\{consumer_runs.val}",
  )
  store.close()
}

///|
fn scenario_peek_is_untracked_and_defensive() -> Unit raise Failure {
  let store = @provider.Store()
  let accumulator : @provider.Accumulator[Int] = store.accumulator(label="peek")
  let (source, _) = store.input(3)
  let (_, contribution) = accumulator.derived(store, () => {
    accumulator.push(source())
    0
  })
  let values = contribution.view()
  let consumer_runs = Ref(0)
  let consumer = store.derived(() => {
    consumer_runs.val += 1
    values().length()
  })
  require(read_view(consumer) == 1, "peek consumer prime")
  let snapshot = contribution.peek()
  snapshot.push(99)
  require(contribution.peek() == [3], "peek exposed mutable buffer")
  require(consumer_runs.val == 1, "peek recorded a dependency")
  println(
    "scenario=peek original=\{to_repr(contribution.peek())} mutated_copy=\{to_repr(snapshot)} consumer_runs=\{consumer_runs.val}",
  )
  store.close()
}

///|
fn scenario_creation_tiers() -> Unit raise Failure {
  let store = @provider.Store()
  let accumulator : @provider.Accumulator[Int] = store.accumulator(
    label="tiers",
  )
  let (source, _) = store.input(4)
  let (common, common_contribution) = accumulator.derived(
    store,
    () => {
      accumulator.push(1)
      source()
    },
    label="common_eq",
  )
  let (backdated, backdated_contribution) = accumulator.derived_with_backdate(
    store,
    () => {
      accumulator.push(2)
      Stamped::{ value: source(), stamp: @incr.Revision::initial() }
    },
    label="custom_backdate",
  )
  let (raw, raw_contribution) = accumulator.derived_no_backdate(
    store,
    () => {
      accumulator.push(3)
      RawValue::{ value: source() }
    },
    label="no_backdate",
  )
  require(read_view(common) == 4, "common producer")
  require(read_view(backdated).value == 4, "backdated producer")
  require(read_view(raw).value == 4, "no-backdate producer")
  require(common_contribution.peek() == [1], "common contribution")
  require(backdated_contribution.peek() == [2], "backdated contribution")
  require(raw_contribution.peek() == [3], "no-backdate contribution")
  println(
    "scenario=tiers common=\{to_repr(common_contribution.peek())} backdated=\{to_repr(backdated_contribution.peek())} no_backdate=\{to_repr(raw_contribution.peek())}",
  )
  store.close()
}

///|
fn scenario_lifecycle() -> Unit raise Failure {
  let store = @provider.Store()
  let accumulator : @provider.Accumulator[Int] = store.accumulator(
    label="lifecycle",
  )
  let (_, contribution) = accumulator.derived(store, () => {
    accumulator.push(5)
    0
  })
  ignore(read_view(contribution.view()))
  require(!accumulator.is_disposed(), "accumulator starts disposed")
  accumulator.dispose()
  require(accumulator.is_disposed(), "accumulator did not dispose")
  require(contribution.peek() == [], "disposed accumulator peek is not empty")
  store.close()
  store.close()
  println(
    "scenario=lifecycle accumulator_disposed=\{accumulator.is_disposed()} peek=\{to_repr(contribution.peek())} close_calls=2",
  )
}

///|
fn scenario_cross_store_rejected_early() -> Unit {
  let owner = @provider.Store()
  let other = @provider.Store()
  let accumulator : @provider.Accumulator[Int] = owner.accumulator(
    label="owner",
  )
  let compute_runs = Ref(0)
  let rejected = try {
    ignore(
      accumulator.derived(other, () => {
        compute_runs.val += 1
        0
      }),
    )
    false
  } catch {
    _ => true
  }
  require(rejected, "cross-Store producer was accepted")
  require(compute_runs.val == 0, "cross-Store compute ran before rejection")
  println(
    "scenario=cross_store rejected=\{rejected} compute_runs=\{compute_runs.val}",
  )
  owner.close()
  other.close()
}

///|
fn run_positive() -> Unit raise Failure {
  scenario_independent_producers()
  scenario_changed_set_invalidates()
  scenario_same_set_backdates()
  scenario_peek_is_untracked_and_defensive()
  scenario_creation_tiers()
  scenario_lifecycle()
  scenario_cross_store_rejected_early()
  println("positive_probes=PASS")
}

///|
fn main {
  try! run_positive()
}
