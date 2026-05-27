///|
/// UI-shaped benchmarks for the private static `Derived` probe.
///
/// These mirror the `tests/ui_shape_bench_test.mbt` layered and tree shapes,
/// which are the shapes where fixed-dependency derived nodes can replace
/// dynamically tracked `Derived` nodes. Flat and sparse shapes contain only
/// inputs plus eager leaves, so they have no static-derived variant.

///|
test "ui-static-probe: layered 1000 eager via dynamic Derived" (b : @bench.T) {
  let rt = Runtime()
  let input = Input(rt, 0)
  let derived = Derived(rt, () => input.get() * 2)
  let leaves : Array[EagerDerived[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let idx = i
    leaves.push(EagerDerived(rt, () => derived.get_or_abort() + idx))
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    input.set(v)
  })
  ignore(leaves)
}

///|
test "ui-static-probe: layered 1000 eager via static Derived" (b : @bench.T) {
  let rt = Runtime()
  let input = Input(rt, 0)
  let derived = static_derived_map1_probe(input, x => x * 2)
  let leaves : Array[EagerDerived[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let idx = i
    leaves.push(EagerDerived(rt, () => derived.get_or_abort() + idx))
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    input.set(v)
  })
  ignore(leaves)
}

///|
test "ui-static-probe: tree 1023 dynamic Derived + 512 eager leaves" (
  b : @bench.T,
) {
  let rt = Runtime()
  let input = Input(rt, 0)
  let nodes : Array[Derived[Int]] = []
  nodes.push(Derived(rt, () => input.get()))
  for i = 0; i < 511; i = i + 1 {
    let parent = nodes[i]
    let li = 2 * i + 1
    let ri = 2 * i + 2
    nodes.push(Derived(rt, () => parent.get_or_abort() + li))
    nodes.push(Derived(rt, () => parent.get_or_abort() + ri))
  }
  let leaves : Array[EagerDerived[Int]] = []
  for i = 511; i < 1023; i = i + 1 {
    let node = nodes[i]
    leaves.push(EagerDerived(rt, () => node.get_or_abort()))
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    input.set(v)
  })
  ignore(leaves)
}

///|
test "ui-static-probe: tree 1023 static Derived + 512 eager leaves" (
  b : @bench.T,
) {
  let rt = Runtime()
  let input = Input(rt, 0)
  let nodes : Array[StaticDerivedProbe[Int]] = []
  nodes.push(static_derived_map1_probe(input, x => x))
  for i = 0; i < 511; i = i + 1 {
    let parent = nodes[i]
    let li = 2 * i + 1
    let ri = 2 * i + 2
    nodes.push(static_derived_map_static1_probe(parent, x => x + li))
    nodes.push(static_derived_map_static1_probe(parent, x => x + ri))
  }
  let leaves : Array[EagerDerived[Int]] = []
  for i = 511; i < 1023; i = i + 1 {
    let node = nodes[i]
    leaves.push(EagerDerived(rt, () => node.get_or_abort()))
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    input.set(v)
  })
  ignore(leaves)
}
