///|
test "unbound inputs report ordered waiting issues" {
  let graph = @nodeflow.Nodeflow::empty()
  let add = added_node(graph, @nodeflow.NodeDescriptor::Add)
  let observation = number_at(graph, add.outputs()[0])
  let issues = unavailable_issues(observation)
  assert_eq(
    issues,
    ReadOnlyArray::from_array([
      @nodeflow.EvaluationIssue::InputWaiting(add.inputs()[0]),
      @nodeflow.EvaluationIssue::InputWaiting(add.inputs()[1]),
    ]),
  )
  graph.close()
}

///|
test "waiting and blocked issues retain declared input order" {
  let graph = @nodeflow.Nodeflow::empty()
  let unavailable = added_node(graph, @nodeflow.NodeDescriptor::Add)
  let consumer = added_node(graph, @nodeflow.NodeDescriptor::Add)
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        {
          target: consumer.inputs()[1],
          binding: @nodeflow.BindingTarget::Bound(unavailable.outputs()[0]),
        },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  let observation = number_at(graph, consumer.outputs()[0])
  let issues = unavailable_issues(observation)
  assert_eq(
    issues,
    ReadOnlyArray::from_array([
      @nodeflow.EvaluationIssue::InputWaiting(consumer.inputs()[0]),
      @nodeflow.EvaluationIssue::BlockedEvaluation(consumer.inputs()[1]),
    ]),
  )
  graph.close()
}

///|
test "safe divide failure is current and propagates" {
  let graph = @nodeflow.Nodeflow::empty()
  let ten = added_node(graph, @nodeflow.NodeDescriptor::Number(value=10))
  let zero = added_node(graph, @nodeflow.NodeDescriptor::Number(value=0))
  let divide = added_node(graph, @nodeflow.NodeDescriptor::SafeDivide)
  bind(graph, divide.inputs()[0], ten.outputs()[0])
  bind(graph, divide.inputs()[1], zero.outputs()[0])
  assert_eq(
    number_at(graph, divide.outputs()[0]),
    @nodeflow.OutputObservation::Current(
      @nodeflow.OutputData::Number(
        @nodeflow.NumberFormulaOutcome::Failure(
          @nodeflow.FormulaFailure::DivisionByZero,
        ),
      ),
    ),
  )
  let add = added_node(graph, @nodeflow.NodeDescriptor::Add)
  bind(graph, add.inputs()[0], divide.outputs()[0])
  bind(graph, add.inputs()[1], ten.outputs()[0])
  assert_eq(
    number_at(graph, add.outputs()[0]),
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

///|
test "self cycle becomes cyclic then unbound and recovers" {
  let graph = @nodeflow.Nodeflow::empty()
  let add = added_node(graph, @nodeflow.NodeDescriptor::Add)
  bind(graph, add.inputs()[0], add.outputs()[0])
  let cyclic = number_at(graph, add.outputs()[0])
  let issues = unavailable_issues(cyclic)
  assert_eq(
    issues,
    ReadOnlyArray::from_array([@nodeflow.EvaluationIssue::CyclicEvaluation]),
  )
  unbind(graph, add.inputs()[0])
  let waiting = number_at(graph, add.outputs()[0])
  let issues = unavailable_issues(waiting)
  assert_eq(
    issues,
    ReadOnlyArray::from_array([
      @nodeflow.EvaluationIssue::InputWaiting(add.inputs()[0]),
      @nodeflow.EvaluationIssue::InputWaiting(add.inputs()[1]),
    ]),
  )
  let ten = added_node(graph, @nodeflow.NodeDescriptor::Number(value=10))
  let twenty = added_node(graph, @nodeflow.NodeDescriptor::Number(value=20))
  bind(graph, add.inputs()[0], ten.outputs()[0])
  bind(graph, add.inputs()[1], twenty.outputs()[0])
  assert_eq(
    number_at(graph, add.outputs()[0]),
    @nodeflow.OutputObservation::Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(30)),
    ),
  )
  graph.close()
}

///|
fn bind(
  graph : @nodeflow.Nodeflow,
  target : @nodeflow.PortReference,
  provider : @nodeflow.PortReference,
) -> Unit raise @nodeflow.GraphPublicationError {
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        { target, binding: @nodeflow.BindingTarget::Bound(provider) },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
}

///|
fn unbind(
  graph : @nodeflow.Nodeflow,
  target : @nodeflow.PortReference,
) -> Unit raise @nodeflow.GraphPublicationError {
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        { target, binding: @nodeflow.BindingTarget::Unbound },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
}

///|
fn unavailable_issues(
  observation : @nodeflow.OutputObservation,
) -> ReadOnlyArray[@nodeflow.EvaluationIssue] {
  match observation {
    @nodeflow.OutputObservation::Unavailable(issues) => issues
    _ => abort("expected unavailable")
  }
}
