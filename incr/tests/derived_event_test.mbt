///|
test "derived_event: listener observes public event types" {
  let rt = Runtime()
  let sig = Input(rt, 1)
  let memo = Derived::Derived(rt, () => sig.get() + 1)
  let events : Array[String] = []
  rt.on_derived_event(evt => {
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
  inspect(read_derived_for_test(memo), content="2")
  inspect(events.length(), content="2")
  inspect(events[0], content="enter@0")
  inspect(events[1], content="completed")
  rt.clear_derived_event_listener()
  sig.set(2)
  inspect(read_derived_for_test(memo), content="3")
  inspect(events.length(), content="2")
}

///|
test "derived_event: listener mutation is rejected during recompute" {
  let rt = Runtime()
  let memo = Derived::Derived(rt, () => {
    try rt.clear_derived_event_listener() catch {
      _ => 1
    } noraise {
      _ => 0
    }
  })
  inspect(read_derived_for_test(memo), content="1")
}

///|
test "derived_event_listener_observes_hybrid_memo_recompute_events" {
  let rt = Runtime()
  let sig = Input(rt, 1)
  let hybrid = @incr.ReachableDerived(rt, () => sig.get() + 1)
  let events : Array[String] = []
  rt.on_derived_event(evt => {
    match evt {
      EnteringCompute(_) => events.push("enter")
      Completed(e) =>
        if e.backdated {
          events.push("completed@backdated")
        } else {
          events.push("completed")
        }
      Aborted(_) => events.push("aborted")
    }
  })
  inspect(read_reachable_for_test(hybrid), content="2")
  inspect(events.length(), content="2")
  inspect(events[0], content="enter")
  inspect(events[1], content="completed")
  events.clear()
  inspect(read_reachable_for_test(hybrid), content="2")
  inspect(events.length(), content="0")
  sig.set(2)
  inspect(read_reachable_for_test(hybrid), content="3")
  inspect(events.length(), content="2")
  inspect(events[0], content="enter")
  inspect(events[1], content="completed")
}

///|
test "derived_event_no_listener_creates_no_backlog_for_later_listener" {
  let rt = Runtime()
  let sig = Input(rt, 1)
  let memo = Derived::Derived(rt, () => sig.get() + 1)
  inspect(read_derived_for_test(memo), content="2")
  let events : Array[String] = []
  rt.on_derived_event(evt => {
    match evt {
      EnteringCompute(_) => events.push("enter")
      Completed(_) => events.push("completed")
      Aborted(_) => events.push("aborted")
    }
  })
  inspect(read_derived_for_test(memo), content="2")
  inspect(events.length(), content="0")
  sig.set(2)
  inspect(read_derived_for_test(memo), content="3")
  inspect(events.length(), content="2")
  inspect(events[0], content="enter")
  inspect(events[1], content="completed")
}
