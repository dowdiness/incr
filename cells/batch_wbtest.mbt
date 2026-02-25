///|
suberror BatchTestError {
  Stop
}

///|
test "batch: basic - single revision for multiple sets" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let b = Signal::new(rt, 2)
  inspect(rt.current_revision.value, content="0")
  rt.batch(() => {
    a.set(10)
    b.set(20)
  })
  // Only one revision bump for both sets
  inspect(rt.current_revision.value, content="1")
  inspect(a.get(), content="10")
  inspect(b.get(), content="20")
}

///|
test "batch: nested - only outermost commits" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let b = Signal::new(rt, 2)
  let c = Signal::new(rt, 3)
  rt.batch(() => {
    a.set(10)
    rt.batch(() => {
      b.set(20)
      c.set(30)
    })
    // Inner batch should not have committed yet
  })
  // Single revision bump for all three sets
  inspect(rt.current_revision.value, content="1")
  inspect(a.get(), content="10")
  inspect(b.get(), content="20")
  inspect(c.get(), content="30")
}

///|
test "batch: empty - no revision bump" {
  let rt = Runtime::new()
  let _a = Signal::new(rt, 1)
  rt.batch(() => ())
  inspect(rt.current_revision.value, content="0")
}

///|
test "batch: mixed durabilities" {
  let rt = Runtime::new()
  let low = Signal::new(rt, 1)
  let high = Signal::new(rt, 100, durability=High)
  rt.batch(() => {
    low.set(2)
    high.set(200)
  })
  // Single revision, max durability should be High
  inspect(rt.current_revision.value, content="1")
  inspect(low.get(), content="2")
  inspect(high.get(), content="200")
  // durability_last_changed should reflect High (covers all levels)
  inspect(rt.durability_last_changed[0].value, content="1")
  inspect(rt.durability_last_changed[1].value, content="1")
  inspect(rt.durability_last_changed[2].value, content="1")
}

///|
test "batch: memo read after batch" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let b = Signal::new(rt, 2)
  let mut compute_count = 0
  let sum = Memo::new(rt, () => {
    compute_count = compute_count + 1
    a.get() + b.get()
  })
  // Initial computation
  inspect(sum.get(), content="3")
  inspect(compute_count, content="1")
  // Batch update both inputs
  rt.batch(() => {
    a.set(10)
    b.set(20)
  })
  // Memo should recompute once after batch
  inspect(sum.get(), content="30")
  inspect(compute_count, content="2")
}

///|
test "batch: same-value set is still no-op in batch" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 42)
  rt.batch(() => a.set(42), // same value, should not record pending
  )
  // Same-value optimization still applies
  inspect(rt.current_revision.value, content="0")
}

///|
test "batch: revert detection - set then revert is no-op" {
  // Two-phase values enable detecting when a signal is set and then
  // reverted to its original value within the same batch.
  let rt = Runtime::new()
  let a = Signal::new(rt, 0)
  let mut compute_count = 0
  let doubled = Memo::new(rt, () => {
    compute_count = compute_count + 1
    a.get() * 2
  })
  // Initial
  inspect(doubled.get(), content="0")
  inspect(compute_count, content="1")
  // Batch: set(1) then revert to set(0) — net effect is no change
  rt.batch(() => {
    a.set(1)
    a.set(0)
  })
  // No revision bump because the final value equals the original
  inspect(rt.current_revision.value, content="0")
  // Memo should not need to recompute
  inspect(doubled.get(), content="0")
  inspect(compute_count, content="1")
}

///|
test "batch: multi-signal with mixed changes" {
  // Some signals change, some revert — only actually-changed signals
  // should produce a revision bump.
  let rt = Runtime::new()
  let a = Signal::new(rt, 10)
  let b = Signal::new(rt, 20)
  let c = Signal::new(rt, 30)
  let mut compute_count = 0
  let sum = Memo::new(rt, () => {
    compute_count = compute_count + 1
    a.get() + b.get() + c.get()
  })
  inspect(sum.get(), content="60")
  inspect(compute_count, content="1")
  // Batch: a changes, b reverts, c changes
  rt.batch(() => {
    a.set(100)
    b.set(999)
    b.set(20) // revert to original
    c.set(300)
  })
  // Revision should bump (a and c changed)
  inspect(rt.current_revision.value, content="1")
  inspect(a.get(), content="100")
  inspect(b.get(), content="20") // b is still 20
  inspect(c.get(), content="300")
  inspect(sum.get(), content="420") // 100 + 20 + 300
  inspect(compute_count, content="2")
}

///|
test "batch: diamond dependency with batch" {
  // input -> A -> C
  //       -> B -> C
  let rt = Runtime::new()
  let input = Signal::new(rt, 10)
  let extra = Signal::new(rt, 1)
  let mut a_count = 0
  let a = Memo::new(rt, () => {
    a_count = a_count + 1
    input.get() + 1
  })
  let mut b_count = 0
  let b = Memo::new(rt, () => {
    b_count = b_count + 1
    input.get() + extra.get()
  })
  let mut c_count = 0
  let c = Memo::new(rt, () => {
    c_count = c_count + 1
    a.get() + b.get()
  })
  // Initial
  inspect(c.get(), content="22") // (10+1) + (10+1) = 11 + 11
  inspect(a_count, content="1")
  inspect(b_count, content="1")
  inspect(c_count, content="1")
  // Batch update both inputs at once
  rt.batch(() => {
    input.set(5)
    extra.set(2)
  })
  inspect(c.get(), content="13") // (5+1) + (5+2) = 6 + 7
  inspect(a_count, content="2")
  inspect(b_count, content="2")
  inspect(c_count, content="2")
}

///|
test "batch: raised error rolls back pending writes and restores depth" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let res : Result[Unit, Error] = try? rt.batch(fn() raise {
    sig.set(1)
    raise Stop
  })
  inspect(res is Err(_), content="true")
  inspect(rt.batch_depth, content="0")
  inspect(sig.get(), content="0")
  inspect(rt.current_revision.value, content="0")
  inspect(rt.batch_pending_signals.length(), content="0")
  // Ensure signal remains fully reusable after rollback.
  sig.set(100)
  inspect(sig.get(), content="100")
}

///|
test "batch: nested raised error rolls back entire outer batch" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let res : Result[Unit, Error] = try? rt.batch(fn() raise {
    sig.set(1)
    rt.batch(fn() raise {
      sig.set(2)
      raise Stop
    })
  })
  inspect(res is Err(_), content="true")
  inspect(rt.batch_depth, content="0")
  inspect(sig.get(), content="0")
  inspect(rt.current_revision.value, content="0")
  inspect(rt.batch_pending_signals.length(), content="0")
}

///|
test "batch: failed inner batch_result rolls back before outer continues" {
  let rt = Runtime::new()
  let outer_only = Signal::new(rt, 0)
  let shared = Signal::new(rt, 0)
  let inner_only = Signal::new(rt, 0)

  rt.batch(() => {
    outer_only.set(10)
    shared.set(1)

    let inner = rt.batch_result(fn() raise {
      shared.set(2)
      inner_only.set(99)
      raise Stop
    })
    inspect(inner is Err(_), content="true")

    // Outer batch continues with its own writes.
    outer_only.set(20)
  })

  inspect(outer_only.get(), content="20")
  inspect(shared.get(), content="1")
  inspect(inner_only.get(), content="0")
  inspect(rt.current_revision.value, content="1")
  inspect(rt.batch_pending_signals.length(), content="0")
}

///|
test "batch: raised error does not fire on_change callback" {
  let mut fired = 0
  let rt = Runtime::new(on_change=() => fired = fired + 1)
  let sig = Signal::new(rt, 0)
  let res : Result[Unit, Error] = try? rt.batch(fn() raise {
    sig.set(1)
    raise Stop
  })
  inspect(res is Err(_), content="true")
  inspect(fired, content="0")
  inspect(sig.get(), content="0")
}

///|
test "batch_result: commits on success" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let res = rt.batch_result(() => sig.set(5))
  inspect(res is Ok(_), content="true")
  inspect(sig.get(), content="5")
  inspect(rt.current_revision.value, content="1")
}

///|
test "batch_result: returns Err and rolls back" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let res = rt.batch_result(fn() raise {
    sig.set(5)
    raise Stop
  })
  inspect(res is Err(_), content="true")
  inspect(sig.get(), content="0")
  inspect(rt.current_revision.value, content="0")
}

///|
// Characterization test: this simulates the state left behind if a user
// callback aborts after Runtime::batch increments batch_depth but before
// unwind/commit.
test "batch leak simulation: stale batch_depth defers writes" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  rt.batch_depth = 1
  sig.set(1)
  inspect(sig.get(), content="0")
  inspect(rt.current_revision.value, content="0")
  inspect(rt.batch_pending_signals.length(), content="1")
}

///|
// Characterization test: manual cleanup of leaked batch state restores normal
// operation and commits pending writes.
test "batch leak simulation: manual cleanup recovers state" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  rt.batch_depth = 1
  sig.set(1)
  rt.batch_depth = 0
  rt.commit_batch()
  inspect(sig.get(), content="1")
  inspect(rt.current_revision.value, content="1")
  inspect(rt.batch_pending_signals.length(), content="0")
}

///|
test "panic batch: corrupted negative batch_depth triggers underflow abort" {
  let rt = Runtime::new()
  // Directly corrupt batch_depth to simulate a future bug where an internal
  // decrement site is added without a matching increment.
  // batch() will: +1 (to 0), run f(), -1 (to -1), then hit the guard.
  rt.batch_depth = -1
  rt.batch(() => ())
}

///|
// Trigger commit_batch with a signal whose commit_pending is None —
// simulates internal state corruption (missing commit closure).
test "panic commit_batch: signal with None commit_pending aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  // Manually enter batch mode by directly setting batch_depth
  rt.batch_depth = 1
  // set() detects batch_depth > 0 and calls set_batch, which registers
  // commit_pending and enqueues the cell id in batch_pending_signals
  sig.set(1)
  // Corrupt the commit_pending closure
  let meta = rt.get_cell(sig.id())
  meta.commit_pending = None
  // Manually exit batch and trigger commit_batch
  rt.batch_depth = 0
  rt.commit_batch()
}
