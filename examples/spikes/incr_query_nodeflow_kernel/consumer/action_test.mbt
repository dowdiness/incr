///|
test "display action" {
  let graph = @nodeflow.Nodeflow::empty()
  let display = match
    graph
    .apply(
      @nodeflow.GraphEdit::AddNode(descriptor=@nodeflow.NodeDescriptor::Display),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap() {
    @nodeflow.GraphEditResult::Added(node) => node
    _ => abort("expected display")
  }
  let action = display.actions()[0]
  let snapshot = graph.snapshot(
    @nodeflow.ObservationDemand::empty().request_action(action),
  )
  assert_eq(
    snapshot.action_observation(action),
    @nodeflow.ActionObservation::Present(
      @nodeflow.ActionAvailability::Unavailable(
        ReadOnlyArray::from_array([
          @nodeflow.ActionInputIssue::Unbound(display.inputs()[0]),
        ]),
      ),
    ),
  )
  let number = match
    graph
    .apply(
      @nodeflow.GraphEdit::AddNode(
        descriptor=@nodeflow.NodeDescriptor::Number(value=7),
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap() {
    @nodeflow.GraphEditResult::Added(node) => node
    _ => abort("expected number")
  }
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        {
          target: display.inputs()[0],
          binding: @nodeflow.BindingTarget::Bound(number.outputs()[0]),
        },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_true(
    graph
    .snapshot(@nodeflow.ObservationDemand::empty().request_action(action))
    .action_observation(action)
    is @nodeflow.ActionObservation::Present(
      @nodeflow.ActionAvailability::Available
    ),
  )
  assert_eq(
    graph.invoke(action),
    @nodeflow.ActionInvocationOutcome::Decided(
      @nodeflow.ApplicationDecision::Success(@nodeflow.Command::RecordNumber(7)),
    ),
  )
  graph.close()
}

///|
test "fresh invocation uses the latest committed value" {
  let graph = @nodeflow.Nodeflow::empty()
  let number = added_node(graph, @nodeflow.NodeDescriptor::Number(value=7))
  let display = added_node(graph, @nodeflow.NodeDescriptor::Display)
  bind(graph, display.inputs()[0], number.outputs()[0])
  let action = display.actions()[0]
  assert_eq(
    graph
    .snapshot(@nodeflow.ObservationDemand::empty().request_action(action))
    .action_observation(action),
    @nodeflow.ActionObservation::Present(
      @nodeflow.ActionAvailability::Available,
    ),
  )
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::SetParameter(
        parameter=number.parameters()[0],
        value=@nodeflow.ParameterValue::Number(9),
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    graph.invoke(action),
    @nodeflow.ActionInvocationOutcome::Decided(
      @nodeflow.ApplicationDecision::Success(@nodeflow.Command::RecordNumber(9)),
    ),
  )
  graph.close()
}

///|
test "failed Formula Outcome remains available to application refusal" {
  let graph = @nodeflow.Nodeflow::empty()
  let ten = added_node(graph, @nodeflow.NodeDescriptor::Number(value=10))
  let zero = added_node(graph, @nodeflow.NodeDescriptor::Number(value=0))
  let divide = added_node(graph, @nodeflow.NodeDescriptor::SafeDivide)
  bind(graph, divide.inputs()[0], ten.outputs()[0])
  bind(graph, divide.inputs()[1], zero.outputs()[0])
  let display = added_node(graph, @nodeflow.NodeDescriptor::Display)
  bind(graph, display.inputs()[0], divide.outputs()[0])
  let action = display.actions()[0]
  assert_eq(
    graph
    .snapshot(@nodeflow.ObservationDemand::empty().request_action(action))
    .action_observation(action),
    @nodeflow.ActionObservation::Present(
      @nodeflow.ActionAvailability::Available,
    ),
  )
  assert_eq(
    graph.invoke(action),
    @nodeflow.ActionInvocationOutcome::Decided(
      @nodeflow.ApplicationDecision::ApplicationRefusal(
        @nodeflow.FormulaFailure::DivisionByZero,
      ),
    ),
  )
  graph.close()
}

///|
test "foreign Action Reference is missing and rejected" {
  let owner = @nodeflow.Nodeflow::empty()
  let display = added_node(owner, @nodeflow.NodeDescriptor::Display)
  let action = display.actions()[0]
  let other = @nodeflow.Nodeflow::empty()
  assert_eq(
    other
    .snapshot(@nodeflow.ObservationDemand::empty().request_action(action))
    .action_observation(action),
    @nodeflow.ActionObservation::Missing,
  )
  assert_eq(
    other.invoke(action),
    @nodeflow.ActionInvocationOutcome::Rejected(
      @nodeflow.ActionInvocationRejection::MissingAction,
    ),
  )
  owner.close()
  other.close()
}

///|
test "Action demand keeps first occurrence order and deduplicates" {
  let graph = @nodeflow.Nodeflow::empty()
  let first = added_node(graph, @nodeflow.NodeDescriptor::Display)
  let second = added_node(graph, @nodeflow.NodeDescriptor::Display)
  let first_action = first.actions()[0]
  let second_action = second.actions()[0]
  let snapshot = graph.snapshot(
    @nodeflow.ObservationDemand::empty()
    .request_action(second_action)
    .request_action(first_action)
    .request_action(second_action),
  )
  assert_eq(snapshot.action_observations().length(), 2)
  assert_eq(snapshot.action_observations()[0].0, second_action)
  assert_eq(snapshot.action_observations()[1].0, first_action)
  graph.close()
}

///|
test "cyclic Action input is value unavailable" {
  let graph = @nodeflow.Nodeflow::empty()
  let ten = added_node(graph, @nodeflow.NodeDescriptor::Number(value=10))
  let cyclic = added_node(graph, @nodeflow.NodeDescriptor::Add)
  bind(graph, cyclic.inputs()[0], cyclic.outputs()[0])
  bind(graph, cyclic.inputs()[1], ten.outputs()[0])
  let display = added_node(graph, @nodeflow.NodeDescriptor::Display)
  bind(graph, display.inputs()[0], cyclic.outputs()[0])
  let action = display.actions()[0]
  let expected = ReadOnlyArray::from_array([
    @nodeflow.ActionInputIssue::ValueUnavailable(display.inputs()[0]),
  ])
  assert_eq(
    graph
    .snapshot(@nodeflow.ObservationDemand::empty().request_action(action))
    .action_observation(action),
    @nodeflow.ActionObservation::Present(
      @nodeflow.ActionAvailability::Unavailable(expected),
    ),
  )
  assert_eq(
    graph.invoke(action),
    @nodeflow.ActionInvocationOutcome::Unavailable(expected),
  )
  graph.close()
}
