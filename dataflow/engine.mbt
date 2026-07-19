///|
/// Imperative shell for the dataflow spike. Owns mutable state
/// (source graph, materialized reachability, lifecycle phase, worker
/// states, mailboxes, transport, trace, scheduler) and orchestrates
/// the epoch lifecycle: stage → close → validate → route → deliver →
/// drain → publish. All state transitions go through the pure
/// reducers in `core.mbt`; this struct only applies their results and
/// performs mutable scheduling, tracing, and publication effects.
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
/// Construct the engine with `worker_count` virtual workers. The
/// count must be > 0. Optional `scheduler_seed` enables deterministic
/// randomized scheduling; without it, delivery is always FIFO
/// (index 0). The phase starts at `Ready(0)`.
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
/// Shell-side effect handler: applies the pure reducer's phase
/// mutation and emits trace events for the decision. This is the
/// only place where `self.phase` is mutated from a reducer result.
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
/// Run a lifecycle event through the pure reducer and apply the
/// result. Returns the reducer's error without mutating state on
/// failure.
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
/// Shell entry point: open a new epoch. Delegates to
/// `run_epoch_event`.
fn Engine::begin_epoch(
  self : Engine,
  epoch_value : Int,
) -> Result[Unit, ProtocolError] {
  self.run_epoch_event(BeginEpoch(epoch_value))
}

///|
/// Shell entry point: stage a batch of source updates for the given
/// epoch. The input array is copied into an immutable persistent
/// `Vector`; caller mutation cannot affect the staged epoch.
fn Engine::stage_batch(
  self : Engine,
  epoch_value : Int,
  updates : Array[SourceUpdate],
) -> Result[Unit, ProtocolError] {
  self.run_epoch_event(StageEpoch(epoch_value, @vector.Vector(updates)))
}

///|
/// Shell entry point: close input for the given epoch. After close,
/// no further staging is accepted until the epoch completes.
fn Engine::close_input(
  self : Engine,
  epoch_value : Int,
) -> Result[Unit, ProtocolError] {
  self.run_epoch_event(CloseInput(epoch_value))
}

///|
/// Copy an admitted envelope wrapper into transport and record the enqueue.
/// Persistent event payloads are immutable, so they are safely shared.
fn Engine::queue_envelope(self : Engine, envelope : RoutedEnvelope) -> Unit {
  let owned = copy_routed_envelope(envelope)
  self.transport.push(owned)
  self.trace.push(EnvelopeQueued(copy_routed_envelope(owned)))
}

///|
/// Parse a single raw envelope and enqueue it into transport.
/// Parsing validates all trust boundaries before the envelope
/// enters engine state.
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
/// Batch version of `route_envelope`. Parses all envelopes first;
/// if any fails, none are enqueued (atomic batch).
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
/// Convert worker-produced envelope drafts into raw envelopes with
/// computed receivers, then route them through the standard parser.
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
/// Select a random index in `[0, length)` using the seeded RNG, or
/// 0 if no seed is configured. Used for randomized scheduling of
/// transport routing and mailbox delivery.
fn Engine::pick_index(self : Engine, length : Int) -> Int {
  match self.random {
    None => 0
    Some(random) => random.next_positive_int() % length
  }
}

///|
/// Move one envelope from transport to its target worker's mailbox. The shell
/// copies the wrapper for mailbox ownership while sharing immutable payloads.
fn Engine::route_one(self : Engine) -> Unit {
  let index = self.pick_index(self.transport.length())
  let envelope = self.transport.remove(index)
  let owned = copy_routed_envelope(envelope)
  self.mailboxes[envelope.receiver.0].push(owned)
  self.trace.push(EnvelopeRouted(copy_routed_envelope(owned)))
}

///|
/// Return indices of workers with non-empty mailboxes. Used by
/// `deliver_one` to select a ready worker.
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
/// Deliver one envelope to a ready worker: select a worker and
/// message index (randomized if seeded), snapshot the envelope for
/// the trace, run the pure worker reducer, swap in the new worker
/// state, and queue any produced drafts.
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
/// Return true when both transport and all mailboxes are empty.
/// Quiescence is required before completion evidence can be
/// gathered.
fn Engine::is_quiescent(self : Engine) -> Bool {
  self.transport.is_empty() && self.mailboxes.all(mailbox => mailbox.is_empty())
}

///|
/// Route and deliver all pending messages until quiescent.
/// Alternates between routing one transport message and delivering
/// one mailbox message. Returns the first delivery error
/// encountered.
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
/// Enqueue `CloseEpoch` messages for all workers. Sender is `-1`
/// (coordinator).
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
/// Group validated edge updates by target worker (via
/// `owner_for_key`) and enqueue per-worker `ApplyEdges` messages.
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
/// Enqueue `ResetOrigins` messages for all workers with the
/// affected origin set.
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
/// Enqueue `SeedOrigin` messages, one per affected origin, routed
/// to the owning worker.
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
/// Union all workers' reachable sets into a single `HashSet`.
/// Called after drain to gather the post-epoch closure.
fn Engine::collect_reachable(self : Engine) -> @hashset.HashSet[Reach] {
  let result : @hashset.HashSet[Reach] = @hashset.HashSet([])
  self.workers.each(worker => worker.reachable.each(reach => result.add(reach)))
  result
}

///|
/// Return true when every worker has observed close for the given epoch. This
/// is one completion condition; transport and mailboxes must also be empty.
fn Engine::workers_closed(self : Engine, epoch : Epoch) -> Bool {
  self.workers.all(worker => worker.closed_epoch == Some(epoch))
}

///|
/// Orchestrate the close→validate→accept flow: extract the closed
/// epoch, run `prepare_epoch`, and on success transition to
/// `Draining`. On validation failure, transition to `Ready(next)`
/// with a rejection decision and return the original error.
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
/// Apply the validated source batch: enqueue close events, edge
/// updates, drain, and commit the new source map. Traces
/// `SourceApplied` progress.
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
/// Clear stale reachability for affected origins, drain, then
/// re-seed and drain again. This is the bounded retraction
/// mechanism: only origins whose targets changed are recomputed,
/// leaving unaffected origins in place.
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
/// Gather completion state from the shell: transport/mailbox
/// counts, worker completion facts. This is the effectful
/// gathering step; the pure `parse_completion` validates it.
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
/// Gather completion facts, validate them through
/// `parse_completion`, then collect the union reachable set and
/// build the `CompletedEpoch`.
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
/// Transition to `Ready(next)` via `CommitPublication`, install
/// the new materialized set, record a defensive publication
/// snapshot, and increment the publication count.
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
/// Main orchestration pipeline for a closed epoch: validate →
/// apply source → recompute affected origins → parse completion →
/// publish. Each step returns early on error. The previous
/// materialized set is snapshotted before mutation for delta
/// computation.
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
/// Return a defensive trace snapshot. Envelope wrappers are rebuilt while
/// sharing immutable payloads; mutable publication arrays are copied.
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
/// Return a canonical sorted snapshot of the current source graph.
fn Engine::source_snapshot(self : Engine) -> Array[WeightedEdge] {
  canonical_source(self.source)
}

///|
/// Return a canonical sorted snapshot of the current materialized
/// reachability.
fn Engine::reachable_snapshot(self : Engine) -> Array[Reach] {
  canonical_reachable(self.materialized)
}

///|
/// Return a defensive copy of the last publication, or `None` if
/// no epoch has been published. The engine retains only a
/// defensive snapshot, not an unbounded materialization history.
fn Engine::last_publication_snapshot(self : Engine) -> Publication? {
  self.last_publication.map(copy_publication)
}

///|
/// Return the number of epochs published so far. Monotonically
/// increasing.
fn Engine::publication_count(self : Engine) -> Int {
  self.published_count
}

///|
/// Transition to `Stopped` and clear all transport and mailboxes.
/// Subsequent lifecycle events return `EngineStopped`.
fn Engine::shutdown(self : Engine) -> Unit {
  ignore(self.run_epoch_event(StopEngine))
  self.transport.clear()
  self.mailboxes.each(mailbox => mailbox.clear())
}
