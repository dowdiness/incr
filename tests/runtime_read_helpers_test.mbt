///|
fn[T] read_memo_for_test(memo : @incr.Memo[T]) -> T {
  let observer = memo.observe()
  let value = observer.get()
  observer.dispose()
  value
}

///|
fn[T : Eq] read_hybrid_for_test(memo : @incr.HybridMemo[T]) -> T {
  let observer = memo.observe()
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
