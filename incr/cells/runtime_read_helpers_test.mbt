///|
fn[T] read_reactive_for_test(reactive : EagerDerived[T]) -> T {
  let observer = reactive.observe()
  let value = observer.get()
  observer.dispose()
  value
}
