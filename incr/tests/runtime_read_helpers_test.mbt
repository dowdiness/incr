///|
fn[T] read_derived_for_test(derived : @incr.Derived[T]) -> T {
  let observer = derived.observe()
  let value = observer.get()
  observer.dispose()
  value
}

///|
fn[T : Eq] read_reachable_for_test(reachable : @incr.ReachableDerived[T]) -> T {
  let observer = reachable.observe()
  let value = observer.get()
  observer.dispose()
  value
}

///|
fn[T] read_reactive_for_test(reactive : @incr.Reactive[T]) -> T {
  let observer = reactive.observe()
  let value = observer.get()
  observer.dispose()
  value
}

