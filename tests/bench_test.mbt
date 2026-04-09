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
  ignore(m.get()) // prime
  b.bench(fn() { b.keep(m.get()) })
}

///|
test "memo: get stale (signal changed, recompute)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let m = Memo::new(rt, () => sig.get() * 2)
  ignore(m.get()) // prime
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    b.keep(m.get())
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
  ignore(leaf.get()) // prime
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    b.keep(leaf.get())
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
    ignore(memos[i].get()) // prime all
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    for i = 0; i < width; i = i + 1 {
      b.keep(memos[i].get())
    }
  })
}

///|
test "hybrid: get warm (up-to-date, no recompute)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let h = @incr.HybridMemo::new(rt, () => sig.get() * 2)
  ignore(h.get()) // prime
  b.bench(fn() { b.keep(h.get()) })
}

///|
test "hybrid: get stale (signal changed, recompute)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let h = @incr.HybridMemo::new(rt, () => sig.get() * 2)
  ignore(h.get()) // prime
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    b.keep(h.get())
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
  // arrays because there's no dispose mechanism yet. This measures whether
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
test "baseline: push propagation with 0 reactives" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
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
    ignore(m.get())
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
