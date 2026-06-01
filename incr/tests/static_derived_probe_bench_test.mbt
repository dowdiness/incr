///|
/// Probe for the static/applicative `Derived` fast-path idea.
///
/// These are benchmark-only lower-bound comparisons, not an API proposal.
/// The `dynamic Derived` rows measure today's fixed-shape computations through
/// the ordinary dynamically tracked `Derived` engine. The `manual fixed-dep`
/// rows do the same input reads and result equality check directly, without
/// tracking-stack frames or dependency-list diffing. The gap is the maximum
/// headroom a future `map` / `map2` / `map3` static-dependency API could hope to
/// recover before paying its own integration costs.

///|
test "applicative-probe: map1 dynamic Derived stale" (b : @bench.T) {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 0)
  let derived = @incr.Derived(rt, () => input.get() + 1)
  ignore(derived.read_or_abort())
  let mut v = 0
  b.bench(fn() {
    v += 1
    input.set(v)
    b.keep(derived.read_or_abort())
  })
}

///|
test "applicative-probe: map1 manual fixed-dep lower bound" (b : @bench.T) {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 0)
  let cached : Ref[Int] = { val: input.get() + 1 }
  let mut v = 0
  b.bench(fn() {
    v += 1
    input.set(v)
    let next = input.get() + 1
    if cached.val != next {
      cached.val = next
    }
    b.keep(cached.val)
  })
}

///|
test "applicative-probe: map2 dynamic Derived stale" (b : @bench.T) {
  let rt = @incr.Runtime()
  let left = @incr.Input(rt, 0)
  let right = @incr.Input(rt, 10)
  let derived = @incr.Derived(rt, () => left.get() + right.get())
  ignore(derived.read_or_abort())
  let mut v = 0
  b.bench(fn() {
    v += 1
    left.set(v)
    b.keep(derived.read_or_abort())
  })
}

///|
test "applicative-probe: map2 manual fixed-dep lower bound" (b : @bench.T) {
  let rt = @incr.Runtime()
  let left = @incr.Input(rt, 0)
  let right = @incr.Input(rt, 10)
  let cached : Ref[Int] = { val: left.get() + right.get() }
  let mut v = 0
  b.bench(fn() {
    v += 1
    left.set(v)
    let next = left.get() + right.get()
    if cached.val != next {
      cached.val = next
    }
    b.keep(cached.val)
  })
}

///|
test "applicative-probe: map3 dynamic Derived stale" (b : @bench.T) {
  let rt = @incr.Runtime()
  let first = @incr.Input(rt, 0)
  let second = @incr.Input(rt, 10)
  let third = @incr.Input(rt, 100)
  let derived = @incr.Derived(rt, () => first.get() + second.get() + third.get())
  ignore(derived.read_or_abort())
  let mut v = 0
  b.bench(fn() {
    v += 1
    first.set(v)
    b.keep(derived.read_or_abort())
  })
}

///|
test "applicative-probe: map3 manual fixed-dep lower bound" (b : @bench.T) {
  let rt = @incr.Runtime()
  let first = @incr.Input(rt, 0)
  let second = @incr.Input(rt, 10)
  let third = @incr.Input(rt, 100)
  let cached : Ref[Int] = { val: first.get() + second.get() + third.get() }
  let mut v = 0
  b.bench(fn() {
    v += 1
    first.set(v)
    let next = first.get() + second.get() + third.get()
    if cached.val != next {
      cached.val = next
    }
    b.keep(cached.val)
  })
}
