///|
test "surface projection tracks rebind removal and restoration" {
  let graph = @nodeflow.Nodeflow::empty()
  let provider = surface_added_node(
    graph,
    @nodeflow.NodeDescriptor::Number(value=3),
  )
  let other = surface_added_node(
    graph,
    @nodeflow.NodeDescriptor::Number(value=4),
  )
  let add = surface_added_node(graph, @nodeflow.NodeDescriptor::Add)
  surface_bind(graph, add.inputs()[0], provider.outputs()[0])
  let before = graph.snapshot(@nodeflow.ObservationDemand::empty())
  assert_eq(before.nodes().length(), 3)
  assert_eq(before.ports().length(), 5)
  assert_eq(before.parameters().length(), 2)
  assert_eq(before.connections().length(), 1)
  surface_bind(graph, add.inputs()[0], other.outputs()[0])
  assert_eq(
    graph.snapshot(@nodeflow.ObservationDemand::empty()).connections()[0].output(),
    other.outputs()[0],
  )
  let document = graph.document()
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::RemoveNodes(nodes=[other.node()]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    graph.snapshot(@nodeflow.ObservationDemand::empty()).connections().length(),
    0,
  )
  let restored = @nodeflow.Nodeflow::restore(
    document,
    @nodeflow.ObservationDemand::empty(),
  ).unwrap()
  let restored_snapshot = restored.snapshot()
  assert_eq(restored_snapshot.nodes().length(), 3)
  assert_eq(restored_snapshot.connections().length(), 1)
  assert_eq(restored_snapshot.connections()[0].input(), add.inputs()[0])
  graph.close()
  restored.nodeflow().close()
}

///|
test "surface projection exposes semantic structure" {
  let graph = @nodeflow.Nodeflow::empty()
  let number = surface_added_node(
    graph,
    @nodeflow.NodeDescriptor::Number(value=7),
  )
  let display = surface_added_node(graph, @nodeflow.NodeDescriptor::Display)
  surface_bind(graph, display.inputs()[0], number.outputs()[0])
  let snapshot = graph.snapshot(@nodeflow.ObservationDemand::empty())
  assert_eq(snapshot.nodes().length(), 2)
  assert_eq(snapshot.nodes()[0].node(), number.node())
  assert_eq(snapshot.nodes()[0].kind(), @nodeflow.NodeKind::Number)
  assert_eq(snapshot.nodes()[1].node(), display.node())
  assert_eq(snapshot.nodes()[1].kind(), @nodeflow.NodeKind::Display)
  assert_eq(snapshot.ports().length(), 3)
  assert_eq(snapshot.ports()[0].port(), number.outputs()[0])
  assert_eq(snapshot.ports()[0].direction(), @nodeflow.PortDirection::Output)
  assert_eq(snapshot.ports()[0].value_type(), @nodeflow.PortValueType::Number)
  assert_eq(snapshot.ports()[0].required(), false)
  assert_eq(snapshot.ports()[1].port(), display.inputs()[0])
  assert_eq(snapshot.ports()[1].direction(), @nodeflow.PortDirection::Input)
  assert_eq(snapshot.ports()[1].required(), true)
  assert_eq(snapshot.parameters()[0].parameter(), number.parameters()[0])
  assert_eq(
    snapshot.parameters()[0].value(),
    @nodeflow.ParameterValue::Number(7),
  )
  assert_eq(snapshot.actions()[0].action(), display.actions()[0])
  assert_eq(snapshot.connections().length(), 1)
  assert_eq(snapshot.connections()[0].input(), display.inputs()[0])
  assert_eq(snapshot.connections()[0].output(), number.outputs()[0])
  graph.close()
}

///|
test "number and boolean parameter references are typed" {
  let graph = @nodeflow.Nodeflow::empty()
  let number = surface_added_node(
    graph,
    @nodeflow.NodeDescriptor::Number(value=7),
  )
  let boolean = surface_added_node(
    graph,
    @nodeflow.NodeDescriptor::Boolean(value=true),
  )
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::SetParameter(
        parameter=number.parameters()[0],
        value=@nodeflow.ParameterValue::Number(8),
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::SetParameter(
        parameter=boolean.parameters()[0],
        value=@nodeflow.ParameterValue::Boolean(false),
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    graph.snapshot(@nodeflow.ObservationDemand::empty()).parameters()[0].value(),
    @nodeflow.ParameterValue::Number(8),
  )
  assert_eq(
    graph.snapshot(@nodeflow.ObservationDemand::empty()).parameters()[1].value(),
    @nodeflow.ParameterValue::Boolean(false),
  )
  assert_eq(
    number_at(graph, number.outputs()[0]),
    @nodeflow.OutputObservation::Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(8)),
    ),
  )
  assert_eq(
    graph
    .snapshot(
      @nodeflow.ObservationDemand::empty().request(boolean.outputs()[0]),
    )
    .observation(boolean.outputs()[0]),
    @nodeflow.OutputObservation::Current(@nodeflow.OutputData::Boolean(false)),
  )
  let before_rejection = graph.document().encode_json()
  assert_true(
    graph
    .apply(
      @nodeflow.GraphEdit::SetParameter(
        parameter=number.parameters()[0],
        value=@nodeflow.ParameterValue::Boolean(true),
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap_err()
    is @nodeflow.GraphEditRejection::WrongParameterType,
  )
  assert_eq(graph.document().encode_json(), before_rejection)
  assert_eq(
    number_at(graph, number.outputs()[0]),
    @nodeflow.OutputObservation::Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(8)),
    ),
  )
  let stale_parameter = number.parameters()[0]
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::RemoveNodes(nodes=[number.node()]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  let after_removal = graph.document().encode_json()
  assert_true(
    graph
    .apply(
      @nodeflow.GraphEdit::SetParameter(
        parameter=stale_parameter,
        value=@nodeflow.ParameterValue::Number(1),
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap_err()
    is @nodeflow.GraphEditRejection::MissingParameter,
  )
  assert_eq(graph.document().encode_json(), after_removal)
  graph.close()
}

///|
fn surface_added_node(
  graph : @nodeflow.Nodeflow,
  descriptor : @nodeflow.NodeDescriptor,
) -> @nodeflow.AddedNode raise @nodeflow.GraphPublicationError {
  match
    graph
    .apply(
      @nodeflow.GraphEdit::AddNode(descriptor~),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap() {
    @nodeflow.GraphEditResult::Added(node) => node
    _ => abort("expected added node")
  }
}

///|
fn surface_bind(
  graph : @nodeflow.Nodeflow,
  input : @nodeflow.PortReference,
  output : @nodeflow.PortReference,
) -> Unit raise @nodeflow.GraphPublicationError {
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        { target: input, binding: @nodeflow.BindingTarget::Bound(output) },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
}
