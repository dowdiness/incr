///|
test "structural snapshot is demand independent" {
  let graph = Nodeflow::empty()
  let left = wb_added_node(graph, NodeDescriptor::Number(value=1))
  let right = wb_added_node(graph, NodeDescriptor::Number(value=2))
  let add = wb_added_node(graph, NodeDescriptor::Add)
  let display = wb_added_node(graph, NodeDescriptor::Display)
  wb_bind(graph, display.inputs[0], add.outputs[0])
  let display_runtime = graph.runtime.nodes.get(display.node.node).unwrap()
  assert_eq(display_runtime.action_invocation_count(), 0)
  wb_bind(graph, add.inputs[0], left.outputs[0])
  wb_bind(graph, add.inputs[1], right.outputs[0])
  let runtime = graph.runtime.nodes.get(add.node.node).unwrap()
  assert_eq(runtime.formula_compute_count(), 0)
  let structural = graph.snapshot(ObservationDemand::empty())
  assert_eq(structural.nodes().length(), 4)
  assert_eq(runtime.formula_compute_count(), 0)
  assert_eq(display_runtime.action_invocation_count(), 0)
  ignore(graph.snapshot(ObservationDemand::empty().request(add.outputs[0])))
  assert_eq(runtime.formula_compute_count(), 1)
  graph.close()
}

///|
test "OptionalOffset computes only when required and connected optional inputs are current" {
  let graph = Nodeflow::empty()
  let required = wb_added_node(graph, NodeDescriptor::Number(value=1))
  let optional = wb_added_node(graph, NodeDescriptor::Number(value=2))
  let offset = wb_added_node(graph, NodeDescriptor::OptionalOffset(value=3))
  wb_bind(graph, offset.inputs[0], required.outputs[0])
  wb_bind(graph, offset.inputs[1], optional.outputs[0])
  let runtime = graph.runtime.nodes.get(offset.node.node).unwrap()
  assert_eq(runtime.formula_compute_count(), 0)
  ignore(graph.snapshot(ObservationDemand::empty()))
  assert_eq(runtime.formula_compute_count(), 0)
  assert_eq(
    wb_observe_number(graph, offset.outputs[0]),
    OutputObservation::Current(
      OutputData::Number(NumberFormulaOutcome::Success(6)),
    ),
  )
  assert_eq(runtime.formula_compute_count(), 1)

  let unavailable = wb_added_node(graph, NodeDescriptor::Add)
  wb_bind(graph, offset.inputs[1], unavailable.outputs[0])
  match wb_observe_number(graph, offset.outputs[0]) {
    OutputObservation::Unavailable(issues) =>
      assert_eq(
        issues,
        ReadOnlyArray::from_array([
          EvaluationIssue::BlockedEvaluation(offset.inputs[1]),
        ]),
      )
    _ => fail("expected blocked optional input")
  }
  assert_eq(runtime.formula_compute_count(), 1)
  graph.close()
}
