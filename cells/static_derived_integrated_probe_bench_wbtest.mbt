///|
/// Integrated static/applicative `Derived` prototype benchmarks.
///
/// The static rows use the private generalized `StaticDerivedProbe` path from
/// `static_derived_probe.mbt`: a real pull backend entry with fixed
/// dependencies, existing `pull_verify`, and no dynamic tracking frame or
/// dependency-list diff on recompute. This remains benchmark-only and is not a
/// public API proposal.

///|
test "integrated-applicative-probe: map1 dynamic Derived stale" (b : @bench.T) {
  let rt = Runtime()
  let input = Input(rt, 0)
  let derived = Derived(rt, () => input.get() + 1)
  ignore(derived.read_or_abort())
  let mut v = 0
  b.bench(fn() {
    v += 1
    input.set(v)
    b.keep(derived.read_or_abort())
  })
}

///|
test "integrated-applicative-probe: map1 static Derived prototype stale" (
  b : @bench.T,
) {
  let rt = Runtime()
  let input = Input(rt, 0)
  let derived = static_derived_map1_probe(input, x => x + 1)
  ignore(derived.read_or_abort())
  let mut v = 0
  b.bench(fn() {
    v += 1
    input.set(v)
    b.keep(derived.read_or_abort())
  })
}

///|
test "integrated-applicative-probe: map2 dynamic Derived stale" (b : @bench.T) {
  let rt = Runtime()
  let left = Input(rt, 0)
  let right = Input(rt, 10)
  let derived = Derived(rt, () => left.get() + right.get())
  ignore(derived.read_or_abort())
  let mut v = 0
  b.bench(fn() {
    v += 1
    left.set(v)
    b.keep(derived.read_or_abort())
  })
}

///|
test "integrated-applicative-probe: map2 static Derived prototype stale" (
  b : @bench.T,
) {
  let rt = Runtime()
  let left = Input(rt, 0)
  let right = Input(rt, 10)
  let derived = static_derived_map2_probe(left, right, (l, r) => l + r)
  ignore(derived.read_or_abort())
  let mut v = 0
  b.bench(fn() {
    v += 1
    left.set(v)
    b.keep(derived.read_or_abort())
  })
}

///|
test "integrated-applicative-probe: map3 dynamic Derived stale" (b : @bench.T) {
  let rt = Runtime()
  let first = Input(rt, 0)
  let second = Input(rt, 10)
  let third = Input(rt, 100)
  let derived = Derived(rt, () => first.get() + second.get() + third.get())
  ignore(derived.read_or_abort())
  let mut v = 0
  b.bench(fn() {
    v += 1
    first.set(v)
    b.keep(derived.read_or_abort())
  })
}

///|
test "integrated-applicative-probe: map3 static Derived prototype stale" (
  b : @bench.T,
) {
  let rt = Runtime()
  let first = Input(rt, 0)
  let second = Input(rt, 10)
  let third = Input(rt, 100)
  let derived = static_derived_map3_probe(first, second, third, (a, b, c) => {
    a + b + c
  })
  ignore(derived.read_or_abort())
  let mut v = 0
  b.bench(fn() {
    v += 1
    first.set(v)
    b.keep(derived.read_or_abort())
  })
}
