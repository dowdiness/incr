///|
test "signal: get" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  b.bench(fn() { b.keep(sig.get()) })
}

///|
test "signal: set same value (no-op)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  b.bench(fn() { sig.set(0) })
}

///|
test "signal: set new value" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
  })
}

///|
test "memo: get warm (up-to-date, no recompute)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let m = Memo::new(rt, () => sig.get() * 2)
  ignore(rt.read(m)) // prime
  b.bench(fn() { b.keep(rt.read(m)) })
}

///|
test "memo: get stale (signal changed, recompute)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let m = Memo::new(rt, () => sig.get() * 2)
  ignore(rt.read(m)) // prime
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    b.keep(rt.read(m))
  })
}

///|
test "memo: deep chain get (100 levels, stale)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let depth = 100
  let memos : Array[Memo[Int]] = []
  memos.push(Memo::new(rt, () => sig.get()))
  for i = 1; i < depth; i = i + 1 {
    let prev = memos[i - 1]
    memos.push(Memo::new(rt, () => prev.get() + 1))
  }
  let leaf = memos[depth - 1]
  ignore(rt.read(leaf)) // prime
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    b.keep(rt.read(leaf))
  })
}

///|
test "memo: wide fanout get (1 signal, 50 memos, stale)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let width = 50
  let memos : Array[Memo[Int]] = []
  for i = 0; i < width; i = i + 1 {
    let multiplier = i + 1
    memos.push(Memo::new(rt, () => sig.get() * multiplier))
  }
  for i = 0; i < width; i = i + 1 {
    ignore(rt.read(memos[i])) // prime all
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    for i = 0; i < width; i = i + 1 {
      b.keep(rt.read(memos[i]))
    }
  })
}

///|
test "hybrid: get warm (up-to-date, no recompute)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let h = @incr.HybridMemo::new(rt, () => sig.get() * 2)
  ignore(rt.read_hybrid(h)) // prime
  b.bench(fn() { b.keep(rt.read_hybrid(h)) })
}

///|
test "hybrid: get stale (signal changed, recompute)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let h = @incr.HybridMemo::new(rt, () => sig.get() * 2)
  ignore(rt.read_hybrid(h)) // prime
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    b.keep(rt.read_hybrid(h))
  })
}

///|
test "batch: 10 signals, single revision" (b : @bench.T) {
  let rt = Runtime::new()
  let sigs : Array[Signal[Int]] = []
  for i = 0; i < 10; i = i + 1 {
    sigs.push(Signal::new(rt, i))
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    let cv = v
    rt.batch(fn() {
      for i = 0; i < 10; i = i + 1 {
        sigs[i].set(cv)
      }
    })
  })
}

///|
test "baseline: signal.set with clean runtime" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
}

///|
test "baseline: signal.set with 10k unreferenced memos" (b : @bench.T) {
  // Memos are created and immediately dropped. They persist in the SoA
  // arrays because they are not explicitly disposed. This measures whether
  // accumulated SoA entries affect signal.set performance.
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  for i = 0; i < 10_000; i = i + 1 {
    let idx = i
    ignore(Memo::new(rt, fn() { sig.get() + idx }))
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
}

///|
test "baseline: memo creation cost (monotonic SoA growth)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  b.bench(fn() { ignore(Memo::new(rt, fn() { sig.get() })) })
}

///|
test "baseline: push propagation with 100 live reactives" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let reactives : Array[@incr.Reactive[Int]] = []
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    reactives.push(@incr.Reactive::new(rt, fn() { sig.get() + idx }))
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
  ignore(reactives)
}

///|
test "baseline: push propagation with 100 disposed reactives" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    let r = @incr.Reactive::new(rt, fn() { sig.get() + idx })
    r.dispose()
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
}

///|
test "baseline: push propagation with 100 abandoned reactives (handle dropped)" (
  b : @bench.T,
) {
  // User dropped handle but reactive is still live in SoA — push still
  // propagates through it. This is the CPU waste GC should eliminate.
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    ignore(@incr.Reactive::new(rt, fn() { sig.get() + idx }))
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
}

///|
test "baseline: reactive create-dispose cycle (existing free list)" (
  b : @bench.T,
) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  b.bench(fn() {
    let r = @incr.Reactive::new(rt, fn() { sig.get() })
    r.dispose()
  })
}

///|
test "layer1: memo create-dispose cycle (free list)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  b.bench(fn() {
    let m = Memo::new(rt, fn() { sig.get() })
    ignore(rt.read(m))
    m.dispose()
  })
}

///|
test "layer1: signal create-dispose cycle (free list)" (b : @bench.T) {
  let rt = Runtime::new()
  b.bench(fn() {
    let sig = Signal::new(rt, 0)
    sig.dispose()
  })
}

///|
test "layer2: scope create and dispose (empty)" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  b.bench(fn() {
    let scope = @incr.Scope::new(rt)
    scope.dispose()
  })
}

///|
test "layer2: scope create 10 signals and dispose" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  b.bench(fn() {
    let scope = @incr.Scope::new(rt)
    for i in 0..<10 {
      let _ = scope.signal(i)
    }
    scope.dispose()
  })
}

///|
test "layer2: scope bulk dispose 100 mixed cells" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  b.bench(fn() {
    let scope = @incr.Scope::new(rt)
    for i in 0..<50 {
      let _ = scope.signal(i)
    }
    for _ in 0..<50 {
      let _ = scope.memo(fn() { 0 })
    }
    scope.dispose()
  })
}

///|
test "layer2: nested scope (3 levels) create and dispose" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  b.bench(fn() {
    let root = @incr.Scope::new(rt)
    let mid = root.child()
    let leaf = mid.child()
    let _ = root.signal(1)
    let _ = mid.signal(2)
    let _ = leaf.signal(3)
    root.dispose()
  })
}

///|
// ─── Layer 4a: Observer + gc() ──────────────────────────────────────────────

///|
test "observer: get warm (memo)" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 42)
  let m = @incr.Memo::new(rt, fn() { sig.get() * 2 })
  let obs = m.observe()
  ignore(obs.get()) // prime
  b.bench(fn() { b.keep(obs.get()) })
  obs.dispose()
}

///|
test "observer: observe + dispose cycle" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 42)
  let m = @incr.Memo::new(rt, fn() { sig.get() * 2 })
  ignore(rt.read(m)) // prime
  b.bench(fn() {
    let obs = m.observe()
    b.keep(obs.get())
    obs.dispose()
  })
}

///|
test "gc: sweep 1k all-live" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 1)
  let observers : Array[@incr.Observer[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let m = @incr.Memo::new(rt, fn() { sig.get() + i })
    let obs = m.observe()
    ignore(obs.get())
    observers.push(obs)
  }
  b.bench(fn() { rt.gc() })
  for obs in observers {
    obs.dispose()
  }
}

///|
test "gc: sweep 1k all-dead" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 1)
  for i = 0; i < 1000; i = i + 1 {
    let m = @incr.Memo::new(rt, fn() { sig.get() + i })
    ignore(rt.read(m))
  }
  // First gc disposes all, subsequent gcs are sweeps over Disposed entries
  rt.gc()
  b.bench(fn() { rt.gc() })
}

///|
test "gc: sweep 1k 50pct dead" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 1)
  let observers : Array[@incr.Observer[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let m = @incr.Memo::new(rt, fn() { sig.get() + i })
    let obs = m.observe()
    ignore(obs.get())
    if i % 2 == 0 {
      obs.dispose()
    } else {
      observers.push(obs)
    }
  }
  b.bench(fn() { rt.gc() })
  for obs in observers {
    obs.dispose()
  }
}

///|
test "runtime: read one-shot" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  let sig = @incr.Signal::new(rt, 42)
  let m = @incr.Memo::new(rt, fn() { sig.get() * 2 })
  ignore(rt.read(m)) // prime
  b.bench(fn() { b.keep(rt.read(m)) })
}

///|
/// Measures fixpoint convergence on a stable relation (no pending delta).
/// This is the common driver pattern: drivers batch inserts, then call
/// fixpoint to check for convergence. After the prime run, deltas are empty
/// and fixpoint returns after detecting stable state. Gates Stage 3g of
/// the R1 kernel split plan.
test "fixpoint: one iteration, empty delta (stable convergence)" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  let rel : @incr.Relation[Int] = @incr.Relation::new(rt, label="R")
  let _ = rel.insert(42)
  rt.fixpoint() // prime: converge to stable state
  b.bench(fn() { rt.fixpoint() })
}

///|
/// Measures fixpoint with a non-empty delta each iteration: inserts a
/// fresh fact, runs one rule that copies the delta into a derived
/// relation, converges. Exercises the productive path through
/// `datalog_fixpoint.run_fixpoint` and its tail `publish_cell_changes`
/// call. Gates Stage 3g of the R1 kernel split plan.
test "fixpoint: one iteration, single fact delta (identity rule)" (b : @bench.T) {
  let rt = @incr.Runtime::new()
  let rel : @incr.Relation[Int] = @incr.Relation::new(rt, label="R")
  let derived : @incr.Relation[Int] = @incr.Relation::new(rt, label="D")
  let _ = rt.new_rule([rel.id()], [derived.id()], () => {
    for d in rel.delta_iter() {
      derived.insert(d) |> ignore
    }
  })
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    rel.insert(v) |> ignore
    rt.fixpoint()
  })
}
