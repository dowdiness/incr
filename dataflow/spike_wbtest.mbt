///|
fn test_update(from : Int, to : Int, diff : Int) -> SourceUpdate {
  { edge: { from, to }, diff }
}

///|
fn test_consolidated_update(
  from : Int,
  to : Int,
  diff : Int,
) -> ConsolidatedUpdate {
  { edge: { from, to }, diff }
}

///|
fn test_validated_update(
  from : Int,
  to : Int,
  next : Int,
) -> ValidatedEdgeUpdate {
  {
    edge: { from, to },
    next: if next == 0 {
      Absent
    } else {
      Present(PositiveMultiplicity(next))
    },
  }
}

///|
fn[A] test_vector(values : ArrayView[A]) -> @vector.Vector[A] {
  @vector.Vector(values)
}

///|
fn test_unwrap_publication(
  result : Result[Publication, ProtocolError],
) -> Publication raise Failure {
  match result {
    Ok(publication) => publication
    Err(_) => fail("expected a published epoch")
  }
}

///|
fn test_stage_batches(
  engine : Engine,
  epoch : Int,
  batches : Array[Array[SourceUpdate]],
) -> Result[Publication, ProtocolError] {
  match engine.begin_epoch(epoch) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for batch in batches {
    match engine.stage_batch(epoch, batch) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  match engine.close_input(epoch) {
    Err(error) => return Err(error)
    Ok(_) => engine.run_closed()
  }
}

///|
fn test_flatten_batches(
  batches : ArrayView[Array[SourceUpdate]],
) -> Array[SourceUpdate] {
  let result : Array[SourceUpdate] = []
  batches.each(batch => result.append(batch))
  result
}

///|
fn test_assert_matches_oracle(
  engine : Engine,
  oracle : Oracle,
  epoch : Int,
  batches : Array[Array[SourceUpdate]],
) -> Publication raise Failure {
  let expected = oracle.apply(epoch, test_flatten_batches(batches))
  let actual = test_stage_batches(engine, epoch, batches)
  guard actual == expected else { fail("engine diverged from oracle") }
  test_unwrap_publication(actual)
}

///|
fn test_reaches(pairs : Array[(Int, Int)]) -> Array[Reach] {
  let result = pairs.map(pair => {
    let (origin, target) = pair
    Reach::{ origin, target }
  })
  result.sort()
  result
}

///|
test "consolidation removes zero-net updates and sorts canonically" {
  let updates = [
    test_update(2, 3, 1),
    test_update(1, 2, -1),
    test_update(2, 3, 2),
    test_update(1, 2, 1),
  ]
  guard consolidate_updates(test_vector(updates)) ==
    [test_consolidated_update(2, 3, 3)] else {
    fail("consolidation did not remove zero-net updates")
  }
}

///|
test "source threshold changes only when support crosses zero" {
  let source : @hashmap.HashMap[Edge, PositiveMultiplicity] = @hashmap.HashMap([])
  let inserted = prepare_epoch(source, test_vector([test_update(1, 2, 2)]))
  let prepared = match inserted {
    Ok(value) => value
    Err(_) => fail("positive insertion was rejected")
  }
  guard prepared.changed_from == test_vector([1]) &&
    prepared.edge_updates == test_vector([test_validated_update(1, 2, 2)]) else {
    fail("zero-to-positive transition was not parsed")
  }
  let partial = prepare_epoch(
    prepared.next_source,
    test_vector([test_update(1, 2, -1)]),
  )
  match partial {
    Ok(value) => {
      guard value.changed_from.is_empty() &&
        value.edge_updates == test_vector([test_validated_update(1, 2, 1)]) else {
        fail("positive-to-positive transition was not parsed")
      }
    }
    Err(_) => fail("partial retraction was rejected")
  }
  let final_retraction = prepare_epoch(
    prepared.next_source,
    test_vector([test_update(1, 2, -2)]),
  )
  match final_retraction {
    Ok(value) => {
      guard value.changed_from == test_vector([1]) &&
        value.edge_updates == test_vector([test_validated_update(1, 2, 0)]) else {
        fail("positive-to-zero transition was not parsed")
      }
    }
    Err(_) => fail("final valid retraction was rejected")
  }
}

///|
test "invalid epoch is rejected atomically and a later epoch completes" {
  let engine = Engine(2, scheduler_seed=17)
  let oracle = Oracle()
  ignore(
    test_assert_matches_oracle(engine, oracle, 0, [
      [test_update(1, 2, 1), test_update(2, 3, 1)],
    ]),
  )
  let source_before = engine.source_snapshot()
  let reachable_before = engine.reachable_snapshot()
  let publication_count_before = engine.publication_count()
  let invalid = [test_update(1, 2, -2), test_update(3, 4, 1)]
  let actual = test_stage_batches(engine, 1, [invalid])
  let expected = oracle.apply(1, invalid)
  guard actual == expected else { fail("invalid epoch result disagreed") }
  guard actual is Err(InvalidSourceMultiplicity(_, -1)) else {
    fail("invalid source multiplicity was not reported")
  }
  guard engine.source_snapshot() == source_before &&
    engine.reachable_snapshot() == reachable_before &&
    engine.publication_count() == publication_count_before else {
    fail("rejected epoch mutated completed state")
  }
  let recovered = test_assert_matches_oracle(engine, oracle, 2, [
    [test_update(3, 4, 1)],
  ])
  guard recovered.reachable.contains(Reach::{ origin: 3, target: 4 }) else {
    fail("later valid epoch did not complete")
  }
}

///|
test "close rejects later input and blocks the next epoch until completion" {
  let engine = Engine(1)
  guard engine.begin_epoch(0) == Ok(()) else { fail("epoch did not open") }
  guard engine.stage_batch(0, [test_update(1, 2, 1)]) == Ok(()) else {
    fail("input was not staged")
  }
  guard engine.close_input(0) == Ok(()) else { fail("close failed") }
  guard engine.stage_batch(0, [test_update(2, 3, 1)]) ==
    Err(UpdateAfterClose(0)) else {
    fail("update after close was accepted")
  }
  guard engine.begin_epoch(1) == Err(EpochStillActive(0)) else {
    fail("later epoch opened before completion")
  }
  ignore(test_unwrap_publication(engine.run_closed()))
  guard engine.begin_epoch(1) == Ok(()) else {
    fail("later epoch did not open after completion")
  }
}

///|
test "staging converts caller arrays to immutable epoch values" {
  let engine = Engine(1)
  guard engine.begin_epoch(0) == Ok(()) else { fail("epoch did not open") }
  let updates = [test_update(1, 2, 1)]
  guard engine.stage_batch(0, updates) == Ok(()) else {
    fail("input was not staged")
  }
  updates[0] = test_update(9, 9, 1)
  guard engine.close_input(0) == Ok(()) else { fail("close failed") }
  let publication = test_unwrap_publication(engine.run_closed())
  guard publication.source ==
    [WeightedEdge::{ edge: { from: 1, to: 2 }, weight: 1 }] else {
    fail("caller mutation changed immutable staged input")
  }
}

///|
test "epoch lifecycle reducer preserves prior immutable phases" {
  let opened = match reduce_epoch(Ready(0), BeginEpoch(0)) {
    Err(_) => fail("pure reducer rejected the expected epoch")
    Ok(transition) => transition
  }
  let first_batch = test_vector([test_update(1, 2, 1)])
  let staged = match reduce_epoch(opened.phase, StageEpoch(0, first_batch)) {
    Err(_) => fail("pure reducer rejected valid staged input")
    Ok(transition) => transition
  }
  guard opened.phase is Open(active) && active.staged.is_empty() else {
    fail("staging mutated the prior epoch phase")
  }
  guard staged.decision == Some(InputStagedDecision(Epoch(0), first_batch)) else {
    fail("pure reducer did not return the staging decision")
  }
  let closed = match reduce_epoch(staged.phase, CloseInput(0)) {
    Err(_) => fail("pure reducer rejected close")
    Ok(transition) => transition
  }
  guard closed.phase is Closed(active) && active.staged == first_batch else {
    fail("close did not retain immutable staged input")
  }
  guard reduce_epoch(closed.phase, StageEpoch(0, @vector.new()))
    is Err(UpdateAfterClose(0)) else {
    fail("pure reducer changed the update-after-close protocol")
  }
  let accepted = match
    reduce_epoch(closed.phase, AcceptValidatedSource(Epoch(0))) {
    Err(_) => fail("pure reducer rejected validated source")
    Ok(transition) => transition
  }
  guard accepted.phase is Draining(active) &&
    active.epoch == Epoch(0) &&
    accepted.decision == Some(SourceValidatedDecision(Epoch(0))) else {
    fail("validated source did not enter the draining phase")
  }
  let committed = match
    reduce_epoch(accepted.phase, CommitPublication(Epoch(0))) {
    Err(_) => fail("pure reducer rejected completed publication")
    Ok(transition) => transition
  }
  guard committed.phase is Ready(1) &&
    committed.decision == Some(PublicationCommittedDecision(Epoch(0))) else {
    fail("publication did not advance the epoch")
  }
  let source_error = InvalidSourceMultiplicity({ from: 1, to: 2 }, -1)
  let rejected = match
    reduce_epoch(closed.phase, RejectSourceEpoch(Epoch(0), source_error)) {
    Err(_) => fail("pure reducer rejected source rejection")
    Ok(transition) => transition
  }
  guard rejected.phase is Ready(1) &&
    rejected.decision == Some(EpochRejectedDecision(Epoch(0), source_error)) else {
    fail("source rejection did not preserve the lifecycle decision")
  }
}

///|
test "completion parser requires explicit global facts" {
  let epoch = Epoch(0)
  let complete : CompletionFacts = {
    phase: Draining({ epoch, }),
    epoch,
    transport_pending: 0,
    mailbox_pending: 0,
    expected_workers: 2,
    workers: test_vector([
      WorkerCompletionFact::{ worker: WorkerId(0), closed_epoch: Some(epoch) },
      WorkerCompletionFact::{ worker: WorkerId(1), closed_epoch: Some(epoch) },
    ]),
  }
  guard parse_completion(CompletionFacts::{ ..complete, transport_pending: 1 })
    is Err(IncompleteEpoch(0)) &&
    parse_completion(CompletionFacts::{ ..complete, mailbox_pending: 1 })
    is Err(IncompleteEpoch(0)) &&
    parse_completion(CompletionFacts::{
      ..complete,
      workers: test_vector([
        WorkerCompletionFact::{ worker: WorkerId(0), closed_epoch: Some(epoch) },
        WorkerCompletionFact::{ worker: WorkerId(1), closed_epoch: None },
      ]),
    })
    is Err(IncompleteEpoch(0)) &&
    parse_completion(CompletionFacts::{ ..complete, workers: @vector.new() })
    is Err(IncompleteEpoch(0)) &&
    parse_completion(CompletionFacts::{
      ..complete,
      workers: test_vector([
        WorkerCompletionFact::{ worker: WorkerId(0), closed_epoch: Some(epoch) },
      ]),
    })
    is Err(IncompleteEpoch(0)) &&
    parse_completion(CompletionFacts::{
      ..complete,
      workers: test_vector([
        WorkerCompletionFact::{ worker: WorkerId(0), closed_epoch: Some(epoch) },
        WorkerCompletionFact::{ worker: WorkerId(0), closed_epoch: Some(epoch) },
      ]),
    })
    is Err(IncompleteEpoch(0)) &&
    parse_completion(CompletionFacts::{
      ..complete,
      workers: test_vector([
        WorkerCompletionFact::{ worker: WorkerId(1), closed_epoch: Some(epoch) },
        WorkerCompletionFact::{ worker: WorkerId(0), closed_epoch: Some(epoch) },
      ]),
    })
    is Err(IncompleteEpoch(0)) &&
    parse_completion(CompletionFacts::{
      ..complete,
      workers: test_vector([
        WorkerCompletionFact::{ worker: WorkerId(0), closed_epoch: Some(epoch) },
        WorkerCompletionFact::{ worker: WorkerId(1), closed_epoch: Some(epoch) },
        WorkerCompletionFact::{ worker: WorkerId(2), closed_epoch: Some(epoch) },
      ]),
    })
    is Err(IncompleteEpoch(0)) &&
    parse_completion(CompletionFacts::{
      ..complete,
      expected_workers: 0,
      workers: @vector.new(),
    })
    is Err(IncompleteEpoch(0)) else {
    fail("completion parser accepted incomplete global facts")
  }
  let evidence = match parse_completion(complete) {
    Err(_) => fail("completion parser rejected complete global facts")
    Ok(evidence) => evidence
  }
  let source = @hashmap.HashMap::from_iter(
    [({ from: 1, to: 2 }, PositiveMultiplicity(1))].iter(),
  )
  let previous : @hashset.HashSet[Reach] = @hashset.HashSet([])
  let next = @hashset.HashSet::from_iter(
    [Reach::{ origin: 1, target: 2 }].iter(),
  )
  let completed = complete_epoch(evidence, source, previous, next)
  guard completed.publication.source ==
    [WeightedEdge::{ edge: { from: 1, to: 2 }, weight: 1 }] &&
    completed.publication.reachable == [Reach::{ origin: 1, target: 2 }] else {
    fail("completion evidence did not build the expected publication")
  }
}

///|
test "immutable routed payload does not alias caller update buffers" {
  let engine = Engine(2)
  engine.phase = Draining({ epoch: Epoch(0) })
  let updates = [test_validated_update(1, 2, 1)]
  let raw : RawEnvelope = {
    epoch: Epoch(0),
    sender: WorkerId(-1),
    receiver: WorkerId(1),
    event: ApplyEdges(test_vector(updates)),
  }
  guard engine.route_envelope(raw) == Ok(()) else {
    fail("valid raw envelope was not parsed")
  }
  updates[0] = test_validated_update(9, 9, 1)
  guard engine.drain() == Ok(()) else { fail("queued envelope did not drain") }
  let arranged = engine.workers[1].edge_by_from.get(1)
  guard arranged is Some(by_target) &&
    by_target.get(2) == Some(PositiveMultiplicity(1)) else {
    fail("caller mutation changed queued work")
  }
  guard engine.workers[1].edge_by_from.get(9) is None else {
    fail("caller-owned mutation crossed the envelope boundary")
  }
}

///|
test "raw envelope parser rejects unprepared stale and misrouted input" {
  let engine = Engine(2)
  let valid : RawEnvelope = {
    epoch: Epoch(0),
    sender: WorkerId(-1),
    receiver: WorkerId(1),
    event: ApplyEdges(test_vector([test_validated_update(1, 2, 1)])),
  }
  guard engine.route_envelope(valid) == Err(EpochNotPrepared(0)) &&
    engine.workers[1].edge_by_from.is_empty() else {
    fail("unprepared envelope reached worker state")
  }
  engine.phase = Draining({ epoch: Epoch(0) })
  let stale = RawEnvelope::{ ..valid, epoch: Epoch(1) }
  guard engine.route_envelope(stale) == Err(EpochMismatch(0, 1)) else {
    fail("stale envelope entered the prepared epoch")
  }
  let misrouted : RawEnvelope = {
    epoch: Epoch(0),
    sender: WorkerId(0),
    receiver: WorkerId(0),
    event: Feedback({ origin: 0, target: 1 }),
  }
  guard engine.route_envelope(misrouted) ==
    Err(InvalidRouteOwner(FeedbackRoute, 1, 0)) else {
    fail("misrouted feedback entered the wrong worker")
  }
  let misrouted_seed : RawEnvelope = {
    epoch: Epoch(0),
    sender: WorkerId(-1),
    receiver: WorkerId(1),
    event: SeedOrigin(0),
  }
  guard engine.route_envelope(misrouted_seed) ==
    Err(InvalidRouteOwner(SeedOriginRoute, 0, 1)) else {
    fail("misrouted seed entered the wrong worker")
  }
}

///|
test "raw envelope parser returns structured identity and payload errors" {
  let engine = Engine(1)
  engine.phase = Draining({ epoch: Epoch(0) })
  let invalid_worker : RawEnvelope = {
    epoch: Epoch(0),
    sender: WorkerId(-1),
    receiver: WorkerId(4),
    event: ApplyEdges(@vector.new()),
  }
  guard engine.route_envelope(invalid_worker) == Err(InvalidWorker(4)) else {
    fail("invalid worker identity was accepted")
  }
  let empty_batch : RawEnvelope = {
    epoch: Epoch(0),
    sender: WorkerId(-1),
    receiver: WorkerId(0),
    event: ApplyEdges(@vector.new()),
  }
  guard engine.route_envelope(empty_batch) == Err(EmptyEdgeBatch) else {
    fail("empty edge batch was accepted")
  }
  let non_positive : RawEnvelope = {
    epoch: Epoch(0),
    sender: WorkerId(-1),
    receiver: WorkerId(0),
    event: ApplyEdges(
      test_vector([
        { edge: { from: 0, to: 1 }, next: Present(PositiveMultiplicity(0)) },
      ]),
    ),
  }
  guard engine.route_envelope(non_positive) ==
    Err(InvalidEdgeMultiplicity({ from: 0, to: 1 }, 0)) else {
    fail("non-positive edge multiplicity was accepted")
  }
  let forged_apply : RawEnvelope = {
    epoch: Epoch(0),
    sender: WorkerId(0),
    receiver: WorkerId(0),
    event: ApplyEdges(test_vector([test_validated_update(0, 1, 1)])),
  }
  guard engine.route_envelope(forged_apply) ==
    Err(InvalidRouteSender(ApplyEdgeRoute, 0)) else {
    fail("worker forged a coordinator edge update")
  }
  let forged_feedback : RawEnvelope = {
    epoch: Epoch(0),
    sender: WorkerId(-1),
    receiver: WorkerId(0),
    event: Feedback({ origin: 0, target: 0 }),
  }
  guard engine.route_envelope(forged_feedback) ==
    Err(InvalidRouteSender(FeedbackRoute, -1)) &&
    engine.transport.is_empty() else {
    fail(
      "coordinator forged worker feedback or rejected input reached transport",
    )
  }
  let valid_close : RawEnvelope = {
    epoch: Epoch(0),
    sender: WorkerId(-1),
    receiver: WorkerId(0),
    event: CloseEpoch,
  }
  let forged_close = RawEnvelope::{ ..valid_close, sender: WorkerId(0) }
  guard engine.route_envelopes([valid_close, forged_close])
    is Err(InvalidRouteSender(CloseEpochRoute, 0)) &&
    engine.transport.is_empty() else {
    fail("batch routing partially enqueued before a later parse error")
  }
}

///|
test "arranged join and recursive threshold suppress duplicate feedback" {
  let epoch = Epoch(0)
  let initial = WorkerState(WorkerId(0))
  let (arranged, _) = worker_reduce(
    initial,
    epoch,
    ApplyEdges(
      test_vector([
        test_validated_update(0, 1, 1),
        test_validated_update(1, 2, 1),
      ]),
    ),
  )
  guard initial.edge_by_from.is_empty() else {
    fail("worker reducer mutated its input state")
  }
  let (seeded, seed) = worker_reduce(arranged, epoch, SeedOrigin(0))
  let first_reach = Reach::{ origin: 0, target: 1 }
  guard seed == [FeedbackDraft(first_reach)] else {
    fail("seed did not join with the keyed edge arrangement")
  }
  let (first_state, first) = worker_reduce(seeded, epoch, Feedback(first_reach))
  guard first == [FeedbackDraft({ origin: 0, target: 2 })] else {
    fail("feedback join did not produce the next candidate")
  }
  let (_, duplicate) = worker_reduce(first_state, epoch, Feedback(first_reach))
  guard duplicate.is_empty() else {
    fail("threshold admitted duplicate recursive feedback")
  }
}

///|
test "materialization is published only after global quiescence" {
  let engine = Engine(4, scheduler_seed=42)
  guard engine.begin_epoch(0) == Ok(()) else { fail("epoch did not open") }
  guard engine.stage_batch(0, [test_update(0, 1, 1), test_update(1, 2, 1)]) ==
    Ok(()) else {
    fail("batch did not stage")
  }
  guard engine.close_input(0) == Ok(()) else { fail("close failed") }
  guard engine.publication_count() == 0 else {
    fail("close published before work drained")
  }
  let publication = test_unwrap_publication(engine.run_closed())
  guard engine.is_quiescent() && engine.workers_closed(Epoch(0)) else {
    fail("publication occurred before global completion")
  }
  let expected_reachable = publication.reachable.copy()
  publication.reachable.clear()
  let retained = match engine.last_publication_snapshot() {
    None => false
    Some(snapshot) => snapshot.reachable == expected_reachable
  }
  guard retained && engine.publication_count() == 1 else {
    fail("snapshot-only publication retention aliased returned output")
  }
  let trace = engine.trace_snapshot()
  guard trace.last() is Some(MaterializationPublished(_)) else {
    fail("materialization was not the final decision")
  }
}

///|
test "publication retention keeps only the defensive latest snapshot" {
  let engine = Engine(1)
  let first = test_unwrap_publication(
    test_stage_batches(engine, 0, [[test_update(0, 1, 1)]]),
  )
  first.source.clear()
  let second = test_unwrap_publication(
    test_stage_batches(engine, 1, [[test_update(1, 2, 1)]]),
  )
  second.reachable.clear()
  let latest_is_epoch_one = match engine.last_publication_snapshot() {
    None => false
    Some(snapshot) =>
      snapshot.epoch == Epoch(1) && !snapshot.reachable.is_empty()
  }
  guard engine.publication_count() == 2 && latest_is_epoch_one else {
    fail("publication retention did not replace the defensive latest snapshot")
  }
}

///|
test "required reachability graph cases terminate and match full recomputation" {
  let cases : Array[(String, Array[Array[Array[SourceUpdate]]])] = [
    ("empty", [[[]]]),
    ("one edge", [[[test_update(1, 2, 1)]]]),
    (
      "chain",
      [[[test_update(1, 2, 1), test_update(2, 3, 1), test_update(3, 4, 1)]]],
    ),
    (
      "duplicate partial retraction",
      [[[test_update(1, 2, 2)]], [[test_update(1, 2, -1)]]],
    ),
    (
      "alternate paths and final support removal",
      [
        [
          [
            test_update(1, 2, 1),
            test_update(2, 4, 1),
            test_update(1, 3, 1),
            test_update(3, 4, 1),
          ],
        ],
        [[test_update(2, 4, -1)]],
        [[test_update(3, 4, -1)]],
      ],
    ),
    ("self cycle", [[[test_update(1, 1, 1)]]]),
    (
      "multi node cycle",
      [[[test_update(1, 2, 1), test_update(2, 3, 1), test_update(3, 1, 1)]]],
    ),
    (
      "cycle with acyclic tail",
      [
        [
          [
            test_update(1, 2, 1),
            test_update(2, 1, 1),
            test_update(2, 3, 1),
            test_update(3, 4, 1),
          ],
        ],
      ],
    ),
    (
      "mixed insertion and deletion",
      [
        [[test_update(1, 2, 1), test_update(2, 3, 1)]],
        [[test_update(2, 3, -1), test_update(2, 4, 1)]],
      ],
    ),
  ]
  for worker_count in [1, 2, 4] {
    for case in cases {
      let (_, epochs) = case
      let engine = Engine(worker_count)
      let oracle = Oracle()
      for epoch, batches in epochs {
        ignore(test_assert_matches_oracle(engine, oracle, epoch, batches))
      }
    }
  }
}

///|
test "cycles have finite set output" {
  let engine = Engine(4, scheduler_seed=11)
  let publication = test_unwrap_publication(
    test_stage_batches(engine, 0, [
      [test_update(1, 2, 1), test_update(2, 3, 1), test_update(3, 1, 1)],
    ]),
  )
  guard publication.reachable ==
    test_reaches([
      (1, 1),
      (1, 2),
      (1, 3),
      (2, 1),
      (2, 2),
      (2, 3),
      (3, 1),
      (3, 2),
      (3, 3),
    ]) else {
    fail("cycle output was not the finite set closure")
  }
}

///|
fn test_engine_with_seed(worker_count : Int, seed : Int?) -> Engine {
  match seed {
    None => Engine(worker_count)
    Some(value) => Engine(worker_count, scheduler_seed=value)
  }
}

///|
test "worker count delivery seed and batch split preserve canonical output" {
  let split = [
    [test_update(0, 1, 1)],
    [test_update(1, 2, 1), test_update(2, 0, 1)],
    [test_update(2, 3, 1)],
  ]
  let reversed = [
    [
      test_update(2, 3, 1),
      test_update(2, 0, 1),
      test_update(1, 2, 1),
      test_update(0, 1, 1),
    ],
  ]
  let mut baseline : Publication? = None
  for worker_count in [1, 2, 4] {
    for seed in [None, Some(3), Some(99)] {
      let first = test_unwrap_publication(
        test_stage_batches(test_engine_with_seed(worker_count, seed), 0, split),
      )
      let second = test_unwrap_publication(
        test_stage_batches(
          test_engine_with_seed(worker_count, seed),
          0,
          reversed,
        ),
      )
      guard first == second else {
        fail("batch split or permutation changed canonical output")
      }
      match baseline {
        None => baseline = Some(first)
        Some(expected) => {
          let equal = first == expected
          guard equal else {
            fail("worker count or delivery seed changed canonical output")
          }
        }
      }
    }
  }
}

///|
test "same scheduler seed replays an equal canonical decision trace" {
  let batches = [
    [
      test_update(0, 1, 1),
      test_update(1, 2, 1),
      test_update(2, 0, 1),
      test_update(2, 3, 1),
    ],
  ]
  let first = Engine(4, scheduler_seed=123)
  let second = Engine(4, scheduler_seed=123)
  let first_output = test_stage_batches(first, 0, batches)
  let second_output = test_stage_batches(second, 0, batches)
  guard first_output == second_output &&
    first.trace_snapshot() == second.trace_snapshot() else {
    fail("same-seed replay changed decisions or output")
  }
}

///|
test "shutdown rejects new work and discards outstanding mail" {
  let engine = Engine(1)
  guard engine.begin_epoch(0) == Ok(()) else { fail("epoch did not open") }
  engine.shutdown()
  guard engine.stage_batch(0, []) == Err(EngineStopped) &&
    engine.begin_epoch(0) == Err(EngineStopped) &&
    engine.is_quiescent() else {
    fail("shutdown policy did not reject and discard")
  }
}
