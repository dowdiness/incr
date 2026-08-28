///|
test "Graph Document round-trip restores identities outputs and Actions" {
  let graph = @nodeflow.Nodeflow::empty()
  let ten = added_node(graph, @application.NodeDescriptor::Number(value=10))
  let twenty = added_node(graph, @application.NodeDescriptor::Number(value=20))
  let two = added_node(graph, @application.NodeDescriptor::Number(value=2))
  let add = added_node(graph, @application.NodeDescriptor::Add)
  bind(graph, add.inputs()[0], ten.outputs()[0])
  bind(graph, add.inputs()[1], twenty.outputs()[0])
  let multiply = added_node(graph, @application.NodeDescriptor::Multiply)
  bind(graph, multiply.inputs()[0], add.outputs()[0])
  bind(graph, multiply.inputs()[1], two.outputs()[0])
  let display = added_node(graph, @application.NodeDescriptor::Display)
  bind(graph, display.inputs()[0], multiply.outputs()[0])
  let action = display.actions()[0]
  assert_eq(
    graph.invoke(action),
    @nodeflow.ActionInvocationOutcome::Decided(
      @application.ApplicationDecision::Success(
        @application.Command::RecordNumber(60),
      ),
    ),
  )

  let document = graph.document()
  let encoded = document.encode_json()
  let decoded = @nodeflow.GraphDocument::decode_json(encoded).unwrap()
  assert_eq(decoded.encode_json(), encoded)
  let demand = @nodeflow.ObservationDemand::empty()
    .request(multiply.outputs()[0])
    .request_action(action)
  let restoration = @nodeflow.Nodeflow::restore(decoded, demand).unwrap()
  let restored = restoration.nodeflow()
  ignore(
    graph
    .apply(
      @nodeflow.GraphEdit::SetParameter(
        parameter=ten.parameters()[0],
        value=@application.ParameterValue::Number(99),
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(document.encode_json(), encoded)
  assert_eq(
    graph.invoke(action),
    @nodeflow.ActionInvocationOutcome::Decided(
      @application.ApplicationDecision::Success(
        @application.Command::RecordNumber(238),
      ),
    ),
  )
  assert_eq(
    restoration.snapshot().observation(multiply.outputs()[0]),
    @nodeflow.OutputObservation::Current(
      @application.OutputData::Number(
        @application.NumberFormulaOutcome::Success(60),
      ),
    ),
  )
  assert_eq(
    restoration.snapshot().action_observation(action),
    @nodeflow.ActionObservation::Present(
      @nodeflow.ActionAvailability::Available,
    ),
  )
  assert_eq(
    restored.invoke(action),
    @nodeflow.ActionInvocationOutcome::Decided(
      @application.ApplicationDecision::Success(
        @application.Command::RecordNumber(60),
      ),
    ),
  )
  let fresh = added_node(restored, @application.NodeDescriptor::Number(value=9))
  assert_true(fresh.node() != ten.node())
  assert_true(fresh.node() != display.node())
  graph.close()
  restored.close()
}

///|
test "Graph Document decoding separates syntax and shape errors" {
  assert_eq(
    decode_error_name(@nodeflow.GraphDocument::decode_json("{").unwrap_err()),
    "malformed",
  )
  assert_eq(
    decode_error_name(@nodeflow.GraphDocument::decode_json("[]").unwrap_err()),
    "shape",
  )
  assert_eq(
    decode_error_name(
      @nodeflow.GraphDocument::decode_json(
        "{\"version\":1,\"graph\":0,\"frontier\":0}",
      ).unwrap_err(),
    ),
    "shape",
  )
}

///|
fn decode_error_name(error : @nodeflow.GraphDocumentDecodeError) -> String {
  match error {
    @nodeflow.GraphDocumentDecodeError::MalformedJson => "malformed"
    WrongShape => "shape"
  }
}

///|
fn restoration_rejection(
  json : String,
) -> String raise @nodeflow.GraphRestorationError {
  let document = @nodeflow.GraphDocument::decode_json(json).unwrap()
  restoration_rejection_name(
    @nodeflow.Nodeflow::restore(document, @nodeflow.ObservationDemand::empty()).unwrap_err(),
  )
}

///|
fn restoration_rejection_name(
  rejection : @nodeflow.GraphRestorationRejection,
) -> String {
  match rejection {
    @nodeflow.GraphRestorationRejection::UnsupportedVersion => "version"
    InvalidGraphIdentity => "graph"
    InvalidFrontier => "frontier"
    DuplicateNode => "duplicate-node"
    NodeBeyondFrontier => "node-frontier"
    InvalidDescriptor => "descriptor"
    DuplicateBindingTarget => "duplicate-binding"
    MissingEndpoint => "missing-endpoint"
    WrongDirection => "direction"
    WrongType => "type"
  }
}

///|
test "Graph restoration validates semantic document invariants" {
  assert_eq(
    restoration_rejection(
      "{\"version\":2,\"graph\":0,\"frontier\":0,\"nodes\":[]}",
    ),
    "version",
  )
  assert_eq(
    restoration_rejection(
      "{\"version\":1,\"graph\":-1,\"frontier\":0,\"nodes\":[]}",
    ),
    "graph",
  )
  assert_eq(
    restoration_rejection(
      "{\"version\":1,\"graph\":0,\"frontier\":-1,\"nodes\":[]}",
    ),
    "frontier",
  )
  let number = "{\"id\":0,\"descriptor\":{\"kind\":\"number\",\"value\":1},\"bindings\":[]}"
  assert_eq(
    restoration_rejection(
      "{\"version\":1,\"graph\":0,\"frontier\":1,\"nodes\":[" +
      number +
      "," +
      number +
      "]}",
    ),
    "duplicate-node",
  )
  assert_eq(
    restoration_rejection(
      "{\"version\":1,\"graph\":0,\"frontier\":1,\"nodes\":[{\"id\":1,\"descriptor\":{\"kind\":\"number\",\"value\":1},\"bindings\":[]}]}",
    ),
    "node-frontier",
  )
  assert_eq(
    restoration_rejection(
      "{\"version\":1,\"graph\":0,\"frontier\":1,\"nodes\":[{\"id\":0,\"descriptor\":{\"kind\":\"add\"},\"bindings\":[{\"target\":0,\"provider\":[9,0]}]}]}",
    ),
    "missing-endpoint",
  )
  assert_eq(
    restoration_rejection(
      "{\"version\":1,\"graph\":0,\"frontier\":1,\"nodes\":[{\"id\":0,\"descriptor\":{\"kind\":\"add\"},\"bindings\":[{\"target\":0,\"provider\":[0,-1]}]}]}",
    ),
    "missing-endpoint",
  )
  assert_eq(
    restoration_rejection(
      "{\"version\":1,\"graph\":0,\"frontier\":2,\"nodes\":[{\"id\":0,\"descriptor\":{\"kind\":\"add\"},\"bindings\":[{\"target\":0,\"provider\":[1,0]}]},{\"id\":1,\"descriptor\":{\"kind\":\"add\"},\"bindings\":[]}]}",
    ),
    "direction",
  )
  assert_eq(
    restoration_rejection(
      "{\"version\":1,\"graph\":0,\"frontier\":2,\"nodes\":[{\"id\":0,\"descriptor\":{\"kind\":\"add\"},\"bindings\":[{\"target\":0,\"provider\":[1,0]}]},{\"id\":1,\"descriptor\":{\"kind\":\"boolean\",\"value\":true},\"bindings\":[]}]}",
    ),
    "type",
  )
  assert_eq(
    restoration_rejection(
      "{\"version\":1,\"graph\":0,\"frontier\":2,\"nodes\":[{\"id\":0,\"descriptor\":{\"kind\":\"add\"},\"bindings\":[{\"target\":0,\"provider\":[1,0]},{\"target\":0,\"provider\":null}]},{\"id\":1,\"descriptor\":{\"kind\":\"number\",\"value\":1},\"bindings\":[]}]}",
    ),
    "duplicate-binding",
  )
}
