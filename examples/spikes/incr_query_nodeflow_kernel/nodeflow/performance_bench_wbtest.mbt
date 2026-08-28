///|
fn bench_output(graph : Int, node : Int, port : Int) -> PortReference {
  { graph, node, port }
}

///|
fn bench_restore(document : GraphDocument) -> Nodeflow raise {
  Nodeflow::restore(document, ObservationDemand::empty()).unwrap().nodeflow()
}

///|
fn independent_number_fixture(size : Int) -> Nodeflow raise {
  let graph = next_graph_id()
  let nodes = Array::makei(size, id => {
    id,
    descriptor: @application.NodeDescriptor::Number(value=id),
    bindings: [],
  })
  bench_restore({ wire: { version: 1, graph, next_node: size, nodes } })
}

///|
struct RebindFixture {
  graph : Nodeflow
  input : PortReference
  first : PortReference
  second : PortReference
}

///|
fn rebind_fixture(size : Int) -> RebindFixture raise {
  let graph_id = next_graph_id()
  let first_node = size - 3
  let second_node = size - 2
  let target_node = size - 1
  let nodes : Array[DocumentNode] = []
  for id in 0..<target_node {
    nodes.push({
      id,
      descriptor: @application.NodeDescriptor::Number(value=id),
      bindings: [],
    })
  }
  let first = bench_output(graph_id, first_node, 0)
  let second = bench_output(graph_id, second_node, 0)
  nodes.push({
    id: target_node,
    descriptor: @application.NodeDescriptor::Add,
    bindings: [
      (0, BindingTarget::Bound(first)),
      (1, BindingTarget::Bound(first)),
    ],
  })
  {
    graph: bench_restore({
      wire: { version: 1, graph: graph_id, next_node: size, nodes },
    }),
    input: bench_output(graph_id, target_node, 0),
    first,
    second,
  }
}

///|
struct ChainFixture {
  graph : Nodeflow
  source : ParameterReference
  output : PortReference
}

///|
fn chain_fixture(total_size : Int, active_depth : Int) -> ChainFixture raise {
  let graph_id = next_graph_id()
  let nodes : Array[DocumentNode] = [
    {
      id: 0,
      descriptor: @application.NodeDescriptor::Number(value=0),
      bindings: [],
    },
    {
      id: 1,
      descriptor: @application.NodeDescriptor::Number(value=1),
      bindings: [],
    },
  ]
  let mut previous = bench_output(graph_id, 0, 0)
  for id in 2..<active_depth {
    nodes.push({
      id,
      descriptor: @application.NodeDescriptor::Add,
      bindings: [
        (0, BindingTarget::Bound(previous)),
        (1, BindingTarget::Bound(bench_output(graph_id, 1, 0))),
      ],
    })
    previous = bench_output(graph_id, id, 2)
  }
  for id in active_depth..<total_size {
    nodes.push({
      id,
      descriptor: @application.NodeDescriptor::Number(value=id),
      bindings: [],
    })
  }
  {
    graph: bench_restore({
      wire: { version: 1, graph: graph_id, next_node: total_size, nodes },
    }),
    source: { graph: graph_id, node: 0, parameter: 0 },
    output: previous,
  }
}

///|
fn bench_snapshot(b : @bench.T, size : Int) -> Unit raise {
  let graph = independent_number_fixture(size)
  b.bench(() => {
    let snapshot = graph.snapshot(ObservationDemand::empty()) catch {
      _ => abort("valid snapshot benchmark fixture failed")
    }
    b.keep(snapshot)
  })
  graph.close()
}

///|
fn bench_rebind(b : @bench.T, size : Int) -> Unit raise {
  let fixture = rebind_fixture(size)
  let mut use_second = false
  b.bench(() => {
    use_second = !use_second
    let provider = if use_second { fixture.second } else { fixture.first }
    let result = fixture.graph.apply(
      GraphEdit::BindingChangeSet(changes=[
        { target: fixture.input, binding: Bound(provider) },
      ]),
      ObservationDemand::empty(),
    ) catch {
      _ => abort("valid rebind benchmark fixture failed")
    }
    b.keep(result)
  })
  fixture.graph.close()
}

///|
fn bench_chain_edit(
  b : @bench.T,
  total_size : Int,
  active_depth : Int,
) -> Unit raise {
  let fixture = chain_fixture(total_size, active_depth)
  let demand = ObservationDemand::empty().request(fixture.output)
  let mut value = 0
  b.bench(() => {
    value = value + 1
    let result = fixture.graph.apply(
      GraphEdit::SetParameter(
        parameter=fixture.source,
        value=@application.ParameterValue::Number(value),
      ),
      demand,
    ) catch {
      _ => abort("valid chain benchmark fixture failed")
    }
    b.keep(result)
  })
  fixture.graph.close()
}

///|
test "Nodeflow structural snapshot N=100" (b : @bench.T) {
  bench_snapshot(b, 100)
}

///|
test "Nodeflow structural snapshot N=1000" (b : @bench.T) {
  bench_snapshot(b, 1000)
}

///|
test "Nodeflow structural snapshot N=10000" (b : @bench.T) {
  bench_snapshot(b, 10000)
}

///|
test "Nodeflow atomic rebind and snapshot N=100" (b : @bench.T) {
  bench_rebind(b, 100)
}

///|
test "Nodeflow atomic rebind and snapshot N=1000" (b : @bench.T) {
  bench_rebind(b, 1000)
}

///|
test "Nodeflow atomic rebind and snapshot N=10000" (b : @bench.T) {
  bench_rebind(b, 10000)
}

///|
test "Nodeflow chain source edit and demanded tail N=100" (b : @bench.T) {
  bench_chain_edit(b, 100, 100)
}

///|
test "Nodeflow chain source edit and demanded tail N=1000" (b : @bench.T) {
  bench_chain_edit(b, 1000, 1000)
}

///|
test "Nodeflow source edit total N=10000 active depth=100" (b : @bench.T) {
  bench_chain_edit(b, 10000, 100)
}
