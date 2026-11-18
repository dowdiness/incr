///|
/// Domain types stay separate from `core.mbt` and `engine.mbt` so the trust
/// boundaries are visible without exposing a public API.
///
/// An epoch is distinct from worker and graph integers because protocol order
/// is strict. A handled epoch is consumed even when source validation rejects.
#derive(Eq, Debug)
priv struct Epoch(Int32)

///|
/// A distinct worker identity prevents graph keys from being used as routing
/// addresses. `-1` is reserved for the coordinator; workers are virtual local
/// states, not parallel threads.
#derive(Eq, Debug)
priv struct WorkerId(Int32)

///|
/// Route identities make protocol errors structural rather than stringly
/// typed. They describe admission rules, not independently executable ports.
#derive(Eq, Debug)
priv enum RouteId {
  ApplyEdgeRoute
  CloseEpochRoute
  ResetOriginsRoute
  SeedOriginRoute
  FeedbackRoute
}

///|
/// Positive multiplicity is a refinement produced only after whole-epoch
/// validation, so workers never need to defend against zero or negative state.
#derive(Eq, Debug)
priv struct PositiveMultiplicity(Int32)

///|
/// Edges support both hash lookup and total ordering because internal maps are
/// unordered while publications must be schedule-independent.
#derive(Eq, Compare, Hash, Debug)
priv struct Edge {
  from : Int32
  to : Int32
}

///|
/// Reachability is deliberately set-valued, not path-counted. This bounds
/// cycles and makes only zero/positive edge-presence changes semantically
/// relevant to closure.
#derive(Eq, Compare, Hash, Debug)
priv struct Reach {
  origin : Int32
  target : Int32
}

///|
/// Source input remains signed until the entire epoch is consolidated; checking
/// individual updates would incorrectly reject batches whose net state is valid.
#derive(Eq, Compare, Debug)
priv struct SourceUpdate {
  edge : Edge
  diff : Int32
}

///|
/// This type-state marks that duplicate updates have been combined and zero-net
/// changes removed before source validation.
#derive(Eq, Compare, Debug)
priv struct ConsolidatedUpdate {
  edge : Edge
  diff : Int32
}

///|
/// Exact absent-or-positive state prevents workers from reinterpreting raw
/// signed deltas or representing an invalid zero-weight edge.
#derive(Eq, Debug)
priv enum EdgeMultiplicity {
  Absent
  Present(PositiveMultiplicity)
}

///|
/// A validated update couples an edge with exact next state so the worker
/// boundary cannot accidentally accept a consolidated-but-unvalidated delta.
#derive(Eq, Debug)
priv struct ValidatedEdgeUpdate {
  edge : Edge
  next : EdgeMultiplicity
}

///|
/// Reachability deltas are restricted by the set model to presence changes;
/// they do not claim path provenance or multiplicity.
#derive(Eq, Compare, Debug)
priv struct ReachUpdate {
  reach : Reach
  diff : Int32
}

///|
/// Publications retain source weights separately from set-valued reachability,
/// because duplicate source support still matters to later retractions.
#derive(Eq, Compare, Debug)
priv struct WeightedEdge {
  edge : Edge
  weight : Int32
}

///|
/// Structured failures preserve the violated invariant for tests and replay;
/// atomicity is checked separately against retained state.
#derive(Eq, Debug)
priv enum ProtocolError {
  NoActiveEpoch
  EpochNotExpected(Int32, Int32)
  EpochMismatch(Int32, Int32)
  EpochStillActive(Int32)
  UpdateAfterClose(Int32)
  EpochNotClosed(Int32)
  EpochNotPrepared(Int32)
  InvalidSourceMultiplicity(Edge, Int32)
  InvalidEdgeMultiplicity(Edge, Int32)
  InvalidWorker(Int32)
  EmptyEdgeBatch
  InvalidRouteSender(RouteId, Int32)
  InvalidRouteOwner(RouteId, Int32, Int32)
  IncompleteEpoch(Int32)
  EngineStopped
}

///|
/// Event variants fuse operation and payload so invalid operator/port/event
/// combinations are unrepresentable after routing admission.
#derive(Eq, Debug)
priv enum RoutedEvent {
  ApplyEdges(@vector.Vector[ValidatedEdgeUpdate])
  CloseEpoch
  ResetOrigins(@vector.Vector[Int32])
  SeedOrigin(Int32)
  Feedback(Reach)
}

///|
/// Raw envelopes exist only at the shell boundary because sender, epoch, and
/// ownership constraints depend on runtime context and cannot be encoded in
/// the payload type alone.
priv struct RawEnvelope {
  epoch : Epoch
  sender : WorkerId
  receiver : WorkerId
  event : RoutedEvent
}

///|
/// Only this admitted form may enter queues. Persistent payloads can be shared
/// safely, avoiding a misleading and unnecessary deep-copy guarantee.
#derive(Eq, Debug)
priv struct RoutedEnvelope {
  epoch : Epoch
  sender : WorkerId
  receiver : WorkerId
  event : RoutedEvent
}

///|
/// Workers emit drafts rather than privileged envelopes so recursive feedback
/// must pass the same ownership and epoch checks as external routing.
#derive(Eq, Debug)
priv enum EnvelopeDraft {
  FeedbackDraft(Reach)
}

///|
/// Progress is intentionally coarser than control flow: traces expose stable
/// protocol milestones rather than every shell implementation detail.
#derive(Eq, Debug)
priv enum ProgressState {
  InputClosed
  SourceValidated
  SourceApplied
  Recomputing
  Quiescent
  Published
}

///|
/// Publication arrays are canonicalized to remove hash iteration and scheduler
/// order from observable results; this is a snapshot, not retained history.
#derive(Eq, Debug)
priv struct Publication {
  epoch : Epoch
  source : Array[WeightedEdge]
  reachable : Array[Reach]
  delta : Array[ReachUpdate]
}

///|
/// Traces retain protocol decisions and scheduling choices for replay. Snapshot
/// APIs copy mutable arrays so diagnostics cannot mutate engine state.
#derive(Eq, Debug)
priv enum TraceEvent {
  SchedulerConfigured(Int32?)
  EpochOpened(Epoch)
  InputStaged(Epoch, @vector.Vector[SourceUpdate])
  InputClosedTrace(Epoch)
  ProgressChanged(Epoch, ProgressState)
  EnvelopeQueued(RoutedEnvelope)
  EnvelopeRouted(RoutedEnvelope)
  EnvelopeDelivered(RoutedEnvelope)
  EpochRejected(Epoch, ProtocolError)
  MaterializationPublished(Publication)
}

///|
/// Staged input uses a persistent `Vector` so lifecycle values remain immutable
/// without copying the full batch at every stage transition.
priv struct OpenEpoch {
  epoch : Epoch
  staged : @vector.Vector[SourceUpdate]
}

///|
/// A distinct closed type-state prevents late input from being mistaken for
/// part of the epoch being validated.
priv struct ClosedEpoch {
  epoch : Epoch
  staged : @vector.Vector[SourceUpdate]
}

///|
/// Routing is gated on this post-validation type-state so workers cannot observe
/// a source epoch that might still be rejected.
priv struct DrainingEpoch {
  epoch : Epoch
}

///|
/// A sum type replaces parallel lifecycle flags, making contradictory states
/// such as open-and-draining unrepresentable.
priv enum EpochPhase {
  Ready(Int32)
  Open(OpenEpoch)
  Closed(ClosedEpoch)
  Draining(DrainingEpoch)
  Stopped
}

///|
/// Lifecycle requests are data so transition policy can be tested without
/// mutating the engine shell.
priv enum EpochEvent {
  BeginEpoch(Int32)
  StageEpoch(Int32, @vector.Vector[SourceUpdate])
  CloseInput(Int32)
  AcceptValidatedSource(Epoch)
  RejectSourceEpoch(Epoch, ProtocolError)
  CommitPublication(Epoch)
  StopEngine
}

///|
/// Decisions separate pure transition policy from tracing, scheduling, and
/// publication effects owned by the shell.
#derive(Eq, Debug)
priv enum EpochDecision {
  EpochOpenedDecision(Epoch)
  InputStagedDecision(Epoch, @vector.Vector[SourceUpdate])
  InputClosedDecision(Epoch)
  SourceValidatedDecision(Epoch)
  EpochRejectedDecision(Epoch, ProtocolError)
  PublicationCommittedDecision(Epoch)
}

///|
/// Phase and decision travel together so the shell cannot apply an effect from
/// a different transition.
priv struct EpochTransition {
  phase : EpochPhase
  decision : EpochDecision?
}

///|
/// A reduced routing capability avoids giving the envelope parser authority
/// over the full lifecycle state.
priv enum RoutingGate {
  RoutingStopped
  RoutingNotPrepared
  RoutingPrepared(Epoch)
}

///|
/// The parser receives only the runtime facts that static event types cannot
/// express: routing readiness and worker cardinality.
priv struct RoutingContext {
  gate : RoutingGate
  worker_count : Int32
}

///|
/// Completion facts carry worker identity and epoch, rather than a boolean
/// count, so duplicates and wrong participants cannot satisfy completion.
priv struct WorkerCompletionFact {
  worker : WorkerId
  closed_epoch : Epoch?
}

///|
/// Effect-derived completion facts remain untrusted until queue emptiness and
/// exact worker participation are checked together.
priv struct CompletionFacts {
  phase : EpochPhase
  epoch : Epoch
  transport_pending : Int32
  mailbox_pending : Int32
  expected_workers : Int32
  workers : @vector.Vector[WorkerCompletionFact]
}

///|
/// Evidence hides raw progress counters after validation, preventing
/// publication code from relying on unchecked or vacuously true facts.
priv struct CompletionEvidence {
  epoch : Epoch
}

///|
/// The next source is owned as a validated copy so rejection preserves the last
/// completed state. `changed_from` tracks only zero/positive crossings because
/// positive weight changes do not affect set closure.
priv struct ValidatedEpoch {
  next_source : @hashmap.HashMap[Edge, PositiveMultiplicity]
  edge_updates : @vector.Vector[ValidatedEdgeUpdate]
  changed_from : @vector.Vector[Int32]
}

///|
/// Final reachability and its publication are bound together so the shell
/// cannot install state different from the snapshot it exposes.
priv struct CompletedEpoch {
  epoch : Epoch
  next_reachable : @hashset.HashSet[Reach]
  publication : Publication
}

///|
/// Worker maps and sets are mutable internally for construction cost, but the
/// reducer copies before mutation. Workers model ownership isolation, not
/// parallel execution.
priv struct WorkerState {
  id : WorkerId
  edge_by_from : @hashmap.HashMap[
    Int32,
    @hashmap.HashMap[Int32, PositiveMultiplicity],
  ]
  reachable : @hashset.HashSet[Reach]
  mut closed_epoch : Epoch?
}
