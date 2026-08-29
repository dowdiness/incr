///|
test "failed Add publication quarantines the changed graph" {
  let graph = Nodeflow::empty()
  let existing = wb_added_node(
    graph,
    @application.NodeDescriptor::Number(value=1),
  )
  graph.runtime.nodes.get(existing.node.node).unwrap().close_runtime()

  let outcome : Result[Unit, GraphPublicationError] = try {
    ignore(
      graph.apply(
        GraphEdit::AddNode(
          descriptor=@application.NodeDescriptor::Number(value=2),
        ),
        ObservationDemand::empty().request(existing.outputs[0]),
      ),
    )
    Ok(())
  } catch {
    error => Err(error)
  }

  assert_true(outcome is Err(GraphPublicationError::ReadClosedRegion))
  assert_eq(graph.state.nodes.length(), 2)
  assert_true(graph.runtime.lifecycle.val is RuntimeLifecycle::Quarantined)

  let snapshot_rejected = try {
    ignore(graph.snapshot(ObservationDemand::empty()))
    false
  } catch {
    SurfaceReadError::ClosedNodeflow => true
    _ => false
  }
  assert_true(snapshot_rejected)
  let apply_rejected = try {
    ignore(
      graph.apply(
        GraphEdit::AddNode(
          descriptor=@application.NodeDescriptor::Number(value=3),
        ),
        ObservationDemand::empty(),
      ),
    )
    false
  } catch {
    GraphPublicationError::ClosedNodeflow => true
    _ => false
  }
  assert_true(apply_rejected)
  let invoke_rejected = try {
    ignore(
      graph.invoke({
        graph: graph.state.graph,
        node: existing.node.node,
        action: 0,
      }),
    )
    false
  } catch {
    ActionInvocationError::ClosedNodeflow => true
    _ => false
  }
  assert_true(invoke_rejected)

  graph.close()
  graph.close()
}

///|
test "failed Change publication quarantines the changed graph" {
  let graph = Nodeflow::empty()
  let demanded = wb_added_node(
    graph,
    @application.NodeDescriptor::Number(value=1),
  )
  let changed = wb_added_node(
    graph,
    @application.NodeDescriptor::Number(value=2),
  )
  graph.runtime.nodes.get(demanded.node.node).unwrap().close_runtime()

  let outcome : Result[Unit, GraphPublicationError] = try {
    ignore(
      graph.apply(
        GraphEdit::SetParameter(
          parameter=changed.parameters[0],
          value=@application.ParameterValue::Number(9),
        ),
        ObservationDemand::empty().request(demanded.outputs[0]),
      ),
    )
    Ok(())
  } catch {
    error => Err(error)
  }

  assert_true(outcome is Err(GraphPublicationError::ReadClosedRegion))
  assert_true(
    graph.state.nodes.get(changed.node.node).unwrap().descriptor
    is @application.NodeDescriptor::Number(value=9),
  )
  assert_true(graph.runtime.lifecycle.val is RuntimeLifecycle::Quarantined)
  graph.close()
}

///|
test "failed Remove publication quarantines the changed graph" {
  let graph = Nodeflow::empty()
  let demanded = wb_added_node(
    graph,
    @application.NodeDescriptor::Number(value=1),
  )
  let removed = wb_added_node(
    graph,
    @application.NodeDescriptor::Number(value=2),
  )
  graph.runtime.nodes.get(demanded.node.node).unwrap().close_runtime()

  let outcome : Result[Unit, GraphPublicationError] = try {
    ignore(
      graph.apply(
        GraphEdit::RemoveNodes(nodes=[removed.node]),
        ObservationDemand::empty().request(demanded.outputs[0]),
      ),
    )
    Ok(())
  } catch {
    error => Err(error)
  }

  assert_true(outcome is Err(GraphPublicationError::ReadClosedRegion))
  assert_true(graph.state.nodes.get(removed.node.node) is None)
  assert_true(graph.runtime.nodes.get(removed.node.node) is None)
  assert_true(graph.runtime.lifecycle.val is RuntimeLifecycle::Quarantined)
  graph.close()
}
