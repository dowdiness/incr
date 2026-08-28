///|
fn wb_added_node(
  graph : Nodeflow,
  descriptor : NodeDescriptor,
) -> AddedNode raise GraphPublicationError {
  match
    graph
    .apply(GraphEdit::AddNode(descriptor~), ObservationDemand::empty())
    .unwrap() {
    GraphEditResult::Added(node) => node
    Changed(_) => abort("expected added node")
  }
}

///|
fn wb_bind(
  graph : Nodeflow,
  target : PortReference,
  provider : PortReference,
) -> Unit raise GraphPublicationError {
  ignore(
    graph
    .apply(
      GraphEdit::BindingChangeSet(changes=[
        { target, binding: BindingTarget::Bound(provider) },
      ]),
      ObservationDemand::empty(),
    )
    .unwrap(),
  )
}

///|
fn wb_observe_number(
  graph : Nodeflow,
  output : PortReference,
) -> OutputObservation raise SurfaceReadError {
  graph.snapshot(ObservationDemand::empty().request(output)).observation(output)
}

///|
test "rebind retires the old provider from the Formula dependency trace" {
  let graph = Nodeflow::empty()
  let ten = wb_added_node(graph, NodeDescriptor::Number(value=10))
  let twenty = wb_added_node(graph, NodeDescriptor::Number(value=20))
  let two = wb_added_node(graph, NodeDescriptor::Number(value=2))
  let add = wb_added_node(graph, NodeDescriptor::Add)
  wb_bind(graph, add.inputs[0], ten.outputs[0])
  wb_bind(graph, add.inputs[1], twenty.outputs[0])
  assert_eq(
    wb_observe_number(graph, add.outputs[0]),
    OutputObservation::Current(
      OutputData::Number(NumberFormulaOutcome::Success(30)),
    ),
  )
  let runtime = graph.runtime.nodes.get(add.node.node).unwrap()
  assert_eq(runtime.formula_compute_count(), 1)

  wb_bind(graph, add.inputs[1], two.outputs[0])
  assert_eq(
    wb_observe_number(graph, add.outputs[0]),
    OutputObservation::Current(
      OutputData::Number(NumberFormulaOutcome::Success(12)),
    ),
  )
  assert_eq(runtime.formula_compute_count(), 2)

  ignore(
    graph
    .apply(
      GraphEdit::SetNumberParameter(node=twenty.node, value=100),
      ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    wb_observe_number(graph, add.outputs[0]),
    OutputObservation::Current(
      OutputData::Number(NumberFormulaOutcome::Success(12)),
    ),
  )
  assert_eq(runtime.formula_compute_count(), 2)

  ignore(
    graph
    .apply(
      GraphEdit::SetNumberParameter(node=two.node, value=3),
      ObservationDemand::empty(),
    )
    .unwrap(),
  )
  assert_eq(
    wb_observe_number(graph, add.outputs[0]),
    OutputObservation::Current(
      OutputData::Number(NumberFormulaOutcome::Success(13)),
    ),
  )
  assert_eq(runtime.formula_compute_count(), 3)
  graph.close()
}

///|
test "removed runtime is closed and survivor binding is unbound" {
  let graph = Nodeflow::empty()
  let provider = wb_added_node(graph, NodeDescriptor::Number(value=8))
  let add = wb_added_node(graph, NodeDescriptor::Add)
  wb_bind(graph, add.inputs[0], provider.outputs[0])
  let provider_view = match
    graph.runtime.nodes.get(provider.node.node).unwrap() {
    RuntimeNode::Number(_, _, view) => view
    _ => abort("expected number")
  }
  let survivor_input = match graph.runtime.nodes.get(add.node.node).unwrap() {
    RuntimeNode::Add(_, left, _, _, _) => left.view()
    _ => abort("expected add")
  }
  ignore(
    graph
    .apply(
      GraphEdit::RemoveNodes(nodes=[provider.node]),
      ObservationDemand::empty(),
    )
    .unwrap(),
  )
  try graph.runtime.store.get(provider_view) catch {
    @incr_query.ReadError::ClosedRegion(_) => ()
    _ => fail("expected closed region")
  } noraise {
    _ => fail("expected closed region")
  }
  match graph.runtime.store.get(survivor_input) {
    NumberBinding::Unbound => ()
    _ => fail("survivor input remained bound")
  }
  assert_true(graph.runtime.nodes.get(provider.node.node) is None)
  assert_true(graph.runtime.outputs.get(provider.outputs[0]) is None)
  graph.close()
}

///|
test "rejected stale removal does not close another runtime" {
  let graph = Nodeflow::empty()
  let removed = wb_added_node(graph, NodeDescriptor::Number(value=1))
  let survivor = wb_added_node(graph, NodeDescriptor::Number(value=2))
  let survivor_view = match
    graph.runtime.nodes.get(survivor.node.node).unwrap() {
    RuntimeNode::Number(_, _, view) => view
    _ => abort("expected number")
  }
  ignore(
    graph
    .apply(
      GraphEdit::RemoveNodes(nodes=[removed.node]),
      ObservationDemand::empty(),
    )
    .unwrap(),
  )
  match
    graph.apply(
      GraphEdit::RemoveNodes(nodes=[removed.node]),
      ObservationDemand::empty(),
    ) {
    Err(MissingNode) => ()
    _ => fail("expected stale removal rejection")
  }
  match graph.runtime.store.get(survivor_view) {
    NumberEvaluation::Current(NumberFormulaOutcome::Success(2)) => ()
    _ => fail("survivor runtime changed")
  }
  graph.close()
}

///|
test "quarantine rejects work but still permits deterministic close" {
  let graph = Nodeflow::empty()
  ignore(wb_added_node(graph, NodeDescriptor::Number(value=1)))
  graph.runtime.lifecycle.val = RuntimeLifecycle::Quarantined

  let snapshot_closed = Ok(graph.snapshot(ObservationDemand::empty())) catch {
    SurfaceReadError::ClosedNodeflow => Err(true)
    CrossStore
    | ClosedRegion
    | ExpiredContext
    | ReentrantRoot
    | DuringTransaction => Err(false)
  }
  assert_true(snapshot_closed.unwrap_err())

  let apply_closed = Ok(
    graph.apply(
      GraphEdit::AddNode(descriptor=NodeDescriptor::Number(value=2)),
      ObservationDemand::empty(),
    ),
  ) catch {
    GraphPublicationError::ClosedNodeflow => Err(true)
    RegionClosed
    | RegionMutationDuringEvaluation
    | RegionMutationDuringTransaction
    | ReadCrossStore
    | ReadClosedRegion
    | ReadExpiredContext
    | ReadReentrantRoot
    | ReadDuringTransaction => Err(false)
  }
  assert_true(apply_closed.unwrap_err())

  graph.close()
  assert_true(graph.runtime.lifecycle.val is RuntimeLifecycle::Closed)
  assert_true(graph.runtime.nodes.is_empty())
  assert_true(graph.runtime.outputs.is_empty())
}
