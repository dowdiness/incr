///|
test "optional offset distinguishes waiting, unbound, blocked, and current" {
  let graph = @nodeflow.Nodeflow::empty()
  let required = surface_added_node(
    graph,
    @nodeflow.NodeDescriptor::Number(value=10),
  )
  let offset = surface_added_node(
    graph,
    @nodeflow.NodeDescriptor::OptionalOffset(value=2),
  )
  let output = offset.outputs()[0]
  assert_eq(
    graph
    .snapshot(@nodeflow.ObservationDemand::empty().request(output))
    .observation(output),
    @nodeflow.OutputObservation::Unavailable(
      ReadOnlyArray::from_array([
        @nodeflow.EvaluationIssue::InputWaiting(offset.inputs()[0]),
      ]),
    ),
  )
  let unavailable = surface_added_node(graph, @nodeflow.NodeDescriptor::Add)
  surface_bind(graph, offset.inputs()[1], unavailable.outputs()[0])
  assert_eq(
    graph
    .snapshot(@nodeflow.ObservationDemand::empty().request(output))
    .observation(output),
    @nodeflow.OutputObservation::Unavailable(
      ReadOnlyArray::from_array([
        @nodeflow.EvaluationIssue::InputWaiting(offset.inputs()[0]),
        @nodeflow.EvaluationIssue::BlockedEvaluation(offset.inputs()[1]),
      ]),
    ),
  )
  unbind(graph, offset.inputs()[1])
  surface_bind(graph, offset.inputs()[0], required.outputs()[0])
  assert_eq(
    graph
    .snapshot(@nodeflow.ObservationDemand::empty().request(output))
    .observation(output),
    @nodeflow.OutputObservation::Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(12)),
    ),
  )
  let current_optional = surface_added_node(
    graph,
    @nodeflow.NodeDescriptor::Number(value=3),
  )
  surface_bind(graph, offset.inputs()[1], current_optional.outputs()[0])
  assert_eq(
    graph
    .snapshot(@nodeflow.ObservationDemand::empty().request(output))
    .observation(output),
    @nodeflow.OutputObservation::Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(15)),
    ),
  )
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::SetParameter(
        parameter=offset.parameters()[0],
        value=@nodeflow.ParameterValue::Number(5),
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    graph
    .snapshot(@nodeflow.ObservationDemand::empty().request(output))
    .observation(output),
    @nodeflow.OutputObservation::Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(18)),
    ),
  )
  surface_bind(graph, offset.inputs()[1], unavailable.outputs()[0])
  assert_eq(
    graph
    .snapshot(@nodeflow.ObservationDemand::empty().request(output))
    .observation(output),
    @nodeflow.OutputObservation::Unavailable(
      ReadOnlyArray::from_array([
        @nodeflow.EvaluationIssue::BlockedEvaluation(offset.inputs()[1]),
      ]),
    ),
  )
  let failed = surface_added_node(graph, @nodeflow.NodeDescriptor::SafeDivide)
  let zero = surface_added_node(
    graph,
    @nodeflow.NodeDescriptor::Number(value=0),
  )
  surface_bind(graph, failed.inputs()[0], required.outputs()[0])
  surface_bind(graph, failed.inputs()[1], zero.outputs()[0])
  surface_bind(graph, offset.inputs()[1], failed.outputs()[0])
  assert_eq(
    graph
    .snapshot(@nodeflow.ObservationDemand::empty().request(output))
    .observation(output),
    @nodeflow.OutputObservation::Current(
      @nodeflow.OutputData::Number(
        @nodeflow.NumberFormulaOutcome::Failure(
          @nodeflow.FormulaFailure::DivisionByZero,
        ),
      ),
    ),
  )
  graph.close()
}
