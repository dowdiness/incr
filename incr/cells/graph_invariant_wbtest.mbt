///|
/// Random graph operation for pull-mode invariant probing.
enum GraphOp {
  SetA(Int)
  SetB(Int)
  ReadSum
  ReadDoubled
  ToggleFlag
  ReadPick
} derive(Debug)

///|
struct GraphFixture {
  rt : Runtime
  input_a : Input[Int]
  input_b : Input[Int]
  flag : Input[Bool]
  sum : Derived[Int]
  doubled : Derived[Int]
  pick : Derived[Int]
}

///|
fn build_graph_fixture() -> GraphFixture {
  let rt = Runtime()
  let input_a = Input(rt, 0)
  let input_b = Input(rt, 0)
  let flag = Input(rt, true)
  let sum = Derived(rt, () => input_a.get() + input_b.get())
  let doubled = Derived(rt, () => sum.get_or_abort() * 2)
  let pick = Derived(rt, () => {
    if flag.get() {
      input_a.get()
    } else {
      input_b.get()
    }
  })
  {
    rt,
    input_a,
    input_b,
    flag,
    sum,
    doubled,
    pick,
  }
}

///|
fn apply_graph_op(fixture : GraphFixture, op : GraphOp) -> Unit {
  match op {
    SetA(v) => fixture.input_a.set(v)
    SetB(v) => fixture.input_b.set(v)
    ReadSum => ignore(fixture.sum.read_or_abort())
    ReadDoubled => ignore(fixture.doubled.read_or_abort())
    ToggleFlag => fixture.flag.set(!fixture.flag.get())
    ReadPick => ignore(fixture.pick.read_or_abort())
  }
}

///|
fn apply_graph_ops(fixture : GraphFixture, ops : Array[GraphOp]) -> Unit {
  for op in ops {
    apply_graph_op(fixture, op)
  }
}

///|
fn dispatch_tables_aligned(rt : Runtime) -> Bool {
  let ci = rt.core.cell_index.length()
  let co = rt.core.cell_ops.length()
  let cl = rt.cell_lifecycle.length()
  ci == co && co == cl
}

///|
fn cell_id_for_slot(rt : Runtime, slot : Int) -> CellId? {
  if slot < 0 || slot >= rt.core.cell_index.length() {
    return None
  }
  match rt.core.cell_index[slot] {
    Disposed => None
    cref =>
      Some(@kernel.cell_id_for(rt.pull, rt.push, rt.datalog, cref))
  }
}

///|
/// Every forward dependency has a matching reverse subscriber link.
fn subscriber_symmetry_holds(rt : Runtime) -> Bool {
  for slot in 0..<rt.core.cell_index.length() {
    match cell_id_for_slot(rt, slot) {
      None => ()
      Some(id) =>
        if !rt.is_cell_disposed(id) {
          match rt.cell_info(id) {
            None => ()
            Some(info) => {
              for dep in info.dependencies {
                match rt.cell_info(dep) {
                  None => return false
                  Some(dep_info) =>
                    if !dep_info.subscribers.contains(id) {
                      return false
                    }
                }
              }
              for sub in info.subscribers {
                match rt.cell_info(sub) {
                  None => return false
                  Some(sub_info) =>
                    if !sub_info.dependencies.contains(id) {
                      return false
                    }
                }
              }
            }
          }
        }
    }
  }
  true
}

///|
fn graph_op_gen() -> @gen.Gen[GraphOp] {
  @gen.one_of([
    @gen.int_bound(50).fmap(v => GraphOp::SetA(v)),
    @gen.int_bound(50).fmap(v => GraphOp::SetB(v)),
    @gen.pure(GraphOp::ReadSum),
    @gen.pure(GraphOp::ReadDoubled),
    @gen.pure(GraphOp::ToggleFlag),
    @gen.pure(GraphOp::ReadPick),
  ])
}

///|
fn graph_ops_gen() -> @gen.Gen[Array[GraphOp]] {
  @gen.sized(size => {
    let count = (size % 8) + 1
    graph_op_gen().array_with_size(count)
  })
}

///|
fn prop_subscriber_symmetry_after_ops(ops : Array[GraphOp]) -> Bool {
  let fixture = build_graph_fixture()
  apply_graph_ops(fixture, ops)
  subscriber_symmetry_holds(fixture.rt)
}

///|
fn prop_dispatch_tables_aligned_after_ops(ops : Array[GraphOp]) -> Bool {
  let fixture = build_graph_fixture()
  apply_graph_ops(fixture, ops)
  dispatch_tables_aligned(fixture.rt)
}

///|
test "graph invariant: subscriber symmetry under random pull ops" {
  let prop = @qc.forall(graph_ops_gen(), prop_subscriber_symmetry_after_ops)
  @qc.quick_check(prop, max_success=100)
}

///|
test "graph invariant: dispatch tables stay aligned under random pull ops" {
  let prop = @qc.forall(graph_ops_gen(), prop_dispatch_tables_aligned_after_ops)
  @qc.quick_check(prop, max_success=100)
}

///|
test "graph invariant: subscriber symmetry smoke (hand-written ops)" {
  let fixture = build_graph_fixture()
  apply_graph_ops(fixture, [
    SetA(1),
    SetB(2),
    ReadSum,
    ToggleFlag,
    ReadPick,
    SetB(3),
    ReadDoubled,
  ])
  inspect(subscriber_symmetry_holds(fixture.rt), content="true")
  inspect(dispatch_tables_aligned(fixture.rt), content="true")
}
