///|
priv struct Engine {
  worker_count : Int
  workers : Array[WorkerState]
  mailboxes : Array[Array[RoutedEnvelope]]
  transport : Array[RoutedEnvelope]
  mut source : @hashmap.HashMap[Edge, PositiveMultiplicity]
  mut materialized : @hashset.HashSet[Reach]
  mut phase : EpochPhase
  random : @splitmix.RandomState?
  trace : Array[TraceEvent]
  mut last_publication : Publication?
  mut published_count : Int
}

///|
fn Engine::Engine(worker_count : Int, scheduler_seed? : Int) -> Engine {
  guard worker_count > 0 else { abort("worker_count must be positive") }
  {
    worker_count,
    workers: Array::makei(worker_count, i => WorkerState(WorkerId(i))),
    mailboxes: Array::makei(worker_count, _ => []),
    transport: [],
    source: @hashmap.HashMap([]),
    materialized: @hashset.HashSet([]),
    phase: Ready(0),
    random: scheduler_seed.map(seed => @splitmix.new(seed=seed.to_uint64())),
    trace: [SchedulerConfigured(scheduler_seed)],
    last_publication: None,
    published_count: 0,
  }
}

///|
fn Engine::apply_epoch_transition(
  self : Engine,
  transition : EpochTransition,
) -> Unit {
  self.phase = transition.phase
  match transition.decision {
    None => ()
    Some(EpochOpenedDecision(epoch)) => self.trace.push(EpochOpened(epoch))
    Some(InputStagedDecision(epoch, batch)) =>
      self.trace.push(InputStaged(epoch, batch))
    Some(InputClosedDecision(epoch)) => {
      self.trace.push(InputClosedTrace(epoch))
      self.trace.push(ProgressChanged(epoch, InputClosed))
    }
    Some(SourceValidatedDecision(epoch)) =>
      self.trace.push(ProgressChanged(epoch, SourceValidated))
    Some(EpochRejectedDecision(epoch, error)) =>
      self.trace.push(EpochRejected(epoch, error))
    Some(PublicationCommittedDecision(epoch)) =>
      self.trace.push(ProgressChanged(epoch, Published))
  }
}

///|
fn Engine::run_epoch_event(
  self : Engine,
  event : EpochEvent,
) -> Result[Unit, ProtocolError] {
  match reduce_epoch(self.phase, event) {
    Err(error) => Err(error)
    Ok(transition) => {
      self.apply_epoch_transition(transition)
      Ok(())
    }
  }
}

///|
fn Engine::begin_epoch(
  self : Engine,
  epoch_value : Int,
) -> Result[Unit, ProtocolError] {
  self.run_epoch_event(BeginEpoch(epoch_value))
}

///|
fn Engine::stage_batch(
  self : Engine,
  epoch_value : Int,
  updates : Array[SourceUpdate],
) -> Result[Unit, ProtocolError] {
  self.run_epoch_event(StageEpoch(epoch_value, @vector.Vector(updates)))
}

///|
fn Engine::close_input(
  self : Engine,
  epoch_value : Int,
) -> Result[Unit, ProtocolError] {
  self.run_epoch_event(CloseInput(epoch_value))
}

///|
fn Engine::queue_envelope(self : Engine, envelope : RoutedEnvelope) -> Unit {
  let owned = copy_routed_envelope(envelope)
  self.transport.push(owned)
  self.trace.push(EnvelopeQueued(copy_routed_envelope(owned)))
}

///|
fn Engine::route_envelope(
  self : Engine,
  raw : RawEnvelope,
) -> Result[Unit, ProtocolError] {
  let context = routing_context(self.phase, self.worker_count)
  match parse_envelope(context, raw) {
    Err(error) => Err(error)
    Ok(envelope) => {
      self.queue_envelope(envelope)
      Ok(())
    }
  }
}

///|
fn Engine::route_envelopes(
  self : Engine,
  raws : ArrayView[RawEnvelope],
) -> Result[Unit, ProtocolError] {
  let context = routing_context(self.phase, self.worker_count)
  match parse_envelopes(context, raws) {
    Err(error) => Err(error)
    Ok(envelopes) => {
      envelopes.each(envelope => self.queue_envelope(envelope))
      Ok(())
    }
  }
}

///|
fn Engine::queue_drafts(
  self : Engine,
  epoch : Epoch,
  sender : WorkerId,
  drafts : ArrayView[EnvelopeDraft],
) -> Result[Unit, ProtocolError] {
  let raws : Array[RawEnvelope] = []
  for draft in drafts {
    let raw = match draft {
      FeedbackDraft(reach) =>
        RawEnvelope::{
          epoch,
          sender,
          receiver: owner_for_key(reach.target, self.worker_count),
          event: Feedback(reach),
        }
    }
    raws.push(raw)
  }
  self.route_envelopes(raws)
}

///|
fn Engine::pick_index(self : Engine, length : Int) -> Int {
  match self.random {
    None => 0
    Some(random) => random.next_positive_int() % length
  }
}

///|
fn Engine::route_one(self : Engine) -> Unit {
  let index = self.pick_index(self.transport.length())
  let envelope = self.transport.remove(index)
  let owned = copy_routed_envelope(envelope)
  self.mailboxes[envelope.receiver.0].push(owned)
  self.trace.push(EnvelopeRouted(copy_routed_envelope(owned)))
}

///|
fn Engine::ready_workers(self : Engine) -> Array[Int] {
  let ready : Array[Int] = []
  for i, mailbox in self.mailboxes {
    if !mailbox.is_empty() {
      ready.push(i)
    }
  }
  ready
}

///|
fn Engine::deliver_one(self : Engine) -> Result[Unit, ProtocolError] {
  let ready = self.ready_workers()
  if ready.is_empty() {
    return Ok(())
  }
  let worker_index = ready[self.pick_index(ready.length())]
  let mailbox = self.mailboxes[worker_index]
  let message_index = self.pick_index(mailbox.length())
  let envelope = mailbox.remove(message_index)
  self.trace.push(EnvelopeDelivered(copy_routed_envelope(envelope)))
  let worker = self.workers[worker_index]
  let (next_worker, drafts) = worker_reduce(
    worker,
    envelope.epoch,
    envelope.event,
  )
  self.workers[worker_index] = next_worker
  self.queue_drafts(envelope.epoch, next_worker.id, drafts)
}

///|
fn Engine::is_quiescent(self : Engine) -> Bool {
  self.transport.is_empty() && self.mailboxes.all(mailbox => mailbox.is_empty())
}

///|
fn Engine::drain(self : Engine) -> Result[Unit, ProtocolError] {
  for ;; {
    if self.is_quiescent() {
      break
    }
    if !self.transport.is_empty() {
      self.route_one()
    }
    match self.deliver_one() {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn Engine::queue_close_events(
  self : Engine,
  epoch : Epoch,
) -> Result[Unit, ProtocolError] {
  let raws = Array::makei(self.worker_count, worker_index => RawEnvelope::{
    epoch,
    sender: WorkerId(-1),
    receiver: WorkerId(worker_index),
    event: CloseEpoch,
  })
  self.route_envelopes(raws)
}

///|
fn Engine::queue_edge_updates(
  self : Engine,
  epoch : Epoch,
  updates : @vector.Vector[ValidatedEdgeUpdate],
) -> Result[Unit, ProtocolError] {
  let grouped : Array[Array[ValidatedEdgeUpdate]] = Array::makei(
    self.worker_count,
    _ => [],
  )
  updates.each(update => {
    let owner = owner_for_key(update.edge.from, self.worker_count)
    grouped[owner.0].push(update)
  })
  let raws : Array[RawEnvelope] = []
  for worker_index, batch in grouped {
    if !batch.is_empty() {
      raws.push({
        epoch,
        sender: WorkerId(-1),
        receiver: WorkerId(worker_index),
        event: ApplyEdges(@vector.Vector(batch)),
      })
    }
  }
  self.route_envelopes(raws)
}

///|
fn Engine::queue_origin_reset(
  self : Engine,
  epoch : Epoch,
  origins : @vector.Vector[Int],
) -> Result[Unit, ProtocolError] {
  let raws = Array::makei(self.worker_count, worker_index => RawEnvelope::{
    epoch,
    sender: WorkerId(-1),
    receiver: WorkerId(worker_index),
    event: ResetOrigins(origins),
  })
  self.route_envelopes(raws)
}

///|
fn Engine::queue_seeds(
  self : Engine,
  epoch : Epoch,
  origins : @vector.Vector[Int],
) -> Result[Unit, ProtocolError] {
  let raws : Array[RawEnvelope] = []
  for origin in origins {
    raws.push({
      epoch,
      sender: WorkerId(-1),
      receiver: owner_for_key(origin, self.worker_count),
      event: SeedOrigin(origin),
    })
  }
  self.route_envelopes(raws)
}

///|
fn Engine::collect_reachable(self : Engine) -> @hashset.HashSet[Reach] {
  let result : @hashset.HashSet[Reach] = @hashset.HashSet([])
  self.workers.each(worker => worker.reachable.each(reach => result.add(reach)))
  result
}

///|
fn Engine::workers_closed(self : Engine, epoch : Epoch) -> Bool {
  self.workers.all(worker => worker.closed_epoch == Some(epoch))
}

///|
fn Engine::prepare_closed_epoch(
  self : Engine,
) -> Result[(Epoch, ValidatedEpoch), ProtocolError] {
  let active = match parse_closed_epoch(self.phase) {
    Err(error) => return Err(error)
    Ok(active) => active
  }
  let epoch = active.epoch
  match prepare_epoch(self.source, active.staged) {
    Err(error) =>
      match reduce_epoch(self.phase, RejectSourceEpoch(epoch, error)) {
        Err(transition_error) => Err(transition_error)
        Ok(transition) => {
          self.apply_epoch_transition(transition)
          Err(error)
        }
      }
    Ok(validated) =>
      match reduce_epoch(self.phase, AcceptValidatedSource(epoch)) {
        Err(error) => Err(error)
        Ok(transition) => {
          self.apply_epoch_transition(transition)
          Ok((epoch, validated))
        }
      }
  }
}

///|
fn Engine::apply_source_epoch(
  self : Engine,
  epoch : Epoch,
  validated : ValidatedEpoch,
) -> Result[Unit, ProtocolError] {
  match self.queue_close_events(epoch) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.queue_edge_updates(epoch, validated.edge_updates) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.drain() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.source = validated.next_source
  self.trace.push(ProgressChanged(epoch, SourceApplied))
  Ok(())
}

///|
fn Engine::recompute_affected_origins(
  self : Engine,
  epoch : Epoch,
  changed_from : @vector.Vector[Int],
  previous : @hashset.HashSet[Reach],
) -> Result[Unit, ProtocolError] {
  let origins = affected_origins(changed_from, previous)
  if origins.is_empty() {
    return Ok(())
  }
  self.trace.push(ProgressChanged(epoch, Recomputing))
  match self.queue_origin_reset(epoch, origins) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.drain() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.queue_seeds(epoch, origins) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.drain()
}

///|
fn Engine::completion_facts(self : Engine, epoch : Epoch) -> CompletionFacts {
  let mailbox_pending = self.mailboxes.fold(init=0, (pending, mailbox) => {
    pending + mailbox.length()
  })
  {
    phase: self.phase,
    epoch,
    transport_pending: self.transport.length(),
    mailbox_pending,
    expected_workers: self.worker_count,
    workers: @vector.Vector(
      self.workers.map(worker => WorkerCompletionFact::{
        worker: worker.id,
        closed_epoch: worker.closed_epoch,
      }),
    ),
  }
}

///|
fn Engine::parse_completed_epoch(
  self : Engine,
  epoch : Epoch,
  previous : @hashset.HashSet[Reach],
) -> Result[CompletedEpoch, ProtocolError] {
  let evidence = match parse_completion(self.completion_facts(epoch)) {
    Err(error) => return Err(error)
    Ok(evidence) => evidence
  }
  let next_reachable = self.collect_reachable()
  Ok(complete_epoch(evidence, self.source, previous, next_reachable))
}

///|
fn Engine::publish_completed_epoch(
  self : Engine,
  completed : CompletedEpoch,
) -> Result[Publication, ProtocolError] {
  let epoch = completed.epoch
  let transition = match reduce_epoch(self.phase, CommitPublication(epoch)) {
    Err(error) => return Err(error)
    Ok(transition) => transition
  }
  let publication = completed.publication
  self.trace.push(ProgressChanged(epoch, Quiescent))
  self.materialized = completed.next_reachable
  self.last_publication = Some(copy_publication(publication))
  self.published_count = self.published_count + 1
  self.apply_epoch_transition(transition)
  self.trace.push(MaterializationPublished(copy_publication(publication)))
  Ok(copy_publication(publication))
}

///|
fn Engine::run_closed(self : Engine) -> Result[Publication, ProtocolError] {
  let (epoch, validated) = match self.prepare_closed_epoch() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let previous = self.materialized.copy()
  match self.apply_source_epoch(epoch, validated) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    self.recompute_affected_origins(epoch, validated.changed_from, previous) {
    Err(error) => return Err(error)
    Ok(_) =>
      match self.parse_completed_epoch(epoch, previous) {
        Err(error) => Err(error)
        Ok(completed) => self.publish_completed_epoch(completed)
      }
  }
}

///|
fn Engine::trace_snapshot(self : Engine) -> Array[TraceEvent] {
  self.trace.map(event => {
    match event {
      InputStaged(epoch, updates) => InputStaged(epoch, updates)
      EnvelopeQueued(envelope) => EnvelopeQueued(copy_routed_envelope(envelope))
      EnvelopeRouted(envelope) => EnvelopeRouted(copy_routed_envelope(envelope))
      EnvelopeDelivered(envelope) =>
        EnvelopeDelivered(copy_routed_envelope(envelope))
      MaterializationPublished(publication) =>
        MaterializationPublished(copy_publication(publication))
      other => other
    }
  })
}

///|
fn Engine::source_snapshot(self : Engine) -> Array[WeightedEdge] {
  canonical_source(self.source)
}

///|
fn Engine::reachable_snapshot(self : Engine) -> Array[Reach] {
  canonical_reachable(self.materialized)
}

///|
fn Engine::last_publication_snapshot(self : Engine) -> Publication? {
  self.last_publication.map(copy_publication)
}

///|
fn Engine::publication_count(self : Engine) -> Int {
  self.published_count
}

///|
fn Engine::shutdown(self : Engine) -> Unit {
  ignore(self.run_epoch_event(StopEngine))
  self.transport.clear()
  self.mailboxes.each(mailbox => mailbox.clear())
}
