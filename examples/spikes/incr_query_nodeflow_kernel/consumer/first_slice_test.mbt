///|
test "number node tracer slice" {
  let graph = @nodeflow.Nodeflow::empty()
  let applied = graph
    .apply(
      @nodeflow.GraphEdit::AddNumberNode(value=10),
      @nodeflow.ObservationDemand::empty(),
    )
    .unwrap()
  let output = applied.output()
  let snapshot = graph.snapshot(
    @nodeflow.ObservationDemand::empty().request(output),
  )
  match snapshot.observation(output) {
    @nodeflow.OutputObservation::Current(@nodeflow.OutputData::Number(value)) =>
      assert_eq(value, 10)
    _ => fail("expected current number output")
  }
  graph.close()
  graph.close()
}

///|
test "closed nodeflow rejects later reads and edits" {
  let graph = @nodeflow.Nodeflow::empty()
  graph.close()
  let snapshot_result : Result[@nodeflow.SurfaceSnapshot, String] = Ok(
    graph.snapshot(@nodeflow.ObservationDemand::empty()),
  ) catch {
    @nodeflow.SurfaceReadError::ClosedNodeflow => Err("closed")
    @nodeflow.SurfaceReadError::CrossStore => Err("cross-store")
    @nodeflow.SurfaceReadError::ClosedRegion => Err("closed-region")
    @nodeflow.SurfaceReadError::ExpiredContext => Err("expired")
    @nodeflow.SurfaceReadError::ReentrantRoot => Err("reentrant")
    @nodeflow.SurfaceReadError::DuringTransaction => Err("transaction")
  }
  assert_eq(snapshot_result.unwrap_err(), "closed")
  let apply_result : Result[
    Result[@nodeflow.GraphEditSuccess, @nodeflow.GraphEditRejection],
    String,
  ] = Ok(
    graph.apply(
      @nodeflow.GraphEdit::AddNumberNode(value=1),
      @nodeflow.ObservationDemand::empty(),
    ),
  ) catch {
    @nodeflow.GraphPublicationError::ClosedNodeflow => Err("closed")
    @nodeflow.GraphPublicationError::RegionClosed => Err("region-closed")
    @nodeflow.GraphPublicationError::RegionMutationDuringEvaluation =>
      Err("evaluation")
    @nodeflow.GraphPublicationError::RegionMutationDuringTransaction =>
      Err("transaction")
    @nodeflow.GraphPublicationError::ReadCrossStore => Err("cross-store")
    @nodeflow.GraphPublicationError::ReadClosedRegion => Err("read-closed")
    @nodeflow.GraphPublicationError::ReadExpiredContext => Err("expired")
    @nodeflow.GraphPublicationError::ReadReentrantRoot => Err("reentrant")
    @nodeflow.GraphPublicationError::ReadDuringTransaction =>
      Err("read-transaction")
  }
  assert_eq(apply_result.unwrap_err(), "closed")
}
