///|
priv struct Epoch(Int) derive(Eq, Debug)

///|
priv struct WorkerId(Int) derive(Eq, Debug)

///|
priv enum RouteId {
  ApplyEdgeRoute
  CloseEpochRoute
  ResetOriginsRoute
  SeedOriginRoute
  FeedbackRoute
} derive(Eq, Debug)

///|
priv struct PositiveMultiplicity(Int) derive(Eq, Debug)

///|
priv struct Edge {
  from : Int
  to : Int
} derive(Eq, Compare, Hash, Debug)

///|
priv struct Reach {
  origin : Int
  target : Int
} derive(Eq, Compare, Hash, Debug)

///|
priv struct SourceUpdate {
  edge : Edge
  diff : Int
} derive(Eq, Compare, Debug)

///|
priv struct ConsolidatedUpdate {
  edge : Edge
  diff : Int
} derive(Eq, Compare, Debug)

///|
priv enum EdgeMultiplicity {
  Absent
  Present(PositiveMultiplicity)
} derive(Eq, Debug)

///|
priv struct ValidatedEdgeUpdate {
  edge : Edge
  next : EdgeMultiplicity
} derive(Eq, Debug)

///|
priv struct ReachUpdate {
  reach : Reach
  diff : Int
} derive(Eq, Compare, Debug)

///|
priv struct WeightedEdge {
  edge : Edge
  weight : Int
} derive(Eq, Compare, Debug)

///|
priv enum ProtocolError {
  NoActiveEpoch
  EpochNotExpected(Int, Int)
  EpochMismatch(Int, Int)
  EpochStillActive(Int)
  UpdateAfterClose(Int)
  EpochNotClosed(Int)
  EpochNotPrepared(Int)
  InvalidSourceMultiplicity(Edge, Int)
  InvalidEdgeMultiplicity(Edge, Int)
  InvalidWorker(Int)
  EmptyEdgeBatch
  InvalidRouteSender(RouteId, Int)
  InvalidRouteOwner(RouteId, Int, Int)
  IncompleteEpoch(Int)
  EngineStopped
} derive(Eq, Debug)

///|
priv enum RoutedEvent {
  ApplyEdges(@vector.Vector[ValidatedEdgeUpdate])
  CloseEpoch
  ResetOrigins(@vector.Vector[Int])
  SeedOrigin(Int)
  Feedback(Reach)
} derive(Eq, Debug)

///|
priv struct RawEnvelope {
  epoch : Epoch
  sender : WorkerId
  receiver : WorkerId
  event : RoutedEvent
}

///|
priv struct RoutedEnvelope {
  epoch : Epoch
  sender : WorkerId
  receiver : WorkerId
  event : RoutedEvent
} derive(Eq, Debug)

///|
priv enum EnvelopeDraft {
  FeedbackDraft(Reach)
} derive(Eq, Debug)

///|
priv enum ProgressState {
  InputClosed
  SourceValidated
  SourceApplied
  Recomputing
  Quiescent
  Published
} derive(Eq, Debug)

///|
priv struct Publication {
  epoch : Epoch
  source : Array[WeightedEdge]
  reachable : Array[Reach]
  delta : Array[ReachUpdate]
} derive(Eq, Debug)

///|
priv enum TraceEvent {
  SchedulerConfigured(Int?)
  EpochOpened(Epoch)
  InputStaged(Epoch, @vector.Vector[SourceUpdate])
  InputClosedTrace(Epoch)
  ProgressChanged(Epoch, ProgressState)
  EnvelopeQueued(RoutedEnvelope)
  EnvelopeRouted(RoutedEnvelope)
  EnvelopeDelivered(RoutedEnvelope)
  EpochRejected(Epoch, ProtocolError)
  MaterializationPublished(Publication)
} derive(Eq, Debug)

///|
priv struct OpenEpoch {
  epoch : Epoch
  staged : @vector.Vector[SourceUpdate]
}

///|
priv struct ClosedEpoch {
  epoch : Epoch
  staged : @vector.Vector[SourceUpdate]
}

///|
priv struct DrainingEpoch {
  epoch : Epoch
}

///|
priv enum EpochPhase {
  Ready(Int)
  Open(OpenEpoch)
  Closed(ClosedEpoch)
  Draining(DrainingEpoch)
  Stopped
}

///|
priv enum EpochEvent {
  BeginEpoch(Int)
  StageEpoch(Int, @vector.Vector[SourceUpdate])
  CloseInput(Int)
  AcceptValidatedSource(Epoch)
  RejectSourceEpoch(Epoch, ProtocolError)
  CommitPublication(Epoch)
  StopEngine
}

///|
priv enum EpochDecision {
  EpochOpenedDecision(Epoch)
  InputStagedDecision(Epoch, @vector.Vector[SourceUpdate])
  InputClosedDecision(Epoch)
  SourceValidatedDecision(Epoch)
  EpochRejectedDecision(Epoch, ProtocolError)
  PublicationCommittedDecision(Epoch)
} derive(Eq, Debug)

///|
priv struct EpochTransition {
  phase : EpochPhase
  decision : EpochDecision?
}

///|
priv enum RoutingGate {
  RoutingStopped
  RoutingNotPrepared
  RoutingPrepared(Epoch)
}

///|
priv struct RoutingContext {
  gate : RoutingGate
  worker_count : Int
}

///|
priv struct WorkerCompletionFact {
  worker : WorkerId
  closed_epoch : Epoch?
}

///|
priv struct CompletionFacts {
  phase : EpochPhase
  epoch : Epoch
  transport_pending : Int
  mailbox_pending : Int
  expected_workers : Int
  workers : @vector.Vector[WorkerCompletionFact]
}

///|
priv struct CompletionEvidence {
  epoch : Epoch
}

///|
priv struct ValidatedEpoch {
  next_source : @hashmap.HashMap[Edge, PositiveMultiplicity]
  edge_updates : @vector.Vector[ValidatedEdgeUpdate]
  changed_from : @vector.Vector[Int]
}

///|
priv struct CompletedEpoch {
  epoch : Epoch
  next_reachable : @hashset.HashSet[Reach]
  publication : Publication
}

///|
priv struct WorkerState {
  id : WorkerId
  edge_by_from : @hashmap.HashMap[
    Int,
    @hashmap.HashMap[Int, PositiveMultiplicity],
  ]
  reachable : @hashset.HashSet[Reach]
  mut closed_epoch : Epoch?
}
