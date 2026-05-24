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
fn event_kind(evt : MemoEvent) -> String {
  match evt {
    EnteringCompute(_) => "enter"
    Completed(_) => "completed"
    Aborted(_) => "aborted"
  }
}

///|
fn push_event_kind(events : Array[String], evt : MemoEvent) -> Unit {
  events.push(event_kind(evt))
}

///|
test "memo_event: hook order follows accumulator then event hook" {
  let rt = Runtime()
  let sentinel = EventOrderSentinel::new()
  rt.commit_hooks.push(sentinel)
  rt.on_memo_event(_evt => ())
  let acc : Accumulator[Int] = Accumulator::new(rt~)
  let memo = Memo(rt, () => {
    acc.push(1)
    42
  })
  inspect(read_memo_for_test(memo), content="42")
  let memo_id = memo.id()
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
test "memo_event: hook order on abort removes active entries before later hooks" {
  let rt = Runtime()
  let sentinel = EventOrderSentinel::new()
  rt.commit_hooks.push(sentinel)
  rt.on_memo_event(_evt => ())
  let _acc : Accumulator[Int] = Accumulator::new(rt~)
  let memo : Memo[Int] = Memo(rt, () => raise Failure("boom"))
  let _ : Result[Result[Int, CycleError], Failure] = try? memo.force_recompute()
  let memo_id = memo.id()
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
test "memo_event: nested recomputes buffer until outermost frame exits" {
  let rt = Runtime()
  let events : Array[String] = []
  let pending_seen_inside_outer : Array[Int] = []
  let inner = Memo(rt, () => 2)
  let outer = Memo(rt, () => {
    let value = inner.get()
    pending_seen_inside_outer.push(rt.event_broadcast_hook.pending.length())
    value + 1
  })
  rt.on_memo_event(evt => push_event_kind(events, evt))
  inspect(read_memo_for_test(outer), content="3")
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
test "memo_event: listener read does not pollute drained memo dependencies" {
  let rt = Runtime()
  let source = Signal(rt, 1)
  let probe_source = Signal(rt, 10)
  let probe = Memo(rt, () => probe_source.get())
  let did_read = Ref(false)
  let probe_reads : Array[Int] = []
  let events : Array[String] = []
  rt.on_memo_event(evt => {
    push_event_kind(events, evt)
    match evt {
      Completed(_) =>
        if !did_read.val {
          did_read.val = true
          probe_reads.push(read_memo_for_test(probe))
        }
      _ => ()
    }
  })
  let outer = Memo(rt, () => source.get() + 1)
  inspect(read_memo_for_test(outer), content="2")
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
test "memo_event: listener set can enqueue recursive memo events" {
  let rt = Runtime()
  let source = Signal(rt, 0)
  let trigger = Signal(rt, 0)
  let reentered = Memo(rt, () => trigger.get() + 10)
  let observed : Array[Int] = []
  let _effect = Effect::new(rt, () => {
    if trigger.get() > 0 {
      observed.push(reentered.get())
    }
  })
  let outer = Memo(rt, () => source.get() + 1)
  let did_set = Ref(false)
  let events : Array[String] = []
  rt.on_memo_event(evt => {
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
  inspect(read_memo_for_test(outer), content="1")
  inspect(observed.length(), content="1")
  inspect(observed[0], content="11")
  inspect(events.length(), content="4")
  inspect(events[0], content="enter")
  inspect(events[1], content="completed")
  inspect(events[2], content="enter")
  inspect(events[3], content="completed")
}

///|
test "memo_event: no event fires for green verification path" {
  let rt = Runtime()
  let source = Signal(rt, 1)
  let unrelated = Signal(rt, 0)
  let memo = Memo(rt, () => source.get() + 1)
  let events : Array[String] = []
  rt.on_memo_event(evt => push_event_kind(events, evt))
  inspect(read_memo_for_test(memo), content="2")
  events.clear()
  unrelated.set(1)
  inspect(read_memo_for_test(memo), content="2")
  inspect(events.length(), content="0")
}

///|
test "memo_event: mutation guard rejects batch body" {
  let rt = Runtime()
  let rejected = Ref(false)
  rt.batch(() => {
    let result : Result[Unit, Error] = try? rt.on_memo_event(_evt => ())
    match result {
      Ok(_) => ()
      Err(_) => rejected.val = true
    }
  })
  inspect(rejected.val, content="true")
}

///|
test "memo_event: mutation guard rejects non-idle phase" {
  let rt = Runtime()
  rt.enter_phase(GarbageCollecting)
  let result : Result[Unit, Error] = try? rt.on_memo_event(_evt => ())
  rt.leave_phase()
  inspect(result is Err(_), content="true")
}

///|
test "memo_event: mutation guard rejects push tracking frame" {
  let rt = Runtime()
  rt.on_memo_event(_evt => ())
  let rejected = Ref(false)
  let _effect = Effect::new(rt, () => {
    let result : Result[Unit, Error] = try? rt.clear_memo_event_listener()
    match result {
      Ok(_) => ()
      Err(_) => rejected.val = true
    }
  })
  inspect(rejected.val, content="true")
}

///|
test "memo_event: mutation guard rejects pending events inside on_change" {
  let rt = Runtime()
  let source = Signal(rt, 0)
  let hybrid = HybridMemo(rt, () => source.get() + 1)
  let _effect = Effect::new(rt, () => ignore(hybrid.get()))
  rt.on_memo_event(_evt => ())
  let rejected = Ref(false)
  source.on_change(_v => {
    let result : Result[Unit, Error] = try? rt.clear_memo_event_listener()
    match result {
      Ok(_) => ()
      Err(_) => rejected.val = true
    }
  })
  source.set(1)
  inspect(rejected.val, content="true")
}

///|
test "memo_event: mutation guard rejects on_change without pending events" {
  let rt = Runtime()
  let source = Signal(rt, 0)
  rt.on_memo_event(_evt => ())
  let saw_empty_pending = Ref(false)
  let rejected = Ref(false)
  source.on_change(_v => {
    saw_empty_pending.val = rt.event_broadcast_hook.pending.is_empty()
    let result : Result[Unit, Error] = try? rt.clear_memo_event_listener()
    match result {
      Ok(_) => ()
      Err(_) => rejected.val = true
    }
  })
  source.set(1)
  inspect(saw_empty_pending.val, content="true")
  inspect(rejected.val, content="true")
}

///|
test "memo_event: mutation guard rejects listener reentry" {
  let rt = Runtime()
  let rejected = Ref(false)
  let memo = Memo(rt, () => 1)
  rt.on_memo_event(_evt => {
    let result : Result[Unit, Error] = try? rt.clear_memo_event_listener()
    match result {
      Ok(_) => ()
      Err(_) => rejected.val = true
    }
  })
  inspect(read_memo_for_test(memo), content="1")
  inspect(rejected.val, content="true")
}

///|
test "memo_event: listener mutation succeeds between operations" {
  let rt = Runtime()
  let first : Result[Unit, Error] = try? rt.on_memo_event(_evt => ())
  let clear : Result[Unit, Error] = try? rt.clear_memo_event_listener()
  let second : Result[Unit, Error] = try? rt.on_memo_event(_evt => ())
  inspect(first is Ok(_), content="true")
  inspect(clear is Ok(_), content="true")
  inspect(second is Ok(_), content="true")
}

///|
test "memo_event: raising API defers drain until next operation" {
  let rt = Runtime()
  let events : Array[String] = []
  rt.on_memo_event(evt => push_event_kind(events, evt))
  let acc : Accumulator[Int] = Accumulator::new(rt~)
  let inner = Memo(rt, () => 1)
  let target : Memo[Int] = Memo(rt, () => {
    ignore(inner.get())
    raise Failure("target failed")
  })
  let result : Result[Result[Array[Int], CycleError], Error] = try? target.accumulated_result(
    acc,
  )
  inspect(result is Err(_), content="true")
  inspect(events.length(), content="0")
  inspect(rt.event_broadcast_hook.pending.length(), content="4")
  let stable = Memo(rt, () => 7)
  inspect(read_memo_for_test(stable), content="7")
  inspect(events.length(), content="6")
  inspect(events[0], content="enter")
  inspect(events[1], content="enter")
  inspect(events[2], content="completed")
  inspect(events[3], content="aborted")
  inspect(events[4], content="enter")
  inspect(events[5], content="completed")
}

///|
test "memo_event: revision capture survives mid-compute revision bump" {
  let rt = Runtime()
  let tick = Signal(rt, 0)
  let started : Array[Int] = []
  let verified : Array[Int] = []
  rt.on_memo_event(evt => {
    match evt {
      EnteringCompute(e) => started.push(e.started_revision.value)
      Completed(e) => verified.push(e.verified_at.value)
      Aborted(_) => ()
    }
  })
  let memo = Memo(rt, () => {
    tick.set_unconditional(tick.peek() + 1)
    99
  })
  inspect(read_memo_for_test(memo), content="99")
  inspect(started.length(), content="1")
  inspect(verified.length(), content="1")
  inspect(started[0] < verified[0], content="true")
}
