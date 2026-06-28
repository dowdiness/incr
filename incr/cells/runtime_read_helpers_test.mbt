///|
/// Compatibility helper for debug_test.mbt which tests Memo::Debug directly.
/// All other callers should use Derived::read_or_abort().
fn[T] read_memo_for_test(memo : Memo[T]) -> T {
  let observer = memo.observe()
  let value = observer.get()
  observer.dispose()
  value
}

///|
fn[T] read_reactive_for_test(reactive : Reactive[T]) -> T {
  let observer = reactive.observe()
  let value = observer.get()
  observer.dispose()
  value
}
