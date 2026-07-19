///|
/// Private domain vocabulary for the dataflow spike. This file defines source,
/// reachability, lifecycle, routing, completion, trace, and worker-state values;
/// behavior lives in `core.mbt` and mutable orchestration in `engine.mbt`.
///
/// Monotonically increasing integer epoch. Exactly one epoch is active at a
/// time; the lifecycle reducer advances to `epoch + 1` on commit or reject.
priv struct Epoch(Int) derive(Eq, Debug)

///|
/// Virtual worker identity. Index into the engine's worker array.
/// `WorkerId(-1)` is the coordinator (shell); real workers use `0..N-1`.
priv struct WorkerId(Int) derive(Eq, Debug)

///|
/// Discriminator for routing rules. Each variant encodes which sender and
/// receiver identities are valid, enforced by `parse_envelope`.
priv enum RouteId {
  ApplyEdgeRoute
  CloseEpochRoute
  ResetOriginsRoute
  SeedOriginRoute
  FeedbackRoute
} derive(Eq, Debug)

///|
/// Strictly-positive integer edge multiplicity. Invariant: the wrapped
/// `Int` is always > 0. Constructed only by `prepare_epoch` after
/// rejecting non-positive weights.
priv struct PositiveMultiplicity(Int) derive(Eq, Debug)

///|
/// Directed graph edge. Hashable and comparable for canonical ordering.
priv struct Edge {
  from : Int
  to : Int
} derive(Eq, Compare, Hash, Debug)

///|
/// Set-valued reachability fact: `origin` can reach `target` via one or
/// more edges. Reachability is maintained as a finite set — cycles produce
/// a bounded closure, not unbounded path multiplicity.
priv struct Reach {
  origin : Int
  target : Int
} derive(Eq, Compare, Hash, Debug)

///|
/// Signed source-level delta from the caller. `diff` may be negative
/// (retraction). Consolidation sums per-edge before validation.
priv struct SourceUpdate {
  edge : Edge
  diff : Int
} derive(Eq, Compare, Debug)

///|
/// Post-consolidation non-zero per-edge delta. Zero-net edges are dropped.
priv struct ConsolidatedUpdate {
  edge : Edge
  diff : Int
} derive(Eq, Compare, Debug)

///|
/// Validated state of one edge after applying an epoch's updates.
/// `Absent` means multiplicity is zero (edge removed); `Present` carries
/// the new strictly-positive weight.
priv enum EdgeMultiplicity {
  Absent
  Present(PositiveMultiplicity)
} derive(Eq, Debug)

///|
/// Post-validation per-edge update. Carries the exact next multiplicity
/// (absent or positive) rather than a signed diff. Produced by
/// `prepare_epoch`; consumed by `WorkerState::apply_edges`.
priv struct ValidatedEdgeUpdate {
  edge : Edge
  next : EdgeMultiplicity
} derive(Eq, Debug)

///|
/// Signed delta on the reachability set. `diff` is +1 (added) or -1
/// (removed). Produced by `output_delta` for publication.
priv struct ReachUpdate {
  reach : Reach
  diff : Int
} derive(Eq, Compare, Debug)

///|
/// Canonical snapshot of one edge with its current positive multiplicity.
/// Used in `Publication.source` for deterministic comparison.
priv struct WeightedEdge {
  edge : Edge
  weight : Int
} derive(Eq, Compare, Debug)

///|
/// All protocol violations detectable during epoch lifecycle, routing,
/// and completion. Each variant identifies the failing invariant so the
/// shell can reject atomically without mutating completed state.
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
/// Parsed, typed event variant. Fuses the former operator, port, and
/// event combination into one enum. Only parsed routed envelopes enter
/// transport, mailboxes, traces, or a reducer.
priv enum RoutedEvent {
  ApplyEdges(@vector.Vector[ValidatedEdgeUpdate])
  CloseEpoch
  ResetOrigins(@vector.Vector[Int])
  SeedOrigin(Int)
  Feedback(Reach)
} derive(Eq, Debug)

///|
/// Unvalidated routing request created at a shell boundary. It must pass
/// `parse_envelope` to
/// become a `RoutedEnvelope`. Epoch, sender role, receiver identity,
/// positive multiplicity, and key ownership checks happen at that
/// parser boundary because they depend on runtime values.
priv struct RawEnvelope {
  epoch : Epoch
  sender : WorkerId
  receiver : WorkerId
  event : RoutedEvent
}

///|
/// Validated envelope produced by the routing parser. Its persistent payloads
/// are immutable and may be structurally shared; invalid roles, ownership, and
/// epochs are rejected before this value enters transport or mailboxes.
priv struct RoutedEnvelope {
  epoch : Epoch
  sender : WorkerId
  receiver : WorkerId
  event : RoutedEvent
} derive(Eq, Debug)

///|
/// Pre-routing feedback candidate produced by the worker reducer. The
/// shell converts drafts into raw envelopes and routes them through the
/// parser. Currently only `FeedbackDraft` exists.
priv enum EnvelopeDraft {
  FeedbackDraft(Reach)
} derive(Eq, Debug)

///|
/// Phase within a single epoch's processing. Tracks the progression
/// from input staging through validation, application, recomputation,
/// and publication. Recorded in `TraceEvent::ProgressChanged`.
priv enum ProgressState {
  InputClosed
  SourceValidated
  SourceApplied
  Recomputing
  Quiescent
  Published
} derive(Eq, Debug)

///|
/// Canonical output of a completed epoch. Contains the epoch number,
/// sorted source edges, sorted reachability set, and sorted reachability
/// delta. Produced by `complete_epoch` and returned by `Engine::run_closed`.
priv struct Publication {
  epoch : Epoch
  source : Array[WeightedEdge]
  reachable : Array[Reach]
  delta : Array[ReachUpdate]
} derive(Eq, Debug)

///|
/// Diagnostic events for replay and debugging. Recorded by the engine
/// shell as it processes lifecycle transitions, routes envelopes, and
/// publishes materializations. Snapshots return defensive copies.
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
/// Active epoch with staged input. The `staged` vector is immutable
/// (persistent `Vector`); staging appends by creating a new vector,
/// preserving prior phases.
priv struct OpenEpoch {
  epoch : Epoch
  staged : @vector.Vector[SourceUpdate]
}

///|
/// Closed epoch with staged input. Input is sealed; further staging
/// returns `UpdateAfterClose`. Validation and source application happen
/// from this phase.
priv struct ClosedEpoch {
  epoch : Epoch
  staged : @vector.Vector[SourceUpdate]
}

///|
/// Epoch in the draining phase after source validation. Routing is
/// prepared; envelopes for this epoch are accepted. Completion facts
/// are gathered in this phase.
priv struct DrainingEpoch {
  epoch : Epoch
}

///|
/// Lifecycle phase of the engine. Transitions are driven by the pure
/// `reduce_epoch` reducer (functional core). The shell applies the
/// returned phase immutably.
priv enum EpochPhase {
  Ready(Int)
  Open(OpenEpoch)
  Closed(ClosedEpoch)
  Draining(DrainingEpoch)
  Stopped
}

///|
/// Input event for the lifecycle reducer. Each variant triggers a
/// specific phase transition. The reducer returns an immutable next
/// phase plus an optional decision; the shell applies the decision.
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
/// Output decision from the lifecycle reducer. The shell records these
/// in the trace and executes side effects (scheduling, transport,
/// publication). Decisions are pure; effects belong to the shell.
priv enum EpochDecision {
  EpochOpenedDecision(Epoch)
  InputStagedDecision(Epoch, @vector.Vector[SourceUpdate])
  InputClosedDecision(Epoch)
  SourceValidatedDecision(Epoch)
  EpochRejectedDecision(Epoch, ProtocolError)
  PublicationCommittedDecision(Epoch)
} derive(Eq, Debug)

///|
/// Result of the lifecycle reducer. Contains the immutable next phase
/// and an optional decision. The shell applies the phase and executes
/// the decision's side effects.
priv struct EpochTransition {
  phase : EpochPhase
  decision : EpochDecision?
}

///|
/// Routing gate derived from the lifecycle phase. Routing is only
/// prepared in the `Draining` phase; otherwise envelopes are rejected.
priv enum RoutingGate {
  RoutingStopped
  RoutingNotPrepared
  RoutingPrepared(Epoch)
}

///|
/// Routing context combining the gate and expected worker count. Used
/// by `parse_envelope` to validate epoch, worker identities, and key
/// ownership.
priv struct RoutingContext {
  gate : RoutingGate
  worker_count : Int
}

///|
/// Per-worker completion fact. Reports whether the worker has closed
/// the epoch. Gathered by the shell into `CompletionFacts`.
priv struct WorkerCompletionFact {
  worker : WorkerId
  closed_epoch : Epoch?
}

///|
/// Global completion facts gathered by the shell. Includes pending
/// transport/mailbox counts, expected worker count, and per-worker
/// close facts. Parsed by `parse_completion` into evidence.
priv struct CompletionFacts {
  phase : EpochPhase
  epoch : Epoch
  transport_pending : Int
  mailbox_pending : Int
  expected_workers : Int
  workers : @vector.Vector[WorkerCompletionFact]
}

///|
/// Proof that all workers closed the epoch and all transport/mailboxes
/// drained. Constructed by `parse_completion`; consumed by
/// `complete_epoch` to build the final publication.
priv struct CompletionEvidence {
  epoch : Epoch
}

///|
/// Validated epoch ready for application. Contains the next source
/// map, validated edge updates, and the set of `from` nodes whose
/// edges changed presence (zero ↔ positive). Used to select affected
/// origins for recomputation.
priv struct ValidatedEpoch {
  next_source : @hashmap.HashMap[Edge, PositiveMultiplicity]
  edge_updates : @vector.Vector[ValidatedEdgeUpdate]
  changed_from : @vector.Vector[Int]
}

///|
/// Completed epoch with final reachability and publication. Produced
/// by `complete_epoch` after parsing completion evidence. The shell
/// publishes this and updates its materialized state.
priv struct CompletedEpoch {
  epoch : Epoch
  next_reachable : @hashset.HashSet[Reach]
  publication : Publication
}

///|
/// Worker-local state. Owns a keyed edge arrangement (`edge_by_from`),
/// a set of reached `Reach` facts, and an optional closed epoch.
/// The worker reducer is pure: it returns a new state plus feedback
/// drafts without mutating the input.
priv struct WorkerState {
  id : WorkerId
  edge_by_from : @hashmap.HashMap[
    Int,
    @hashmap.HashMap[Int, PositiveMultiplicity],
  ]
  reachable : @hashset.HashSet[Reach]
  mut closed_epoch : Epoch?
}
