///|
/// Top-level test reads run with no computation in flight, so the global
/// computing-runtime sentinel must be idle. A panic test that `abort()`s
/// mid-compute leaks it: `abort` is uncatchable, so it bypasses
/// `memo_force_recompute`'s catch arm and `pop_tracking` never clears the
/// sentinel. This is purely a test-harness artifact — in production an `abort`
/// terminates the process, so no later read ever observes the stale value. The
/// test runner instead catches the panic and continues with a shared process
/// global, so a later top-level read would (correctly) trip the cross-runtime
/// guard against a dead runtime's id. Clearing the stale sentinel here restores
/// the "idle between top-level reads" invariant without re-masking a *live*
/// cross-runtime read (which never routes through these top-level helpers). See
/// issue #174.
fn reset_stale_sentinel_for_top_level_test_read() -> Unit {
  @kernel.set_current_computing_runtime_id(None)
}

///|
fn[T] read_memo_for_test(memo : Memo[T]) -> T {
  reset_stale_sentinel_for_top_level_test_read()
  let observer = memo.observe()
  let value = observer.get()
  observer.dispose()
  value
}

///|
fn[T : Eq] read_hybrid_for_test(memo : HybridMemo[T]) -> T {
  reset_stale_sentinel_for_top_level_test_read()
  let observer = memo.observe()
  let value = observer.get()
  observer.dispose()
  value
}

///|
fn[T] read_reactive_for_test(reactive : Reactive[T]) -> T {
  reset_stale_sentinel_for_top_level_test_read()
  let observer = reactive.observe()
  let value = observer.get()
  observer.dispose()
  value
}
