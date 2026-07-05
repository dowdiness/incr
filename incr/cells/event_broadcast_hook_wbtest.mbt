///|
/// Sentinel hook registered after the accumulator and event hooks.
priv struct EventOrderSentinel {
  before_log : Array[(CellId, Bool, Bool, Int)]
  success_log : Array[(CellId, Bool, Bool, Int)]
  abort_log : Array[(CellId, Bool, Bool, Int)]
}

///|
fn EventOrderSentinel::new() -> EventOrderSentinel {
  { before_log: [], success_log: [], abort_log: [] }
}

///|
fn event_entry_present(rt : Runtime, cell_id : CellId) -> Bool {
  match rt.event_broadcast_hook.active.get(cell_id) {
    Some(_) => true
    None => false
  }
}

///|
impl MemoCommitPhase for EventOrderSentinel with fn before_recompute(
  self,
  rt,
  cell_id,
) {
  self.before_log.push(
    (
      cell_id,
      entry_present(rt, cell_id),
      event_entry_present(rt, cell_id),
      rt.event_broadcast_hook.pending.length(),
    ),
  )
}

///|
impl MemoCommitPhase for EventOrderSentinel with fn after_success(
  self,
  rt,
  cell_id,
) {
  self.success_log.push(
    (
      cell_id,
      entry_present(rt, cell_id),
      event_entry_present(rt, cell_id),
      rt.event_broadcast_hook.pending.length(),
    ),
  )
}

///|
impl MemoCommitPhase for EventOrderSentinel with fn after_abort(
  self,
  rt,
  cell_id,
  _e,
) {
  self.abort_log.push(
    (
      cell_id,
      entry_present(rt, cell_id),
      event_entry_present(rt, cell_id),
      rt.event_broadcast_hook.pending.length(),
    ),
  )
}

///|
fn event_kind(evt : DerivedEvent) -> String {
  match evt {
    EnteringCompute(_) => "enter"
    Completed(_) => "completed"
    Aborted(_) => "aborted"
  }
}

///|
fn push_event_kind(events : Array[String], evt : DerivedEvent) -> Unit {
  events.push(event_kind(evt))
}

///|
test "derived_event: hook order follows accumulator then event hook" {
  let rt = Runtime()
  let sentinel = EventOrderSentinel::new()
  rt.commit_hooks.push(sentinel)
  rt.on_derived_event(_evt => ())
  let acc : Accumulator[Int] = Accumulator(rt)
  let derived = Derived(rt, () => {
    acc.push(1)
    42
  })
  inspect(derived.read_or_abort(), content="42")
  let memo_id = derived.id()
  inspect(sentinel.before_log.length(), content="1")
  inspect(sentinel.before_log[0].0 == memo_id, content="true")
  inspect(sentinel.before_log[0].1, content="true")
  inspect(sentinel.before_log[0].2, content="true")
  inspect(sentinel.before_log[0].3, content="1")
  inspect(sentinel.success_log.length(), content="1")
  inspect(sentinel.success_log[0].0 == memo_id, content="true")
  inspect(sentinel.success_log[0].1, content="false")
  inspect(sentinel.success_log[0].2, content="false")
  inspect(sentinel.success_log[0].3, content="2")
  inspect(sentinel.abort_log.length(), content="0")
}

///|
test "derived_event: hook order on abort removes active entries before later hooks" {
  let rt = Runtime()
  let sentinel = EventOrderSentinel::new()
  rt.commit_hooks.push(sentinel)
  rt.on_derived_event(_evt => ())
  let _acc : Accumulator[Int] = Accumulator(rt)
  let derived : Derived[Int] = Derived(rt, () => raise Failure("boom"))
  try derived.force_recompute() catch {
    _ => ()
  } noraise {
    _ => ()
  }
  let memo_id = derived.id()
  inspect(sentinel.before_log.length(), content="1")
  inspect(sentinel.before_log[0].0 == memo_id, content="true")
  inspect(sentinel.before_log[0].1, content="true")
  inspect(sentinel.before_log[0].2, content="true")
  inspect(sentinel.before_log[0].3, content="1")
  inspect(sentinel.abort_log.length(), content="1")
  inspect(sentinel.abort_log[0].0 == memo_id, content="true")
  inspect(sentinel.abort_log[0].1, content="false")
  inspect(sentinel.abort_log[0].2, content="false")
  inspect(sentinel.abort_log[0].3, content="2")
  inspect(sentinel.success_log.length(), content="0")
}

///|
test "derived_event: nested recomputes buffer until outermost frame exits" {
  let rt = Runtime()
  let events : Array[String] = []
  let pending_seen_inside_outer : Array[Int] = []
  let inner = Derived(rt, () => 2)
  let outer = Derived(rt, () => {
    let value = inner.get_or_abort()
    pending_seen_inside_outer.push(rt.event_broadcast_hook.pending.length())
    value + 1
  })
  rt.on_derived_event(evt => push_event_kind(events, evt))
  inspect(outer.read_or_abort(), content="3")
  inspect(pending_seen_inside_outer.length(), content="1")
  inspect(pending_seen_inside_outer[0], content="3")
  inspect(events.length(), content="4")
  inspect(events[0], content="enter")
  inspect(events[1], content="enter")
  inspect(events[2], content="completed")
  inspect(events[3], content="completed")
  inspect(rt.event_broadcast_hook.pending.length(), content="0")
}

///|
test "derived_event: listener read does not pollute drained memo dependencies" {
  let rt = Runtime()
  let source = Input(rt, 1)
  let probe_source = Input(rt, 10)
  let probe = Derived(rt, () => probe_source.get())
  let did_read = Ref(false)
  let probe_reads : Array[Int] = []
  let events : Array[String] = []
  rt.on_derived_event(evt => {
    push_event_kind(events, evt)
    match evt {
      Completed(_) =>
        if !did_read.val {
          did_read.val = true
          probe_reads.push(probe.read_or_abort())
        }
      _ => ()
    }
  })
  let outer = Derived(rt, () => source.get() + 1)
  inspect(outer.read_or_abort(), content="2")
  inspect(probe_reads.length(), content="1")
  inspect(probe_reads[0], content="10")
  let deps = rt.get_memo_data(outer.id()).dependencies
  inspect(deps.length(), content="1")
  inspect(deps[0] == source.id(), content="true")
  inspect(events.length(), content="4")
  inspect(events[0], content="enter")
  inspect(events[1], content="completed")
  inspect(events[2], content="enter")
  inspect(events[3], content="completed")
}

///|
test "derived_event: listener set can enqueue recursive memo events" {
  let rt = Runtime()
  let source = Input(rt, 0)
  let trigger = Input(rt, 0)
  let reentered = Derived(rt, () => trigger.get() + 10)
  let observed : Array[Int] = []
  let _effect = Effect::new(rt, () => {
    if trigger.get() > 0 {
      observed.push(reentered.get_or_abort())
    }
  })
  let outer = Derived(rt, () => source.get() + 1)
  let did_set = Ref(false)
  let events : Array[String] = []
  rt.on_derived_event(evt => {
    push_event_kind(events, evt)
    match evt {
      Completed(e) =>
        if e.cell_id == outer.id() && !did_set.val {
          did_set.val = true
          trigger.set(1)
        }
      _ => ()
    }
  })
  inspect(outer.read_or_abort(), content="1")
  inspect(observed.length(), content="1")
  inspect(observed[0], content="11")
  inspect(events.length(), content="4")
  inspect(events[0], content="enter")
  inspect(events[1], content="completed")
  inspect(events[2], content="enter")
  inspect(events[3], content="completed")
}

///|
test "derived_event: no event fires for green verification path" {
  let rt = Runtime()
  let source = Input(rt, 1)
  let unrelated = Input(rt, 0)
  let derived = Derived(rt, () => source.get() + 1)
  let events : Array[String] = []
  rt.on_derived_event(evt => push_event_kind(events, evt))
  inspect(derived.read_or_abort(), content="2")
  events.clear()
  unrelated.set(1)
  inspect(derived.read_or_abort(), content="2")
  inspect(events.length(), content="0")
}

///|
test "derived_event: mutation guard rejects batch body" {
  let rt = Runtime()
  let rejected = Ref(false)
  rt.batch(() => {
    try rt.on_derived_event(_evt => ()) catch {
      _ => rejected.val = true
    } noraise {
      _ => ()
    }
  })
  inspect(rejected.val, content="true")
}

///|
test "derived_event: mutation guard rejects non-idle phase" {
  let rt = Runtime()
  rt.enter_phase(GarbageCollecting)
  let mut rejected = false
  try rt.on_derived_event(_evt => ()) catch {
    _ => rejected = true
  } noraise {
    _ => ()
  }
  rt.leave_phase()
  inspect(rejected, content="true")
}

///|
test "derived_event: mutation guard rejects push tracking frame" {
  let rt = Runtime()
  rt.on_derived_event(_evt => ())
  let rejected = Ref(false)
  let _effect = Effect::new(rt, () => {
    try rt.clear_derived_event_listener() catch {
      _ => rejected.val = true
    } noraise {
      _ => ()
    }
  })
  inspect(rejected.val, content="true")
}

///|
test "derived_event: mutation guard rejects pending events inside on_change" {
  let rt = Runtime()
  let source = Input(rt, 0)
  let hybrid = ReachableDerived(rt, () => source.get() + 1)
  let _effect = Effect::new(rt, () => ignore(hybrid.get()))
  rt.on_derived_event(_evt => ())
  let rejected = Ref(false)
  source.on_change(_v => {
    try rt.clear_derived_event_listener() catch {
      _ => rejected.val = true
    } noraise {
      _ => ()
    }
  })
  source.set(1)
  inspect(rejected.val, content="true")
}

///|
test "derived_event: mutation guard rejects on_change without pending events" {
  let rt = Runtime()
  let source = Input(rt, 0)
  rt.on_derived_event(_evt => ())
  let saw_empty_pending = Ref(false)
  let rejected = Ref(false)
  source.on_change(_v => {
    saw_empty_pending.val = rt.event_broadcast_hook.pending.is_empty()
    try rt.clear_derived_event_listener() catch {
      _ => rejected.val = true
    } noraise {
      _ => ()
    }
  })
  source.set(1)
  inspect(saw_empty_pending.val, content="true")
  inspect(rejected.val, content="true")
}

///|
test "derived_event: mutation guard rejects listener reentry" {
  let rt = Runtime()
  let rejected = Ref(false)
  let derived = Derived(rt, () => 1)
  rt.on_derived_event(_evt => {
    try rt.clear_derived_event_listener() catch {
      _ => rejected.val = true
    } noraise {
      _ => ()
    }
  })
  inspect(derived.read_or_abort(), content="1")
  inspect(rejected.val, content="true")
}

///|
test "derived_event: listener mutation succeeds between operations" {
  let rt = Runtime()
  let first = try rt.on_derived_event(_evt => ()) catch {
    _ => false
  } noraise {
    _ => true
  }
  let clear = try rt.clear_derived_event_listener() catch {
    _ => false
  } noraise {
    _ => true
  }
  let second = try rt.on_derived_event(_evt => ()) catch {
    _ => false
  } noraise {
    _ => true
  }
  inspect(first, content="true")
  inspect(clear, content="true")
  inspect(second, content="true")
}

///|
test "derived_event: raising API defers drain until next operation" {
  let rt = Runtime()
  let events : Array[String] = []
  rt.on_derived_event(evt => push_event_kind(events, evt))
  let inner = Derived(rt, () => 1)
  let target : Derived[Int] = Derived(rt, () => {
    ignore(inner.get_or_abort())
    raise Failure("target failed")
  })
  let mut failed = false
  try target.force_recompute() catch {
    _ => failed = true
  } noraise {
    _ => ()
  }
  inspect(failed, content="true")
  inspect(events.length(), content="0")
  inspect(rt.event_broadcast_hook.pending.length(), content="4")
  let stable = Derived(rt, () => 7)
  inspect(stable.read_or_abort(), content="7")
  inspect(events.length(), content="6")
  inspect(events[0], content="enter")
  inspect(events[1], content="enter")
  inspect(events[2], content="completed")
  inspect(events[3], content="aborted")
  inspect(events[4], content="enter")
  inspect(events[5], content="completed")
}

///|
test "derived_event: revision capture survives mid-compute revision bump" {
  let rt = Runtime()
  let tick = Input(rt, 0)
  let started : Array[Int] = []
  let verified : Array[Int] = []
  rt.on_derived_event(evt => {
    match evt {
      EnteringCompute(e) => started.push(e.started_revision.value)
      Completed(e) => verified.push(e.verified_at.value)
      Aborted(_) => ()
    }
  })
  let derived = Derived(rt, () => {
    tick.force_set(tick.peek() + 1)
    99
  })
  inspect(derived.read_or_abort(), content="99")
  inspect(started.length(), content="1")
  inspect(verified.length(), content="1")
  inspect(started[0] < verified[0], content="true")
}

///|
// --- Composable derived-event listeners (#210) ---

///|
test "derived_event: two additive listeners observe events event-major in registration order" {
  let rt = Runtime()
  let mut log = ""
  rt.add_derived_event_listener(evt => log = log + "a:" + event_kind(evt) + " ")
  |> ignore
  rt.add_derived_event_listener(evt => log = log + "b:" + event_kind(evt) + " ")
  |> ignore
  let s = Input(rt, 1)
  let m = Derived(rt, () => s.get() * 2)
  inspect(m.read_or_abort(), content="2")
  // One recompute buffers [EnteringCompute, Completed]. Event-major drain:
  // for each event, both listeners fire in registration order.
  inspect(log, content="a:enter b:enter a:completed b:completed ")
}

///|
test "derived_event: remove_derived_event_listener is idempotent and stops only that listener" {
  let rt = Runtime()
  let mut a = 0
  let mut b = 0
  let id_a = rt.add_derived_event_listener(evt => {
    if event_kind(evt) == "completed" {
      a = a + 1
    }
  })
  rt.add_derived_event_listener(evt => {
    if event_kind(evt) == "completed" {
      b = b + 1
    }
  })
  |> ignore
  let s = Input(rt, 1)
  let m = Derived(rt, () => s.get() * 2)
  inspect(m.read_or_abort(), content="2")
  inspect(a, content="1")
  inspect(b, content="1")
  rt.remove_derived_event_listener(id_a)
  s.set(2)
  inspect(m.read_or_abort(), content="4")
  inspect(a, content="1")
  inspect(b, content="2")
  // Removing again at idle is a no-op, not an error.
  rt.remove_derived_event_listener(id_a)
  s.set(3)
  inspect(m.read_or_abort(), content="6")
  inspect(a, content="1")
  inspect(b, content="3")
}

///|
test "derived_event: on_derived_event singleton coexists with an additive listener" {
  let rt = Runtime()
  let mut log = ""
  rt.on_derived_event(evt => {
    if event_kind(evt) == "completed" {
      log = log + "S"
    }
  })
  rt.add_derived_event_listener(evt => {
    if event_kind(evt) == "completed" {
      log = log + "a"
    }
  })
  |> ignore
  let s = Input(rt, 1)
  let m = Derived(rt, () => s.get() * 2)
  inspect(m.read_or_abort(), content="2")
  inspect(log, content="Sa")
}

///|
test "derived_event: additive registration guard rejects inside a compute closure" {
  let rt = Runtime()
  let rejected : Ref[Bool] = Ref(false)
  let s = Input(rt, 1)
  let derived = Derived(rt, () => {
    try rt.add_derived_event_listener(_e => ()) catch {
      _ => rejected.val = true
    } noraise {
      _ => ()
    }
    s.get()
  })
  inspect(derived.read_or_abort(), content="1")
  inspect(rejected.val, content="true")
}
