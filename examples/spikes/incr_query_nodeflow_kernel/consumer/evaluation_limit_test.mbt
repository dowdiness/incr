///|
test "Nodeflow projects its Store evaluation limit as expected unavailability" {
  let graph = @nodeflow.Nodeflow::empty()
  let source = added_node(graph, @application.NodeDescriptor::Number(value=1))
  let mut previous = source.outputs()[0]
  for _ in 0..<260 {
    let add = added_node(graph, @application.NodeDescriptor::Add)
    bind(graph, add.inputs()[0], previous)
    bind(graph, add.inputs()[1], source.outputs()[0])
    previous = add.outputs()[0]
  }
  let display = added_node(graph, @application.NodeDescriptor::Display)
  bind(graph, display.inputs()[0], previous)
  let action = display.actions()[0]
  let demand = @nodeflow.ObservationDemand::empty()
    .request(previous)
    .request_action(action)

  let snapshot = graph.snapshot(demand)
  assert_eq(
    snapshot.observation(previous),
    @nodeflow.OutputObservation::Unavailable(
      ReadOnlyArray::from_array([
        @nodeflow.EvaluationIssue::EvaluationLimitExceeded,
      ]),
    ),
  )
  assert_eq(
    snapshot.action_observation(action),
    @nodeflow.ActionObservation::Present(
      @nodeflow.ActionAvailability::Unavailable(
        ReadOnlyArray::from_array([
          @nodeflow.ActionInputIssue::EvaluationLimitExceeded,
        ]),
      ),
    ),
  )
  assert_eq(
    graph.invoke(action),
    @nodeflow.ActionInvocationOutcome::Unavailable(
      ReadOnlyArray::from_array([
        @nodeflow.ActionInputIssue::EvaluationLimitExceeded,
      ]),
    ),
  )

  let changed = graph
    .apply(
      @nodeflow.GraphEdit::SetParameter(
        parameter=source.parameters()[0],
        value=@application.ParameterValue::Number(2),
      ),
      demand,
    )
    .unwrap()
  let changed_snapshot = match changed {
    @nodeflow.GraphEditResult::Changed(value) => value
    _ => fail("expected changed graph")
  }
  assert_true(
    changed_snapshot.observation(previous)
    is @nodeflow.OutputObservation::Unavailable(_),
  )

  let restoration = @nodeflow.Nodeflow::restore(graph.document(), demand).unwrap()
  assert_true(
    restoration.snapshot().observation(previous)
    is @nodeflow.OutputObservation::Unavailable(_),
  )
  assert_true(
    restoration.snapshot().action_observation(action)
    is @nodeflow.ActionObservation::Present(
      @nodeflow.ActionAvailability::Unavailable(_)
    ),
  )
  let restored = restoration.nodeflow()
  graph.close()
  restored.close()
}
