///|
test "restoration does not replay Action invocations" {
  let graph = Nodeflow::empty()
  let number = wb_added_node(
    graph,
    @application.NodeDescriptor::Number(value=7),
  )
  let display = wb_added_node(graph, @application.NodeDescriptor::Display)
  wb_bind(graph, display.inputs[0], number.outputs[0])
  let action = display.actions[0]
  ignore(graph.invoke(action))
  let original_runtime = graph.runtime.nodes.get(display.node.node).unwrap()
  assert_eq(original_runtime.action_invocation_count(), 1)

  let document = graph.document()
  graph.close()
  let restored_result = Nodeflow::restore(
    document,
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

///|
fn wb_restoration_node(
  id : Int,
  descriptor : @application.NodeDescriptor,
  bindings : Array[(Int, BindingTarget)],
) -> DocumentNode {
  { id, descriptor, bindings }
}

///|
fn wb_bound(graph : Int, node : Int, port : Int) -> BindingTarget {
  BindingTarget::Bound({ graph, node, port })
}

///|
test "restoration validates identity before binding details" {
  let graph = 41
  let duplicate_with_invalid_binding : GraphDocument = {
    wire: {
      version: 1,
      graph,
      next_node: 2,
      nodes: [
        wb_restoration_node(0, @application.NodeDescriptor::Add, [
          (9, wb_bound(graph, 99, 99)),
        ]),
        wb_restoration_node(0, @application.NodeDescriptor::Number(value=1), []),
      ],
    },
  }
  assert_eq(
    validate_document(duplicate_with_invalid_binding),
    Err(GraphRestorationRejection::DuplicateNode),
  )
  let beyond_frontier_with_duplicate : GraphDocument = {
    wire: {
      version: 1,
      graph,
      next_node: 1,
      nodes: [
        wb_restoration_node(1, @application.NodeDescriptor::Number(value=1), []),
        wb_restoration_node(1, @application.NodeDescriptor::Number(value=2), []),
      ],
    },
  }
  assert_eq(
    validate_document(beyond_frontier_with_duplicate),
    Err(GraphRestorationRejection::NodeBeyondFrontier),
  )
}

///|
test "restoration preserves binding rejection order" {
  let graph = 42
  let number = wb_restoration_node(
    1,
    @application.NodeDescriptor::Number(value=1),
    [],
  )
  let boolean = wb_restoration_node(
    2,
    @application.NodeDescriptor::Boolean(value=true),
    [],
  )
  let input_node = wb_restoration_node(3, @application.NodeDescriptor::Add, [])
  let check = (bindings, expected) => {
    let document : GraphDocument = {
      wire: {
        version: 1,
        graph,
        next_node: 4,
        nodes: [{ ..input_node, bindings, }, number, boolean],
      },
    }
    assert_eq(validate_document(document), Err(expected))
  }
  check(
    [(9, wb_bound(graph, 1, 0)), (9, BindingTarget::Unbound)],
    GraphRestorationRejection::InvalidDescriptor,
  )
  check(
    [(0, wb_bound(graph, 1, 0)), (0, BindingTarget::Unbound)],
    GraphRestorationRejection::DuplicateBindingTarget,
  )
  check(
    [(0, wb_bound(graph, 99, 0)), (1, wb_bound(graph, 2, 0))],
    GraphRestorationRejection::MissingEndpoint,
  )
  check(
    [(0, wb_bound(graph, 3, 0)), (1, wb_bound(graph, 2, 0))],
    GraphRestorationRejection::WrongDirection,
  )
  check(
    [(0, wb_bound(graph, 2, 0)), (1, wb_bound(graph, 99, 0))],
    GraphRestorationRejection::WrongType,
  )
}

///|
test "restoration accepts sparse non-monotonic provider identities" {
  let graph = 43
  let low = wb_restoration_node(7, @application.NodeDescriptor::Add, [
    (0, wb_bound(graph, 1000000, 0)),
  ])
  let high = wb_restoration_node(
    1000000,
    @application.NodeDescriptor::Number(value=1),
    [],
  )
  let middle = wb_restoration_node(999999, @application.NodeDescriptor::Add, [
    (0, wb_bound(graph, 7, 2)),
  ])
  let document : GraphDocument = {
    wire: { version: 1, graph, next_node: 1000001, nodes: [low, high, middle] },
  }
  assert_eq(validate_document(document), Ok(()))
}

///|
test "restoration preserves semantic rejection order across document nodes" {
  let graph = 44
  let wrong_type = wb_restoration_node(900, @application.NodeDescriptor::Add, [
    (0, wb_bound(graph, 2, 0)),
  ])
  let missing_endpoint = wb_restoration_node(
    3,
    @application.NodeDescriptor::Add,
    [(0, wb_bound(graph, 901, 0))],
  )
  let number = wb_restoration_node(
    1,
    @application.NodeDescriptor::Number(value=1),
    [],
  )
  let boolean = wb_restoration_node(
    2,
    @application.NodeDescriptor::Boolean(value=true),
    [],
  )
  let validate = nodes => {
    validate_document({ wire: { version: 1, graph, next_node: 901, nodes } })
  }
  assert_eq(
    validate([wrong_type, missing_endpoint, number, boolean]),
    Err(GraphRestorationRejection::WrongType),
  )
  assert_eq(
    validate([missing_endpoint, wrong_type, number, boolean]),
    Err(GraphRestorationRejection::MissingEndpoint),
  )
}

///|
test "late-invalid restoration fixture has a valid prefix" {
  let graph = 45
  let source = wb_restoration_node(
    0,
    @application.NodeDescriptor::Number(value=1),
    [],
  )
  let first = wb_restoration_node(1, @application.NodeDescriptor::Add, [
    (0, wb_bound(graph, 0, 0)),
  ])
  let second = wb_restoration_node(2, @application.NodeDescriptor::Add, [
    (0, wb_bound(graph, 1, 2)),
  ])
  let invalid_tail = wb_restoration_node(3, @application.NodeDescriptor::Add, [
    (0, wb_bound(graph, 4, 2)),
  ])
  let document = nodes => GraphDocument::{
    wire: { version: 1, graph, next_node: 4, nodes },
  }
  assert_eq(validate_document(document([source, first, second])), Ok(()))
  assert_eq(
    validate_document(document([source, first, second, invalid_tail])),
    Err(GraphRestorationRejection::MissingEndpoint),
  )
}
