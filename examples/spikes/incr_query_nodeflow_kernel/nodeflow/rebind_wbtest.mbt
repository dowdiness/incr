///|
fn wb_added_node(
  graph : Nodeflow,
  descriptor : NodeDescriptor,
) -> AddedNode raise GraphPublicationError {
  match
    graph
    .apply(GraphEdit::AddNode(descriptor~), ObservationDemand::empty())
    .unwrap() {
    GraphEditResult::Added(node) => node
    Changed(_) => abort("expected added node")
  }
}

///|
fn wb_bind(
  graph : Nodeflow,
  target : PortReference,
  provider : PortReference,
) -> Unit raise GraphPublicationError {
  ignore(
    graph
    .apply(
      GraphEdit::BindingChangeSet(changes=[
        { target, binding: BindingTarget::Bound(provider) },
      ]),
      ObservationDemand::empty(),
    )
    .unwrap(),
  )
}

///|
fn wb_observe_number(
  graph : Nodeflow,
  output : PortReference,
) -> OutputObservation raise SurfaceReadError {
  graph.snapshot(ObservationDemand::empty().request(output)).observation(output)
}

///|
test "rebind retires the old provider from the Formula dependency trace" {
  let graph = Nodeflow::empty()
  let ten = wb_added_node(graph, NodeDescriptor::Number(value=10))
  let twenty = wb_added_node(graph, NodeDescriptor::Number(value=20))
  let two = wb_added_node(graph, NodeDescriptor::Number(value=2))
  let add = wb_added_node(graph, NodeDescriptor::Add)
  wb_bind(graph, add.inputs[0], ten.outputs[0])
  wb_bind(graph, add.inputs[1], twenty.outputs[0])
  assert_eq(
    wb_observe_number(graph, add.outputs[0]),
    OutputObservation::Current(OutputData::Number(30)),
  )
  let runtime = graph.runtime.nodes.get(add.node.node).unwrap()
  assert_eq(runtime.formula_compute_count(), 1)

  wb_bind(graph, add.inputs[1], two.outputs[0])
  assert_eq(
    wb_observe_number(graph, add.outputs[0]),
    OutputObservation::Current(OutputData::Number(12)),
  )
  assert_eq(runtime.formula_compute_count(), 2)

  ignore(
    graph
    .apply(
      GraphEdit::SetNumberParameter(node=twenty.node, value=100),
      ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    wb_observe_number(graph, add.outputs[0]),
    OutputObservation::Current(OutputData::Number(12)),
  )
  assert_eq(runtime.formula_compute_count(), 2)

  ignore(
    graph
    .apply(
      GraphEdit::SetNumberParameter(node=two.node, value=3),
      ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    wb_observe_number(graph, add.outputs[0]),
    OutputObservation::Current(OutputData::Number(13)),
  )
  assert_eq(runtime.formula_compute_count(), 3)
  graph.close()
}
