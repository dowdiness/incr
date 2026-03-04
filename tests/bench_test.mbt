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
