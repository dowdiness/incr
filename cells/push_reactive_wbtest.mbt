///|
test "runtime: push arrays start empty" {
  let rt = Runtime::new()
  inspect(rt.push.reactives.length(), content="0")
  inspect(rt.push.effects.length(), content="0")
  inspect(rt.push.free_reactives.length(), content="0")
  inspect(rt.push.free_effects.length(), content="0")
  inspect(rt.push.node_count, content="0")
}

///|
test "free list: reactive slot reused after dispose" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get())
  let _ = rt.read_reactive(r)
  let r_idx = match rt.core.cell_index[r.id().id] {
    PushReactive(i) => i
    _ => abort("expected PushReactive")
  }
  r.dispose()
  inspect(rt.push.free_reactives.length(), content="1")
  let r2 = Reactive::new(rt, () => s.get() + 1)
  let _ = rt.read_reactive(r2)
  let r2_idx = match rt.core.cell_index[r2.id().id] {
    PushReactive(i) => i
    _ => abort("expected PushReactive")
  }
  inspect(r2_idx, content=r_idx.to_string())
  inspect(rt.push.reactives.length(), content="1")
  inspect(rt.push.free_reactives.length(), content="0")
}

///|
test "free list: effect slot reused after dispose" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let mut log : Array[Int] = []
  let e = Effect::new(rt, () => log.push(s.get()))
  let e_idx = match rt.core.cell_index[e.cell_id.id] {
    PushEffect(i) => i
    _ => abort("expected PushEffect")
  }
  e.dispose()
  inspect(rt.push.free_effects.length(), content="1")
  let mut log2 : Array[Int] = []
  let e2 = Effect::new(rt, () => log2.push(s.get() * 2))
  let e2_idx = match rt.core.cell_index[e2.cell_id.id] {
    PushEffect(i) => i
    _ => abort("expected PushEffect")
  }
  inspect(e2_idx, content=e_idx.to_string())
  inspect(rt.push.effects.length(), content="1")
  inspect(rt.push.free_effects.length(), content="0")
  s.set(3)
  inspect(log, content="[1]") // e was disposed; did not re-run
  inspect(log2, content="[2, 6]") // e2 ran on creation and on s.set(3)
}

///|
test "runtime: push_node_count tracks live push cells" {
  let rt = Runtime::new()
  inspect(rt.push.node_count, content="0")
  let s = Signal::new(rt, 0)
  let r = Reactive::new(rt, () => s.get())
  inspect(rt.push.node_count, content="1")
  let e = Effect::new(rt, () => {
    let _ = s.get()
    ()
  })
  inspect(rt.push.node_count, content="2")
  r.dispose()
  inspect(rt.push.node_count, content="1")
  e.dispose()
  inspect(rt.push.node_count, content="0")
}

///|
test "cell_ref: PushReactive, PushEffect, Disposed variants exist" {
  let a : CellRef = CellRef::PushReactive(0)
  let b : CellRef = CellRef::PushEffect(2)
  let c : CellRef = CellRef::Disposed
  let ia = match a {
    PushReactive(i) => i
    _ => -1
  }
  let ib = match b {
    PushEffect(i) => i
    _ => -1
  }
  let ok = match c {
    Disposed => true
    _ => false
  }
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
  inspect(rt.read_reactive(r), content="11") // s=1, m=10, r=11
  s.set(3)
  inspect(rt.read_reactive(r), content="31") // s=3, m=30, r=31
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
    r0.get() + // subscriber of r0 (level 1) → push level = 2
    1
  })
  r2_ref.val = Some(r2)
  inspect(count, content="1") // initial compute
  // r0 (level 1) dequeues before r2 (level 2) → r0 runs first → disposes r2
  // r2's pre-seeded queue entry is stale → disposal check must skip it
  s.set(1)
  inspect(count, content="1") // r2 was disposed; stale entry skipped
}

///|
test "panic reactive: get after dispose aborts" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let r = Reactive::new(rt, () => s.get())
  r.dispose()
  let _ = rt.read_reactive(r) // disposed reactive → abort
}

///|
test "panic reactive: cross-runtime get aborts" {
  let rt_a = Runtime::new()
  let rt_b = Runtime::new()
  let s_b = Signal::new(rt_b, 10)
  let reactive_b = Reactive::new(rt_b, () => s_b.get())
  // memo_a computes on rt_a but reads reactive_b from rt_b → abort
  let memo_a = Memo::new(rt_a, () => reactive_b.get())
  let _ = rt_a.read(memo_a)
}

// ─── Task 3: push_propagate_from ────────────────────────────────────────────

///|
test "push propagation: basic reactive chain Signal → Reactive" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get() * 2)
  let _ = rt.read_reactive(r) // initial: 2
  s.set(5) // triggers push propagation
  inspect(rt.read_reactive(r), content="10")
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
  let _ = rt.read_reactive(d) // a=1: b=2, c=10, d=12
  a.set(5) // a=5: b=6, c=50, d=56
  let _ = rt.read_reactive(d)
  inspect(saw_glitch, content="false")
  inspect(rt.read_reactive(d), content="56")
}

// ─── Task 4: level helpers + early cutoff ───────────────────────────────────

///|
test "level: reactive level is source max + 1" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r1 = Reactive::new(rt, () => s.get())
  let r2 = Reactive::new(rt, () => r1.get() + 1)
  let _ = rt.read_reactive(r1)
  let _ = rt.read_reactive(r2)
  let r1_idx = match rt.core.cell_index[r1.id().id] {
    PushReactive(i) => i
    _ => abort("expected PushReactive")
  }
  let r2_idx = match rt.core.cell_index[r2.id().id] {
    PushReactive(i) => i
    _ => abort("expected PushReactive")
  }
  inspect(rt.push.reactives[r1_idx].level, content="1")
  inspect(rt.push.reactives[r2_idx].level, content="2")
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
  let _ = downstream.get_untracked()
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
  inspect(rt.read_reactive(r), content="30")
  inspect(rt.read_reactive(r), content="30") // cached
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
  let _ = rt.read_reactive(r)
  rt.batch(() => {
    s.set(5)
    inspect(rt.read_reactive(r), content="0") // not yet propagated inside batch
  })
  inspect(rt.read_reactive(r), content="10") // propagated after commit
}

///|
test "mixed pull/push: Memo reads Reactive; Reactive reads Signal" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get() + 1)
  let m = Memo::new(rt, () => r.get() * 10)
  s.set(4)
  inspect(rt.read(m), content="50") // r = 5, m = 50
}

// ─── Task 7: disposal ────────────────────────────────────────────────────────

///|
test "dispose: sources' subscriber sets updated after reactive dispose" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get())
  let _ = r.get_untracked()
  let s_idx = match rt.core.cell_index[s.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  inspect(rt.pull.signals[s_idx].meta.subscribers.length(), content="1")
  r.dispose()
  inspect(rt.pull.signals[s_idx].meta.subscribers.length(), content="0")
}

///|
test "dispose: disposed reactive not reachable via subscriber walk" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get() * 2)
  let _ = r.get_untracked()
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
