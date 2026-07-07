///|
/// Property-based probes for dependency-graph invariants used as a refactoring
/// safety net. See `docs/design/internals.md` (current-model invariants) and
/// `docs/design/specs/2026-03-25-push-reachable-count-design.md` (gate).
///
/// Complements `current_model_wbtest.mbt` (green path, backdating, failed-read
/// trace rules) with randomized graph-shape checks: subscriber symmetry,
/// dispatch-table alignment, and the push-reachable zero/non-zero gate.
///
/// `moonbitlang/quickcheck` is pinned in `incr/moon.mod` because MoonBit
/// requires module-level resolution for external packages, but it is imported
/// only via `for "test"` / `for "wbtest"` in `moon.pkg` — never from library
/// sources.
///
/// Fixture design: `gc()` marks Interior cells reachable only from gc roots
/// backward along `gc_dependencies` (upstream). Cells not on a watch-rooted
/// chain are swept. The fixture holds `Watch` handles on every derived cell
/// that random ops may read (`sum`, `pick`) plus the anchor `eager` chain.

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
  // Root cells that random ops may read so `GcSweep` does not dispose them.
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
fn read_derived_if_alive(derived : Derived[Int]) -> Unit {
  if !derived.rt.is_cell_disposed(derived.id()) {
    ignore(derived.read_or_abort())
  }
}

///|
fn read_eager_if_alive(eager : EagerDerived[Int]) -> Unit {
  if !eager.rt.is_cell_disposed(eager.id()) {
    ignore(eager.read())
  }
}

///|
fn apply_graph_op(fixture : GraphFixture, op : GraphOp) -> Unit {
  match op {
    SetA(v) => fixture.input_a.set(v)
    SetB(v) => fixture.input_b.set(v)
    ReadSum => read_derived_if_alive(fixture.sum)
    ReadDoubled => read_derived_if_alive(fixture.doubled)
    ToggleFlag => fixture.flag.set(!fixture.flag.get())
    ReadPick => read_derived_if_alive(fixture.pick)
    ReadEager => read_eager_if_alive(fixture.eager)
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
/// Cells whose `push_reachable_count` gate is defined (see push-reachable spec).
fn participates_in_push_reachable_gate(rt : Runtime, id : CellId) -> Bool {
  if rt.is_cell_disposed(id) {
    return false
  }
  match rt.core.cell_index[id.id] {
    PullInput(_)
    | PullMemo(_)
    | HybridMemo(_)
    | Relation(_)
    | FunctionalRelation(_) => true
    _ => false
  }
}

///|
fn is_live_push_cell(rt : Runtime, id : CellId) -> Bool {
  if rt.is_cell_disposed(id) {
    return false
  }
  match rt.core.cell_index[id.id] {
    PushReactive(_) | PushEffect(_) => true
    _ => false
  }
}

///|
/// Returns true when a live push cell is reachable from `from` by following
/// subscriber (downstream) links.
fn has_live_push_downstream(rt : Runtime, from : CellId) -> Bool {
  let visited : @hashset.HashSet[CellId] = @hashset.HashSet([])
  let worklist : Array[CellId] = []
  for sub in cell_subscribers(rt, from) {
    worklist.push(sub)
  }
  let mut wi = 0
  while wi < worklist.length() {
    let id = worklist[wi]
    wi += 1
    if visited.contains(id) {
      continue
    }
    if rt.is_cell_disposed(id) {
      continue
    }
    visited.add(id)
    if is_live_push_cell(rt, id) {
      return true
    }
    for sub in cell_subscribers(rt, id) {
      worklist.push(sub)
    }
  }
  false
}

///|
/// Gate invariant: `push_reachable_count > 0` iff a live push cell is reachable
/// downstream through subscriber links (zero/non-zero only; not exact path weight).
fn push_reachable_gate_holds(rt : Runtime) -> Bool {
  for slot in 0..<rt.core.cell_index.length() {
    match cell_id_for_slot(rt, slot) {
      None => ()
      Some(id) =>
        if participates_in_push_reachable_gate(rt, id) {
          let counted_live = push_reachable_count(rt, id) > 0
          let downstream_live = has_live_push_downstream(rt, id)
          if counted_live != downstream_live {
            return false
          }
        }
    }
  }
  true
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
fn all_graph_invariants_hold(rt : Runtime) -> Bool {
  subscriber_symmetry_holds(rt) &&
  dispatch_tables_aligned(rt) &&
  push_reachable_gate_holds(rt)
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
fn prop_all_graph_invariants_after_ops(ops : Array[GraphOp]) -> Bool {
  let fixture = build_graph_fixture()
  apply_graph_ops(fixture, ops)
  all_graph_invariants_hold(fixture.rt)
}

///|
test "graph invariant: combined properties under random pull/push ops" {
  let prop = @qc.forall(graph_ops_gen(), prop_all_graph_invariants_after_ops)
  @qc.quick_check(prop, max_success=100)
}

///|
test "graph invariant: smoke (hand-written ops)" {
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
  inspect(push_reachable_gate_holds(fixture.rt), content="true")
}

///|
test "graph invariant: pick off eager chain has zero push reachability" {
  let fixture = build_graph_fixture()
  ignore(fixture.eager.read())
  inspect(
    push_reachable_count(fixture.rt, fixture.pick.id()) == 0,
    content="true",
  )
  inspect(
    has_live_push_downstream(fixture.rt, fixture.pick.id()),
    content="false",
  )
}
