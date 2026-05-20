///|
test "memo_event: listener observes public event types" {
  let rt = Runtime()
  let sig = Signal(rt, 1)
  let memo = Memo(rt, () => sig.get() + 1)
  let events : Array[String] = []
  rt.on_memo_event(evt => {
    match evt {
      EnteringCompute(e) =>
        if e.started_revision.value == 0 {
          events.push("enter@0")
        } else {
          events.push("enter@other")
        }
      Completed(e) =>
        if e.backdated {
          events.push("completed@backdated")
        } else {
          events.push("completed")
        }
      Aborted(_) => events.push("aborted")
    }
  })
  inspect(rt.read(memo), content="2")
  inspect(events.length(), content="2")
  inspect(events[0], content="enter@0")
  inspect(events[1], content="completed")
  rt.clear_memo_event_listener()
  sig.set(2)
  inspect(rt.read(memo), content="3")
  inspect(events.length(), content="2")
}

///|
test "memo_event: listener mutation is rejected during recompute" {
  let rt = Runtime()
  let memo = Memo(rt, () => {
    let result : Result[Unit, Error] = try? rt.clear_memo_event_listener()
    match result {
      Ok(_) => 0
      Err(_) => 1
    }
  })
  inspect(rt.read(memo), content="1")
}
