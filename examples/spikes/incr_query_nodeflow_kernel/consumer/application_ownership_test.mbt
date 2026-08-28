///|
test "application package owns closed Nodeflow semantics" {
  let graph = @nodeflow.Nodeflow::empty()
  let added = graph
    .apply(
      @nodeflow.GraphEdit::AddNode(
        descriptor=@application.NodeDescriptor::Number(value=10),
      ),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap()
  let number = match added {
    @nodeflow.GraphEditResult::Added(node) => node
    @nodeflow.GraphEditResult::Changed(_) => abort("expected added node")
  }
  let snapshot = graph.snapshot(
    @nodeflow.ObservationDemand::empty().request(number.outputs()[0]),
  )
  assert_eq(
    snapshot.observation(number.outputs()[0]),
    @nodeflow.OutputObservation::Current(
      @application.OutputData::Number(
        @application.NumberFormulaOutcome::Success(10),
      ),
    ),
  )
  graph.close()
}
