///|
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
fn copy_routed_envelope(envelope : RoutedEnvelope) -> RoutedEnvelope {
  {
    epoch: envelope.epoch,
    sender: envelope.sender,
    receiver: envelope.receiver,
    event: copy_routed_event(envelope.event),
  }
}

///|
fn copy_publication(publication : Publication) -> Publication {
  {
    epoch: publication.epoch,
    source: publication.source.copy(),
    reachable: publication.reachable.copy(),
    delta: publication.delta.copy(),
  }
}

///|
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
fn canonical_reachable(reachable : @hashset.HashSet[Reach]) -> Array[Reach] {
  let result = reachable.to_array()
  result.sort()
  result
}

///|
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
fn owner_for_key(key : Int, worker_count : Int) -> WorkerId {
  let remainder = key % worker_count
  WorkerId(if remainder < 0 { remainder + worker_count } else { remainder })
}

///|
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
fn routing_context(phase : EpochPhase, worker_count : Int) -> RoutingContext {
  let gate = match phase {
    Stopped => RoutingStopped
    Draining(active) => RoutingPrepared(active.epoch)
    _ => RoutingNotPrepared
  }
  { gate, worker_count }
}

///|
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
fn WorkerState::WorkerState(id : WorkerId) -> WorkerState {
  {
    id,
    edge_by_from: @hashmap.HashMap([]),
    reachable: @hashset.HashSet([]),
    closed_epoch: None,
  }
}

///|
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
fn WorkerState::reset_origins(
  self : WorkerState,
  origins : @vector.Vector[Int],
) -> Unit {
  let affected = @hashset.HashSet::from_iter(origins.iter())
  self.reachable.retain(reach => !affected.contains(reach.origin))
}

///|
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
