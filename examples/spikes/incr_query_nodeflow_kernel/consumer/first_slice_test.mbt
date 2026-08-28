///|
/// Consumer proof of the closed typed Nodeflow surface.
test "number add and multiply" {
  let graph = @nodeflow.Nodeflow::empty()
  let a = graph
    .apply(
      @nodeflow.GraphEdit::AddNode(
        descriptor=@nodeflow.NodeDescriptor::Number(value=10),
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap()
  let b = graph
    .apply(
      @nodeflow.GraphEdit::AddNode(
        descriptor=@nodeflow.NodeDescriptor::Number(value=20),
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap()
  let two = graph
    .apply(
      @nodeflow.GraphEdit::AddNode(
        descriptor=@nodeflow.NodeDescriptor::Number(value=2),
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap()
  let add = graph
    .apply(
      @nodeflow.GraphEdit::AddNode(descriptor=@nodeflow.NodeDescriptor::Add),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap()
  let add_node = match add {
    @nodeflow.GraphEditResult::Added(node) => node
    _ => fail("expected add")
  }
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        {
          target: add_node.inputs()[0],
          binding: @nodeflow.BindingTarget::Bound(output_of(a)),
        },
        {
          target: add_node.inputs()[1],
          binding: @nodeflow.BindingTarget::Bound(output_of(b)),
        },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  let multiply = graph
    .apply(
      @nodeflow.GraphEdit::AddNode(
        descriptor=@nodeflow.NodeDescriptor::Multiply,
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap()
  let multiply_node = match multiply {
    @nodeflow.GraphEditResult::Added(node) => node
    _ => fail("expected multiply")
  }
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        {
          target: multiply_node.inputs()[0],
          binding: @nodeflow.BindingTarget::Bound(add_node.outputs()[0]),
        },
        {
          target: multiply_node.inputs()[1],
          binding: @nodeflow.BindingTarget::Bound(output_of(two)),
        },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  let snapshot = graph.snapshot(
    @nodeflow.ObservationDemand::empty().request(multiply_node.outputs()[0]),
  )
  assert_eq(
    snapshot.observation(multiply_node.outputs()[0]),
    @nodeflow.OutputObservation::Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(60)),
    ),
  )
  graph.close()
}

///|
fn output_of(result : @nodeflow.GraphEditResult) -> @nodeflow.PortReference {
  match result {
    @nodeflow.GraphEditResult::Added(node) => node.outputs()[0]
    _ => abort("expected added")
  }
}

///|
test "close is idempotent" {
  let graph = @nodeflow.Nodeflow::empty()
  graph.close()
  graph.close()
}

///|
fn added_node(
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
    Changed(_) => abort("expected added node")
  }
}

///|
fn number_at(
  graph : @nodeflow.Nodeflow,
  output : @nodeflow.PortReference,
) -> @nodeflow.OutputObservation raise @nodeflow.SurfaceReadError {
  graph
  .snapshot(@nodeflow.ObservationDemand::empty().request(output))
  .observation(output)
}

///|
test "unbound required inputs keep math output unavailable" {
  let graph = @nodeflow.Nodeflow::empty()
  let add = added_node(graph, @nodeflow.NodeDescriptor::Add)
  assert_true(number_at(graph, add.outputs()[0]) is Unavailable(_))
  graph.close()
}

///|
test "type mismatch is rejected before replacing a valid binding" {
  let graph = @nodeflow.Nodeflow::empty()
  let number = added_node(graph, @nodeflow.NodeDescriptor::Number(value=10))
  let boolean = added_node(graph, @nodeflow.NodeDescriptor::Boolean(value=true))
  let add = added_node(graph, @nodeflow.NodeDescriptor::Add)
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        { target: add.inputs()[0], binding: Bound(number.outputs()[0]) },
        { target: add.inputs()[1], binding: Bound(number.outputs()[0]) },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    number_at(graph, add.outputs()[0]),
    Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(20)),
    ),
  )
  let rejected = graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        { target: add.inputs()[1], binding: Bound(boolean.outputs()[0]) },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap_err()
  assert_eq(rejected, @nodeflow.GraphEditRejection::WrongType)
  assert_eq(
    number_at(graph, add.outputs()[0]),
    Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(20)),
    ),
  )
  graph.close()
}

///|
test "duplicate binding targets reject the whole change set" {
  let graph = @nodeflow.Nodeflow::empty()
  let ten = added_node(graph, @nodeflow.NodeDescriptor::Number(value=10))
  let twenty = added_node(graph, @nodeflow.NodeDescriptor::Number(value=20))
  let add = added_node(graph, @nodeflow.NodeDescriptor::Add)
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        { target: add.inputs()[0], binding: Bound(ten.outputs()[0]) },
        { target: add.inputs()[1], binding: Bound(ten.outputs()[0]) },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  let rejected = graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        { target: add.inputs()[1], binding: Bound(twenty.outputs()[0]) },
        { target: add.inputs()[1], binding: Bound(ten.outputs()[0]) },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap_err()
  assert_eq(rejected, DuplicateBindingTarget)
  assert_eq(
    number_at(graph, add.outputs()[0]),
    Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(20)),
    ),
  )
  graph.close()
}

///|
test "rebind selects the new provider and old provider edits stay unrelated" {
  let graph = @nodeflow.Nodeflow::empty()
  let ten = added_node(graph, @nodeflow.NodeDescriptor::Number(value=10))
  let twenty = added_node(graph, @nodeflow.NodeDescriptor::Number(value=20))
  let two = added_node(graph, @nodeflow.NodeDescriptor::Number(value=2))
  let add = added_node(graph, @nodeflow.NodeDescriptor::Add)
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        { target: add.inputs()[0], binding: Bound(ten.outputs()[0]) },
        { target: add.inputs()[1], binding: Bound(twenty.outputs()[0]) },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    number_at(graph, add.outputs()[0]),
    Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(30)),
    ),
  )
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::BindingChangeSet(changes=[
        { target: add.inputs()[1], binding: Bound(two.outputs()[0]) },
      ]),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    number_at(graph, add.outputs()[0]),
    Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(12)),
    ),
  )
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::SetNumberParameter(node=twenty.node(), value=100),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    number_at(graph, add.outputs()[0]),
    Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(12)),
    ),
  )
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::SetNumberParameter(node=two.node(), value=3),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    number_at(graph, add.outputs()[0]),
    Current(
      @nodeflow.OutputData::Number(@nodeflow.NumberFormulaOutcome::Success(13)),
    ),
  )
  graph.close()
}
