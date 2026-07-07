///|
/// Random graph operation for pull/push invariant probing.
enum GraphOp {
  SetA(Int)
  SetB(Int)
  ReadSum
  ReadDoubled
  ToggleFlag
  ReadPick
  ReadEager
  SpawnDisposePush
  ObserveSumDrop
  GcSweep
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
  eager : EagerDerived[Int]
  sum_watch : Watch[Int]
  eager_watch : Watch[Int]
  pick_watch : Watch[Int]
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
  let eager = EagerDerived::EagerDerived(rt, () => doubled.read_or_abort())
  let sum_watch = sum.watch()
  let eager_watch = eager.watch()
  let pick_watch = pick.watch()
  {
    rt,
    input_a,
    input_b,
    flag,
    sum,
    doubled,
    pick,
    eager,
    sum_watch,
    eager_watch,
    pick_watch,
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
    ReadEager =>
      if !fixture.rt.is_cell_disposed(fixture.eager.id()) {
        ignore(fixture.eager.read())
      }
    SpawnDisposePush => {
      let ephemeral = Input(fixture.rt, 0)
      let push = EagerDerived::EagerDerived(fixture.rt, () => ephemeral.get())
      push.dispose()
      ephemeral.dispose()
    }
    ObserveSumDrop => {
      let observer = fixture.sum.observe()
      observer.dispose()
    }
    GcSweep => fixture.rt.gc()
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
    cref => Some(@kernel.cell_id_for(rt.pull, rt.push, rt.datalog, cref))
  }
}

///|
fn push_reachable_count(rt : Runtime, id : CellId) -> Int {
  rt.core.cell_ops[id.id].push_reachable_count()
}

///|
fn cell_dependencies(rt : Runtime, id : CellId) -> Array[CellId] {
  rt.core.cell_ops[id.id].gc_dependencies()
}

///|
fn cell_subscribers(rt : Runtime, id : CellId) -> Array[CellId] {
  let result : Array[CellId] = []
  for sub in rt.core.cell_ops[id.id].subscribers() {
    result.push(sub)
  }
  result
}

///|
/// Every forward dependency has a matching reverse subscriber link.
fn subscriber_symmetry_holds(rt : Runtime) -> Bool {
  for slot in 0..<rt.core.cell_index.length() {
    match cell_id_for_slot(rt, slot) {
      None => ()
      Some(id) =>
        if !rt.is_cell_disposed(id) {
          let deps = cell_dependencies(rt, id)
          let subs = cell_subscribers(rt, id)
          for dep in deps {
            if !rt.validate_cell_soft(dep) {
              return false
            }
            if !cell_subscribers(rt, dep).contains(id) {
              return false
            }
          }
          for sub in subs {
            if !rt.validate_cell_soft(sub) {
              return false
            }
            if !cell_dependencies(rt, sub).contains(id) {
              return false
            }
          }
        }
    }
  }
  true
}

///|
/// While the anchor eager cell is live, its upstream pull chain stays
/// push-reachable (count > 0).
fn push_reachable_gate_holds(fixture : GraphFixture) -> Bool {
  if fixture.rt.is_cell_disposed(fixture.eager.id()) {
    return true
  }
  if push_reachable_count(fixture.rt, fixture.input_a.id()) <= 0 {
    return false
  }
  if push_reachable_count(fixture.rt, fixture.sum.id()) <= 0 {
    return false
  }
  if push_reachable_count(fixture.rt, fixture.doubled.id()) <= 0 {
    return false
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
    @gen.pure(GraphOp::ReadEager),
    @gen.pure(GraphOp::SpawnDisposePush),
    @gen.pure(GraphOp::ObserveSumDrop),
    @gen.pure(GraphOp::GcSweep),
  ])
}

///|
fn graph_ops_gen() -> @gen.Gen[Array[GraphOp]] {
  @gen.sized(size => {
    let count = size % 10 + 1
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
fn prop_push_reachable_gate_after_ops(ops : Array[GraphOp]) -> Bool {
  let fixture = build_graph_fixture()
  apply_graph_ops(fixture, ops)
  push_reachable_gate_holds(fixture)
}

///|
fn prop_all_graph_invariants_after_ops(ops : Array[GraphOp]) -> Bool {
  let fixture = build_graph_fixture()
  apply_graph_ops(fixture, ops)
  subscriber_symmetry_holds(fixture.rt) &&
  dispatch_tables_aligned(fixture.rt) &&
  push_reachable_gate_holds(fixture)
}

///|
test "graph invariant: subscriber symmetry under random pull/push ops" {
  let prop = @qc.forall(graph_ops_gen(), prop_subscriber_symmetry_after_ops)
  @qc.quick_check(prop, max_success=100)
}

///|
test "graph invariant: dispatch tables stay aligned under random pull/push ops" {
  let prop = @qc.forall(graph_ops_gen(), prop_dispatch_tables_aligned_after_ops)
  @qc.quick_check(prop, max_success=100)
}

///|
test "graph invariant: push reachable gate under random pull/push ops" {
  let prop = @qc.forall(graph_ops_gen(), prop_push_reachable_gate_after_ops)
  @qc.quick_check(prop, max_success=100)
}

///|
test "graph invariant: combined invariants under random pull/push ops" {
  let prop = @qc.forall(graph_ops_gen(), prop_all_graph_invariants_after_ops)
  @qc.quick_check(prop, max_success=100)
}

///|
test "graph invariant: subscriber symmetry smoke (hand-written ops)" {
  let fixture = build_graph_fixture()
  apply_graph_ops(fixture, [
    SetA(1),
    SetB(2),
    ReadSum,
    ReadEager,
    ToggleFlag,
    ReadPick,
    SetB(3),
    ReadDoubled,
    SpawnDisposePush,
    ObserveSumDrop,
    GcSweep,
  ])
  inspect(subscriber_symmetry_holds(fixture.rt), content="true")
  inspect(dispatch_tables_aligned(fixture.rt), content="true")
  inspect(push_reachable_gate_holds(fixture), content="true")
}
