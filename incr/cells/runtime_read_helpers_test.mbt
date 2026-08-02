///|
fn[T] read_reactive_for_test(reactive : EagerDerived[T]) -> T {
  let watch = reactive.watch()
  let value = watch.read_or_abort()
  watch.dispose()
  value
}
