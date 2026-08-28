///|
test "restoration does not replay Action invocations" {
  let graph = Nodeflow::empty()
  let number = wb_added_node(graph, NodeDescriptor::Number(value=7))
  let display = wb_added_node(graph, NodeDescriptor::Display)
  wb_bind(graph, display.inputs[0], number.outputs[0])
  let action = display.actions[0]
  ignore(graph.invoke(action))
  let original_runtime = graph.runtime.nodes.get(display.node.node).unwrap()
  assert_eq(original_runtime.action_invocation_count(), 1)

  let restored_result = Nodeflow::restore(
    graph.document(),
    ObservationDemand::empty().request_action(action),
  ).unwrap()
  let restored = restored_result.nodeflow()
  let restored_runtime = restored.runtime.nodes.get(display.node.node).unwrap()
  assert_eq(restored_runtime.action_invocation_count(), 0)
  assert_eq(
    restored_result.snapshot().action_observation(action),
    ActionObservation::Present(ActionAvailability::Available),
  )
  ignore(restored.invoke(action))
  assert_eq(restored_runtime.action_invocation_count(), 1)
  graph.close()
  restored.close()
}

///|
test "semantic restoration rejection allocates no graph identity" {
  let before = Nodeflow::empty()
  let invalid : GraphDocument = {
    wire: { version: 2, graph: before.state.graph, next_node: 0, nodes: [] },
  }
  match Nodeflow::restore(invalid, ObservationDemand::empty()) {
    Err(GraphRestorationRejection::UnsupportedVersion) => ()
    _ => fail("expected unsupported version")
  }
  let after = Nodeflow::empty()
  assert_eq(after.state.graph, before.state.graph + 1)
  before.close()
  after.close()
}
