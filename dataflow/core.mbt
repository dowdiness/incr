///|
/// Deterministic lifecycle, admission, completion, and worker policy live here
/// so correctness does not depend on mutable scheduling in `engine.mbt`.
///
/// Routed events rebuild only their wrapper: persistent `Vector` payloads are
/// immutable, so deep copying would add cost without adding isolation.
fn copy_routed_event(event : RoutedEvent) -> RoutedEvent {
  match event {
    ApplyEdges(updates) => ApplyEdges(updates)
    CloseEpoch => CloseEpoch
    ResetOrigins(origins) => ResetOrigins(origins)
    SeedOrigin(origin) => SeedOrigin(origin)
    Feedback(reach) => Feedback(reach)
  }
}

///|
/// Queue boundaries take a fresh envelope value but share immutable payloads;
/// the distinction avoids promising deep ownership the engine does not need.
fn copy_routed_envelope(envelope : RoutedEnvelope) -> RoutedEnvelope {
  {
    epoch: envelope.epoch,
    sender: envelope.sender,
    receiver: envelope.receiver,
    event: copy_routed_event(envelope.event),
  }
}

///|
/// Publication arrays are mutable, unlike routed vectors, so defensive copies
/// are required at retention and observation boundaries.
fn copy_publication(publication : Publication) -> Publication {
  {
    epoch: publication.epoch,
    source: publication.source.copy(),
    reachable: publication.reachable.copy(),
    delta: publication.delta.copy(),
  }
}

///|
/// Sorting prevents hash iteration order from leaking into replay, oracle
/// comparison, or user-visible publication.
fn canonical_source(
  source : @hashmap.HashMap[Edge, PositiveMultiplicity],
) -> Array[WeightedEdge] {
  let result = source
    .iter()
    .map(pair => {
      let (edge, PositiveMultiplicity(weight)) = pair
      WeightedEdge::{ edge, weight }
    })
    .to_array()
  result.sort()
  result
}

///|
/// Sorting removes scheduler and hash traversal order from reachability output.
fn canonical_reachable(reachable : @hashset.HashSet[Reach]) -> Array[Reach] {
  let result = reachable.to_array()
  result.sort()
  result
}

///|
/// Consolidation precedes validation because duplicate signed updates describe
/// one atomic net change; validating them individually would reject valid epochs.
fn consolidate_updates(
  updates : @vector.Vector[SourceUpdate],
) -> Array[ConsolidatedUpdate] {
  let sums : @hashmap.HashMap[Edge, Int] = @hashmap.HashMap([])
  updates.each(update => {
    sums.update_or_default(update.edge, update.diff, old => old + update.diff)
  })
  let result = sums
    .iter()
    .filter_map(pair => {
      let (edge, diff) = pair
      if diff == 0 {
        None
      } else {
        Some(ConsolidatedUpdate::{ edge, diff })
      }
    })
    .to_array()
  result.sort()
  result
}

///|
/// Validation builds a source copy before any worker mutation, preserving the
/// last completed state on rejection. Affected keys record only zero/positive
/// crossings because this spike models set closure, not path multiplicity.
fn prepare_epoch(
  source : @hashmap.HashMap[Edge, PositiveMultiplicity],
  staged : @vector.Vector[SourceUpdate],
) -> Result[ValidatedEpoch, ProtocolError] {
  let consolidated = consolidate_updates(staged)
  let next_source = source.copy()
  let mut edge_updates : @vector.Vector[ValidatedEdgeUpdate] = @vector.new()
  let changed_from : @hashset.HashSet[Int] = @hashset.HashSet([])
  for update in consolidated {
    let old_weight = match next_source.get(update.edge) {
      None => 0
      Some(PositiveMultiplicity(weight)) => weight
    }
    let next_weight = old_weight + update.diff
    if next_weight < 0 {
      return Err(InvalidSourceMultiplicity(update.edge, next_weight))
    }
    if (old_weight == 0) != (next_weight == 0) {
      changed_from.add(update.edge.from)
    }
    let next = if next_weight == 0 {
      next_source.remove(update.edge)
      Absent
    } else {
      let positive = PositiveMultiplicity(next_weight)
      next_source[update.edge] = positive
      Present(positive)
    }
    edge_updates = edge_updates.push({ edge: update.edge, next })
  }
  let changed = changed_from.to_array()
  changed.sort()
  Ok({ next_source, edge_updates, changed_from: @vector.Vector(changed) })
}

///|
/// Normalized modulo keeps ownership total for generated negative keys rather
/// than making the scheduler's partition function partial.
fn owner_for_key(key : Int, worker_count : Int) -> WorkerId {
  let remainder = key % worker_count
  WorkerId(if remainder < 0 { remainder + worker_count } else { remainder })
}

///|
/// Closed-epoch parsing keeps lifecycle misuse out of source validation, so the
/// latter can assume sealed input instead of rechecking phase flags.
fn parse_closed_epoch(phase : EpochPhase) -> Result[ClosedEpoch, ProtocolError] {
  match phase {
    Stopped => Err(EngineStopped)
    Ready(_) => Err(NoActiveEpoch)
    Open(active) => Err(EpochNotClosed(active.epoch.0))
    Closed(active) => Ok(active)
    Draining(active) => Err(EpochStillActive(active.epoch.0))
  }
}

///|
/// Lifecycle policy is a pure reducer so invalid transitions leave no partial
/// trace or state mutation. The shell has one choke point for applying the
/// returned phase and decision.
fn reduce_epoch(
  phase : EpochPhase,
  event : EpochEvent,
) -> Result[EpochTransition, ProtocolError] {
  match event {
    BeginEpoch(epoch_value) =>
      match phase {
        Stopped => Err(EngineStopped)
        Open(active) => Err(EpochStillActive(active.epoch.0))
        Closed(active) => Err(EpochStillActive(active.epoch.0))
        Draining(active) => Err(EpochStillActive(active.epoch.0))
        Ready(next_epoch) => {
          if epoch_value != next_epoch {
            return Err(EpochNotExpected(next_epoch, epoch_value))
          }
          let epoch = Epoch(epoch_value)
          Ok({
            phase: Open({ epoch, staged: @vector.new() }),
            decision: Some(EpochOpenedDecision(epoch)),
          })
        }
      }
    StageEpoch(epoch_value, batch) =>
      match phase {
        Stopped => Err(EngineStopped)
        Ready(_) => Err(NoActiveEpoch)
        Open(active) => {
          if active.epoch.0 != epoch_value {
            return Err(EpochMismatch(active.epoch.0, epoch_value))
          }
          Ok({
            phase: Open({
              epoch: active.epoch,
              staged: active.staged.concat(batch),
            }),
            decision: Some(InputStagedDecision(active.epoch, batch)),
          })
        }
        Closed(active) =>
          if active.epoch.0 != epoch_value {
            Err(EpochMismatch(active.epoch.0, epoch_value))
          } else {
            Err(UpdateAfterClose(epoch_value))
          }
        Draining(active) =>
          if active.epoch.0 != epoch_value {
            Err(EpochMismatch(active.epoch.0, epoch_value))
          } else {
            Err(UpdateAfterClose(epoch_value))
          }
      }
    CloseInput(epoch_value) =>
      match phase {
        Stopped => Err(EngineStopped)
        Ready(_) => Err(NoActiveEpoch)
        Open(active) => {
          if active.epoch.0 != epoch_value {
            return Err(EpochMismatch(active.epoch.0, epoch_value))
          }
          Ok({
            phase: Closed({ epoch: active.epoch, staged: active.staged }),
            decision: Some(InputClosedDecision(active.epoch)),
          })
        }
        Closed(active) =>
          if active.epoch.0 != epoch_value {
            Err(EpochMismatch(active.epoch.0, epoch_value))
          } else {
            Err(UpdateAfterClose(epoch_value))
          }
        Draining(active) =>
          if active.epoch.0 != epoch_value {
            Err(EpochMismatch(active.epoch.0, epoch_value))
          } else {
            Err(UpdateAfterClose(epoch_value))
          }
      }
    AcceptValidatedSource(epoch) =>
      match phase {
        Stopped => Err(EngineStopped)
        Ready(_) => Err(NoActiveEpoch)
        Open(active) =>
          if active.epoch != epoch {
            Err(EpochMismatch(active.epoch.0, epoch.0))
          } else {
            Err(EpochNotClosed(epoch.0))
          }
        Closed(active) =>
          if active.epoch != epoch {
            Err(EpochMismatch(active.epoch.0, epoch.0))
          } else {
            Ok({
              phase: Draining({ epoch, }),
              decision: Some(SourceValidatedDecision(epoch)),
            })
          }
        Draining(active) =>
          if active.epoch != epoch {
            Err(EpochMismatch(active.epoch.0, epoch.0))
          } else {
            Err(EpochStillActive(epoch.0))
          }
      }
    RejectSourceEpoch(epoch, error) =>
      match phase {
        Stopped => Err(EngineStopped)
        Ready(_) => Err(NoActiveEpoch)
        Open(active) =>
          if active.epoch != epoch {
            Err(EpochMismatch(active.epoch.0, epoch.0))
          } else {
            Err(EpochNotClosed(epoch.0))
          }
        Closed(active) =>
          if active.epoch != epoch {
            Err(EpochMismatch(active.epoch.0, epoch.0))
          } else {
            Ok({
              phase: Ready(epoch.0 + 1),
              decision: Some(EpochRejectedDecision(epoch, error)),
            })
          }
        Draining(active) =>
          if active.epoch != epoch {
            Err(EpochMismatch(active.epoch.0, epoch.0))
          } else {
            Err(EpochStillActive(epoch.0))
          }
      }
    CommitPublication(epoch) =>
      match phase {
        Stopped => Err(EngineStopped)
        Draining(active) =>
          if active.epoch != epoch {
            Err(EpochMismatch(active.epoch.0, epoch.0))
          } else {
            Ok({
              phase: Ready(epoch.0 + 1),
              decision: Some(PublicationCommittedDecision(epoch)),
            })
          }
        _ => Err(EpochNotPrepared(epoch.0))
      }
    StopEngine => Ok({ phase: Stopped, decision: None })
  }
}

///|
/// Routing receives a narrow capability rather than full phase state, limiting
/// what admission logic can depend on.
fn routing_context(phase : EpochPhase, worker_count : Int) -> RoutingContext {
  let gate = match phase {
    Stopped => RoutingStopped
    Draining(active) => RoutingPrepared(active.epoch)
    _ => RoutingNotPrepared
  }
  { gate, worker_count }
}

///|
/// Routing parses into a trusted type instead of returning a boolean, so queues
/// cannot retain unchecked sender, epoch, ownership, or multiplicity data.
fn parse_envelope(
  context : RoutingContext,
  raw : RawEnvelope,
) -> Result[RoutedEnvelope, ProtocolError] {
  let draining_epoch = match context.gate {
    RoutingStopped => return Err(EngineStopped)
    RoutingNotPrepared => return Err(EpochNotPrepared(raw.epoch.0))
    RoutingPrepared(epoch) => epoch
  }
  if draining_epoch != raw.epoch {
    return Err(EpochMismatch(draining_epoch.0, raw.epoch.0))
  }
  if raw.receiver.0 < 0 || raw.receiver.0 >= context.worker_count {
    return Err(InvalidWorker(raw.receiver.0))
  }
  if raw.sender.0 < -1 || raw.sender.0 >= context.worker_count {
    return Err(InvalidWorker(raw.sender.0))
  }
  match raw.event {
    ApplyEdges(updates) => {
      if raw.sender != WorkerId(-1) {
        return Err(InvalidRouteSender(ApplyEdgeRoute, raw.sender.0))
      }
      if updates.is_empty() {
        return Err(EmptyEdgeBatch)
      }
      for update in updates {
        match update.next {
          Present(PositiveMultiplicity(weight)) if weight <= 0 =>
            return Err(InvalidEdgeMultiplicity(update.edge, weight))
          _ => ()
        }
        let expected = owner_for_key(update.edge.from, context.worker_count).0
        if expected != raw.receiver.0 {
          return Err(
            InvalidRouteOwner(ApplyEdgeRoute, expected, raw.receiver.0),
          )
        }
      }
    }
    CloseEpoch =>
      if raw.sender != WorkerId(-1) {
        return Err(InvalidRouteSender(CloseEpochRoute, raw.sender.0))
      }
    ResetOrigins(_) =>
      if raw.sender != WorkerId(-1) {
        return Err(InvalidRouteSender(ResetOriginsRoute, raw.sender.0))
      }
    SeedOrigin(origin) => {
      if raw.sender != WorkerId(-1) {
        return Err(InvalidRouteSender(SeedOriginRoute, raw.sender.0))
      }
      let expected = owner_for_key(origin, context.worker_count).0
      if expected != raw.receiver.0 {
        return Err(InvalidRouteOwner(SeedOriginRoute, expected, raw.receiver.0))
      }
    }
    Feedback(reach) => {
      if raw.sender == WorkerId(-1) {
        return Err(InvalidRouteSender(FeedbackRoute, raw.sender.0))
      }
      let expected = owner_for_key(reach.target, context.worker_count).0
      if expected != raw.receiver.0 {
        return Err(InvalidRouteOwner(FeedbackRoute, expected, raw.receiver.0))
      }
    }
  }
  Ok({
    epoch: raw.epoch,
    sender: raw.sender,
    receiver: raw.receiver,
    event: copy_routed_event(raw.event),
  })
}

///|
/// The complete batch is parsed before enqueueing; otherwise a late malformed
/// envelope could leave an admitted prefix in transport.
fn parse_envelopes(
  context : RoutingContext,
  raws : ArrayView[RawEnvelope],
) -> Result[Array[RoutedEnvelope], ProtocolError] {
  let routed : Array[RoutedEnvelope] = []
  for raw in raws {
    match parse_envelope(context, raw) {
      Err(error) => return Err(error)
      Ok(envelope) => routed.push(envelope)
    }
  }
  Ok(routed)
}

///|
/// Completion requires empty queues and exact ordered coverage of
/// `0..<expected_workers`; a count or universal check alone would accept empty,
/// duplicate, missing, or extra participant sets.
fn parse_completion(
  facts : CompletionFacts,
) -> Result[CompletionEvidence, ProtocolError] {
  match facts.phase {
    Stopped => return Err(EngineStopped)
    Draining(active) =>
      if active.epoch != facts.epoch {
        return Err(EpochMismatch(active.epoch.0, facts.epoch.0))
      }
    _ => return Err(EpochNotPrepared(facts.epoch.0))
  }
  if facts.expected_workers <= 0 ||
    facts.workers.length() != facts.expected_workers {
    return Err(IncompleteEpoch(facts.epoch.0))
  }
  let (_, workers_closed) = facts.workers.fold(init=(0, true), (state, fact) => {
    let (index, closed) = state
    (
      index + 1,
      closed &&
      fact.worker == WorkerId(index) &&
      fact.closed_epoch == Some(facts.epoch),
    )
  })
  if facts.transport_pending != 0 ||
    facts.mailbox_pending != 0 ||
    !workers_closed {
    return Err(IncompleteEpoch(facts.epoch.0))
  }
  Ok({ epoch: facts.epoch })
}

///|
/// Requiring completion evidence makes premature publication unrepresentable
/// in the core; retaining or announcing the result remains a shell effect.
fn complete_epoch(
  evidence : CompletionEvidence,
  source : @hashmap.HashMap[Edge, PositiveMultiplicity],
  previous : @hashset.HashSet[Reach],
  next_reachable : @hashset.HashSet[Reach],
) -> CompletedEpoch {
  let epoch = evidence.epoch
  let publication : Publication = {
    epoch,
    source: canonical_source(source),
    reachable: canonical_reachable(next_reachable),
    delta: output_delta(previous, next_reachable),
  }
  { epoch, next_reachable, publication }
}

///|
/// Construction couples identity with empty owned arrangements so tests and the
/// shell cannot create an uninitialized worker piecemeal.
fn WorkerState::WorkerState(id : WorkerId) -> WorkerState {
  {
    id,
    edge_by_from: @hashmap.HashMap([]),
    reachable: @hashset.HashSet([]),
    closed_epoch: None,
  }
}

///|
/// Worker maps and sets require deep copies because they are mutable; this is
/// the cost paid to keep reducer inputs observationally immutable.
fn WorkerState::copy(self : WorkerState) -> WorkerState {
  let edge_by_from : @hashmap.HashMap[
    Int,
    @hashmap.HashMap[Int, PositiveMultiplicity],
  ] = @hashmap.HashMap([])
  self.edge_by_from.each((from, by_target) => {
    edge_by_from[from] = by_target.copy()
  })
  {
    id: self.id,
    edge_by_from,
    reachable: self.reachable.copy(),
    closed_epoch: self.closed_epoch,
  }
}

///|
/// In-place arrangement updates are confined to a fresh worker copy: mutable
/// hash tables are retained here as efficient builders, not exposed as stateful
/// reducer semantics.
fn WorkerState::apply_edges(
  self : WorkerState,
  updates : @vector.Vector[ValidatedEdgeUpdate],
) -> Unit {
  updates.each(update => {
    match update.next {
      Absent =>
        match self.edge_by_from.get(update.edge.from) {
          None => ()
          Some(by_target) => {
            by_target.remove(update.edge.to)
            if by_target.is_empty() {
              self.edge_by_from.remove(update.edge.from)
            }
          }
        }
      Present(weight) => {
        let by_target = self.edge_by_from.get_or_init(update.edge.from, () => {
          @hashmap.HashMap([])
        })
        by_target[update.edge.to] = weight
      }
    }
  })
}

///|
/// Retraction clears whole affected origins because the spike tracks no path
/// provenance. Unaffected origins remain to bound rebuild work.
fn WorkerState::reset_origins(
  self : WorkerState,
  origins : @vector.Vector[Int],
) -> Unit {
  let affected = @hashset.HashSet::from_iter(origins.iter())
  self.reachable.retain(reach => !affected.contains(reach.origin))
}

///|
/// Targets are sorted before feedback so hash-map iteration cannot alter the
/// seeded scheduler's replay sequence.
fn WorkerState::joined_targets(self : WorkerState, via : Int) -> Array[Int] {
  match self.edge_by_from.get(via) {
    None => []
    Some(by_target) => {
      let targets = by_target.keys().to_array()
      targets.sort()
      targets
    }
  }
}

///|
/// Expansion emits unrouted drafts so recursive work cannot bypass the same
/// ownership and protocol checks as coordinator work.
fn candidate_drafts(
  state : WorkerState,
  origin : Int,
  via : Int,
) -> Array[EnvelopeDraft] {
  state
  .joined_targets(via)
  .map(target => FeedbackDraft(Reach::{ origin, target }))
}

///|
/// The reducer copies before mutation and emits commands, allowing the shell to
/// replace worker state atomically. Set insertion gates feedback so cycles
/// terminate without path-count provenance.
fn worker_reduce(
  state : WorkerState,
  epoch : Epoch,
  event : RoutedEvent,
) -> (WorkerState, Array[EnvelopeDraft]) {
  let next = state.copy()
  let decisions = match event {
    ApplyEdges(updates) => {
      next.apply_edges(updates)
      []
    }
    CloseEpoch => {
      next.closed_epoch = Some(epoch)
      []
    }
    ResetOrigins(origins) => {
      next.reset_origins(origins)
      []
    }
    SeedOrigin(origin) => candidate_drafts(next, origin, origin)
    Feedback(reach) =>
      if next.reachable.add_and_check(reach) {
        candidate_drafts(next, reach.origin, reach.target)
      } else {
        []
      }
  }
  (next, decisions)
}

///|
/// Affected-origin rebuild is the deliberate substitute for general path
/// provenance: any origin previously reaching a changed source is rebuilt,
/// while positive-to-positive source changes are ignored under set semantics.
fn affected_origins(
  changed_from : @vector.Vector[Int],
  previous : @hashset.HashSet[Reach],
) -> @vector.Vector[Int] {
  let changed = @hashset.HashSet::from_iter(changed_from.iter())
  let affected = @hashset.HashSet::from_iter(changed_from.iter())
  previous.each(reach => {
    if changed.contains(reach.target) {
      affected.add(reach.origin)
    }
  })
  let result = affected.to_array()
  result.sort()
  @vector.Vector(result)
}

///|
/// Set semantics restrict output changes to ±1; canonical sorting keeps the
/// delta independent of hash and delivery order.
fn output_delta(
  previous : @hashset.HashSet[Reach],
  next : @hashset.HashSet[Reach],
) -> Array[ReachUpdate] {
  let removed = previous
    .iter()
    .filter_map(reach => {
      if next.contains(reach) {
        None
      } else {
        Some(ReachUpdate::{ reach, diff: -1 })
      }
    })
  let added = next
    .iter()
    .filter_map(reach => {
      if previous.contains(reach) {
        None
      } else {
        Some(ReachUpdate::{ reach, diff: 1 })
      }
    })
  let result = removed.concat(added).to_array()
  result.sort()
  result
}
