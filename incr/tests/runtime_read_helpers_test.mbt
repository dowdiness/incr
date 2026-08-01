///|
fn[T] read_derived_for_test(derived : @incr.Derived[T]) -> T {
  let watch = derived.watch()
  let value = watch.read_or_abort()
  watch.dispose()
  value
}

///|
fn[T : Eq] read_reachable_for_test(reachable : @incr.ReachableDerived[T]) -> T {
  let watch = reachable.watch()
  let value = watch.read_or_abort()
  watch.dispose()
  value
}

///|
fn[T] read_reactive_for_test(reactive : @incr.EagerDerived[T]) -> T {
  let watch = reactive.watch()
  let value = watch.read_or_abort()
  watch.dispose()
  value
}
