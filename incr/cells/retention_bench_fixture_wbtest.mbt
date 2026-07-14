///|
fn build_primed_pull_retention_fixture(n : Int) -> (Runtime, Input[Int]) {
  let rt = Runtime()
  let root = Input(rt, 0, label="root")
  for i in 0..<n {
    let offset = i
    let derived = Derived(rt, () => root.get() + offset)
    ignore(derived.read_or_abort())
  }
  (rt, root)
}

///|
fn build_retained_chain_fixture(n : Int, depth : Int) -> (Runtime, Input[Int]) {
  let rt = Runtime()
  let root = Input(rt, 0, label="root")
  for chain in 0..<n {
    let offset = chain
    let mut leaf = Derived(rt, () => root.get() + offset)
    for _ in 1..<depth {
      let previous = leaf
      leaf = Derived(rt, () => previous.get_or_abort() + 1)
    }
    ignore(leaf.read_or_abort())
  }
  ignore(EagerDerived(rt, () => root.get()))
  (rt, root)
}

///|
test "retention fixture: primed pull node total matches N plus root" {
  let n = 1_000
  let (rt, root) = build_primed_pull_retention_fixture(n)
  assert_eq(rt.dependents(root.id()).length(), n)
  assert_eq(rt.core.cell_index.length(), n + 1)
  assert_eq(rt.core.cell_ops.length(), n + 1)
}

///|
test "retention fixture: chain depth changes total nodes, not root fanout" {
  let n = 1_000
  let (depth1_rt, depth1_root) = build_retained_chain_fixture(n, 1)
  let (depth4_rt, depth4_root) = build_retained_chain_fixture(n, 4)
  assert_eq(depth1_rt.dependents(depth1_root.id()).length(), n + 1)
  assert_eq(depth4_rt.dependents(depth4_root.id()).length(), n + 1)
  assert_eq(depth1_rt.core.cell_index.length(), n + 2)
  assert_eq(depth1_rt.core.cell_ops.length(), n + 2)
  assert_eq(depth4_rt.core.cell_index.length(), n * 4 + 2)
  assert_eq(depth4_rt.core.cell_ops.length(), n * 4 + 2)
}
