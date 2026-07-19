///|
struct GeneratedRun {
  outcomes : Array[Result[Publication, ProtocolError]]
  trace : Array[TraceEvent]
  valid : Bool
}

///|
fn generated_node(value : Int) -> Int {
  let remainder = value % 5
  if remainder < 0 {
    remainder + 5
  } else {
    remainder
  }
}

///|
fn generated_diff(value : Int) -> Int {
  match generated_node(value) {
    0 => 1
    1 => -1
    2 => 2
    3 => -2
    _ => 1
  }
}

///|
fn generated_trace(values : ArrayView[Int]) -> Array[Array[SourceUpdate]] {
  let epochs : Array[Array[SourceUpdate]] = []
  for epoch in 0..<5 {
    let updates : Array[SourceUpdate] = []
    if epoch == 0 {
      updates.push(test_update(0, 1, 1))
      updates.push(test_update(1, 0, 1))
      updates.push(test_update(0, 1, 1))
    }
    for offset in 0..<5 {
      let base = (epoch * 7 + offset * 3) % values.length()
      let from = generated_node(values[base])
      let to = generated_node(values[(base + 1) % values.length()])
      let diff = if epoch == 0 {
        1
      } else {
        generated_diff(values[(base + 2) % values.length()])
      }
      updates.push(test_update(from, to, diff))
    }
    epochs.push(updates)
  }
  epochs
}

///|
fn generated_batches(
  updates : Array[SourceUpdate],
  mode : Int,
  choices : ArrayView[Int],
) -> Array[Array[SourceUpdate]] {
  match mode {
    0 => [updates.copy()]
    1 => updates.map(update => [update])
    2 => {
      let batches : Array[Array[SourceUpdate]] = []
      let mut cursor = 0
      let mut choice = 0
      while cursor < updates.length() {
        let width = generated_node(choices[choice % choices.length()]) % 3 + 1
        let end = @cmp.minimum(cursor + width, updates.length())
        batches.push(updates[cursor:end].to_owned())
        cursor = end
        choice = choice + 1
      }
      batches
    }
    _ => [updates.rev()]
  }
}

///|
fn run_generated_trace(
  worker_count : Int,
  scheduler_seed : Int?,
  batch_mode : Int,
  values : Array[Int],
) -> GeneratedRun {
  let engine = test_engine_with_seed(worker_count, scheduler_seed)
  let oracle = Oracle()
  let outcomes : Array[Result[Publication, ProtocolError]] = []
  let mut valid = true
  let epochs = generated_trace(values)
  for epoch, updates in epochs {
    let batches = generated_batches(updates, batch_mode, values)
    let source_before = engine.source_snapshot()
    let reachable_before = engine.reachable_snapshot()
    let publication_count_before = engine.publication_count()
    let actual = test_stage_batches(engine, epoch, batches)
    let expected = oracle.apply(epoch, updates)
    if actual != expected {
      valid = false
    }
    match actual {
      Ok(publication) =>
        if publication.epoch != Epoch(epoch) ||
          publication.source.any(weighted => weighted.weight <= 0) ||
          !engine.is_quiescent() ||
          !engine.workers_closed(Epoch(epoch)) {
          valid = false
        }
      Err(InvalidSourceMultiplicity(_, _)) =>
        if engine.source_snapshot() != source_before ||
          engine.reachable_snapshot() != reachable_before ||
          engine.publication_count() != publication_count_before {
          valid = false
        }
      Err(_) => valid = false
    }
    outcomes.push(actual)
  }
  { outcomes, trace: engine.trace_snapshot(), valid }
}

///|
fn generated_trace_property(values : Array[Int]) -> Bool {
  let scheduler_seed = values.fold(init=17, (seed, value) => {
    (seed * 31 + value) % 100000
  })
  let baseline = run_generated_trace(1, None, 0, values)
  let split = run_generated_trace(1, None, 2, values)
  let reversed = run_generated_trace(2, Some(scheduler_seed), 3, values)
  let randomized = run_generated_trace(4, Some(scheduler_seed), 2, values)
  let replay = run_generated_trace(4, Some(scheduler_seed), 2, values)
  baseline.valid &&
  split.valid &&
  reversed.valid &&
  randomized.valid &&
  replay.valid &&
  baseline.outcomes == split.outcomes &&
  baseline.outcomes == reversed.outcomes &&
  baseline.outcomes == randomized.outcomes &&
  randomized.outcomes == replay.outcomes &&
  randomized.trace == replay.trace
}

///|
test "generated bounded epoch traces match oracle at N=1/2/4" {
  let values = @gen.int_range(-32, 33).array_with_size(40)
  let property = @qc.forall(values, generated_trace_property)
  @qc.quick_check(property, max_success=40, max_size=40)
}

///|
test "generated trace distribution covers cycles duplicates signs and rejections" {
  let generator = @gen.int_range(-32, 33).array_with_size(40)
  let samples = generator.samples(size=64, seed=20260719UL)
  let mut saw_negative = false
  let mut saw_positive = false
  let mut saw_self_edge = false
  let mut saw_rejection = false
  for values in samples {
    let epochs = generated_trace(values)
    for updates in epochs {
      if updates.any(update => update.diff < 0) {
        saw_negative = true
      }
      if updates.any(update => update.diff > 0) {
        saw_positive = true
      }
      if updates.any(update => update.edge.from == update.edge.to) {
        saw_self_edge = true
      }
    }
    let run = run_generated_trace(1, None, 2, values)
    if run.outcomes.any(outcome => {
        outcome is Err(InvalidSourceMultiplicity(_, _))
      }) {
      saw_rejection = true
    }
  }
  guard saw_negative && saw_positive && saw_self_edge && saw_rejection else {
    fail("generated traces missed a required semantic class")
  }
  let forced = generated_trace(Array::make(40, 0))[0]
  guard forced.count(test_update(0, 1, 1)) >= 2 &&
    forced.contains(test_update(1, 0, 1)) else {
    fail("generated traces lost forced duplicate/cycle coverage")
  }
}
