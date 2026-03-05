///|
test "runtime: push arrays start empty" {
  let rt = Runtime::new()
  inspect(rt.push_reactives.length(), content="0")
  inspect(rt.push_effects.length(), content="0")
  inspect(rt.free_push_reactives.length(), content="0")
  inspect(rt.free_push_effects.length(), content="0")
  inspect(rt.push_node_count, content="0")
}

///|
test "runtime: push_node_count tracks live push cells" {
  let rt = Runtime::new()
  inspect(rt.push_node_count, content="0")
  let s = Signal::new(rt, 0)
  let r = Reactive::new(rt, () => s.get())
  inspect(rt.push_node_count, content="1")
  let e = Effect::new(rt, () => { let _ = s.get(); () })
  inspect(rt.push_node_count, content="2")
  r.dispose()
  inspect(rt.push_node_count, content="1")
  e.dispose()
  inspect(rt.push_node_count, content="0")
}

///|
test "cell_ref: PushReactive, PushEffect, Disposed variants exist" {
  let a : CellRef = CellRef::PushReactive(0)
  let b : CellRef = CellRef::PushEffect(2)
  let c : CellRef = CellRef::Disposed
  let ia = match a { PushReactive(i) => i; _ => -1 }
  let ib = match b { PushEffect(i) => i; _ => -1 }
  let ok = match c { Disposed => true; _ => false }
  inspect(ia, content="0")
  inspect(ib, content="2")
  inspect(ok, content="true")
}

// ─── P1 regression tests (review fixes) ──────────────────────────────────────

///|
test "push propagation: signal → memo → reactive chain (pull-memo bridge)" {
  // Signal → PullMemo → Reactive must propagate eagerly.
  // enqueue_push_subscribers must traverse through pull memos to reach push nodes.
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let m = Memo::new(rt, () => s.get() * 10)
  let r = Reactive::new(rt, () => m.get() + 1)
  inspect(r.get(), content="11") // s=1, m=10, r=11
  s.set(3)
  inspect(r.get(), content="31") // s=3, m=30, r=31
}

///|
test "push propagation: skip stale queue entry after mid-wave disposal" {
  // r0 is at push level 1 (reads signal s directly).
  // r2 is at push level 2 (reads BOTH s and r0 → max(0,1)+1=2).
  // When s changes, both are seeded directly from s's subscriber set.
  // Level 1 dequeues before level 2, so r0 always runs first.
  // r0 disposes r2; r2's stale level-2 queue entry must be skipped.
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let mut count = 0
  let r2_ref : Ref[Reactive[Int]?] = { val: None }
  // r0 (level 1): reads s; when s > 0, disposes r2
  let r0 = Reactive::new(rt, () => {
    let v = s.get()
    if v > 0 {
      match r2_ref.val {
        Some(r) => r.dispose()
        None => ()
      }
    }
    v
  })
  // r2 (level 2): reads s (pre-seeds from signal) AND r0 (raises level to 2)
  let r2 = Reactive::new(rt, () => {
    count += 1
    let _ = s.get() // subscriber of s → pre-seeded when s changes
    r0.get() + 1 // subscriber of r0 (level 1) → push level = 2
  })
  r2_ref.val = Some(r2)
  inspect(count, content="1") // initial compute
  // r0 (level 1) dequeues before r2 (level 2) → r0 runs first → disposes r2
  // r2's pre-seeded queue entry is stale → disposal check must skip it
  s.set(1)
  inspect(count, content="1") // r2 was disposed; stale entry skipped
}

// ─── Task 3: push_propagate_from ────────────────────────────────────────────

///|
test "push propagation: basic reactive chain Signal → Reactive" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get() * 2)
  let _ = r.get() // initial: 2
  s.set(5) // triggers push propagation
  inspect(r.get(), content="10")
}

///|
test "push propagation: glitch prevention in diamond" {
  // a → b(a+1), a → c(a*10), b+c → d
  // d should never see an inconsistent (b,c) pair
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let b = Reactive::new(rt, () => a.get() + 1)
  let c = Reactive::new(rt, () => a.get() * 10)
  let mut saw_glitch = false
  let d = Reactive::new(rt, () => {
    let bv = b.get()
    let cv = c.get()
    // Invariant: bv - 1 == cv / 10 (both sides equal current value of a)
    if bv - 1 != cv / 10 {
      saw_glitch = true
    }
    bv + cv
  })
  let _ = d.get() // a=1: b=2, c=10, d=12
  a.set(5) // a=5: b=6, c=50, d=56
  let _ = d.get()
  inspect(saw_glitch, content="false")
  inspect(d.get(), content="56")
}

// ─── Task 4: level helpers + early cutoff ───────────────────────────────────

///|
test "level: reactive level is source max + 1" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r1 = Reactive::new(rt, () => s.get())
  let r2 = Reactive::new(rt, () => r1.get() + 1)
  let _ = r1.get()
  let _ = r2.get()
  let r1_idx = match rt.cell_index[r1.id().id] {
    PushReactive(i) => i
    _ => abort("expected PushReactive")
  }
  let r2_idx = match rt.cell_index[r2.id().id] {
    PushReactive(i) => i
    _ => abort("expected PushReactive")
  }
  inspect(rt.push_reactives[r1_idx].level, content="1")
  inspect(rt.push_reactives[r2_idx].level, content="2")
}

///|
test "early cutoff: unchanged value does not propagate to downstream" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  // reads s but always returns 5
  let always5 = Reactive::new(rt, () => {
    let _ = s.get()
    5
  })
  let mut count = 0
  let downstream = Reactive::new(rt, () => {
    count += 1
    always5.get()
  })
  let _ = downstream.get()
  inspect(count, content="1")
  s.set(99) // always5 recomputes to 5 again → downstream not re-enqueued
  inspect(count, content="1")
}

// ─── Task 5: Reactive::get / Effect ─────────────────────────────────────────

///|
test "reactive: get() returns cached value" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let r = Reactive::new(rt, () => s.get() * 3)
  inspect(r.get(), content="30")
  inspect(r.get(), content="30") // cached
}

///|
test "effect: runs on creation, then re-runs on each dependency change" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let mut log : Array[Int] = []
  let _e = Effect::new(rt, () => log.push(s.get()))
  inspect(log, content="[0]")
  s.set(1)
  inspect(log, content="[0, 1]")
  s.set(2)
  inspect(log, content="[0, 1, 2]")
}

// ─── Task 6: batch + mixed pull/push ────────────────────────────────────────

///|
test "push: batch commit triggers propagation" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let r = Reactive::new(rt, () => s.get() * 2)
  let _ = r.get()
  rt.batch(() => {
    s.set(5)
    inspect(r.get(), content="0") // not yet propagated inside batch
  })
  inspect(r.get(), content="10") // propagated after commit
}

///|
test "mixed pull/push: Memo reads Reactive; Reactive reads Signal" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get() + 1)
  let m = Memo::new(rt, () => r.get() * 10)
  s.set(4)
  inspect(m.get(), content="50") // r = 5, m = 50
}

// ─── Task 7: disposal ────────────────────────────────────────────────────────

///|
test "dispose: sources' subscriber sets updated after reactive dispose" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get())
  let _ = r.get()
  let s_idx = match rt.cell_index[s.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  inspect(rt.pull_signals[s_idx].subscribers.length(), content="1")
  r.dispose()
  inspect(rt.pull_signals[s_idx].subscribers.length(), content="0")
}

///|
test "dispose: disposed reactive not reachable via subscriber walk" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get() * 2)
  let _ = r.get()
  r.dispose()
  let subs = rt.get_subscribers(s.id()).collect()
  inspect(subs.length(), content="0")
}

///|
test "dispose: effect removed from source subscriber set" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let mut log : Array[Int] = []
  let e = Effect::new(rt, () => log.push(s.get()))
  inspect(log, content="[0]")
  e.dispose()
  s.set(1) // effect is gone; log should not grow
  inspect(log, content="[0]")
}
