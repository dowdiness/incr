///|
test "input publication and availability never invoke an Action" {
  let graph = Nodeflow::empty()
  let number = wb_added_node(graph, NodeDescriptor::Number(value=7))
  let display = wb_added_node(graph, NodeDescriptor::Display)
  wb_bind(graph, display.inputs[0], number.outputs[0])
  let action = display.actions[0]
  let runtime = graph.runtime.nodes.get(display.node.node).unwrap()
  assert_eq(runtime.action_invocation_count(), 0)

  ignore(graph.snapshot(ObservationDemand::empty().request_action(action)))
  assert_eq(runtime.action_invocation_count(), 0)

  ignore(
    graph
    .apply(
      GraphEdit::SetNumberParameter(node=number.node, value=9),
      ObservationDemand::empty(),
    )
    .unwrap(),
  )
  ignore(graph.snapshot(ObservationDemand::empty().request_action(action)))
  assert_eq(runtime.action_invocation_count(), 0)

  assert_eq(
    graph.invoke(action),
    ActionInvocationOutcome::Decided(
      ApplicationDecision::Success(Command::RecordNumber(9)),
    ),
  )
  assert_eq(runtime.action_invocation_count(), 1)
  graph.close()
}
