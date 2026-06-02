///|
/// Pins the 0.8.0 deprecation surface: the old `@incr.MemoEvent` type alias,
/// `Runtime::on_memo_event`, and `Runtime::clear_memo_event_listener` still
/// compile and behave identically to the canonical `Derived*` API. The kept
/// variant names (`EnteringCompute` / `Completed` / `Aborted`) keep downstream
/// `match` arms source-compatible across the rename.
#warnings("-deprecated")
test "derived_event: deprecated MemoEvent / on_memo_event aliases still work" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1)
  let memo = @incr.Memo(rt, () => sig.get() + 1)
  let events : Array[String] = []
  let listener : (@incr.MemoEvent) -> Unit = evt => {
    match evt {
      EnteringCompute(_) => events.push("enter")
      Completed(_) => events.push("completed")
      Aborted(_) => events.push("aborted")
    }
  }
  rt.on_memo_event(listener)
  inspect(read_memo_for_test(memo), content="2")
  inspect(events.length(), content="2")
  inspect(events[0], content="enter")
  inspect(events[1], content="completed")
  rt.clear_memo_event_listener()
  sig.set(2)
  inspect(read_memo_for_test(memo), content="3")
  inspect(events.length(), content="2")
}
