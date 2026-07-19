///|
/// Exhaustive tiny-state tests enumerate bounded graph domains directly so
/// deterministic evidence complements, rather than samples from, generated
/// traces.

///|
/// A positional divisor makes the radix encoding explicit for each canonical
/// directed edge.
priv struct ExhaustiveEncodedEdge {
  edge : Edge
  divisor : Int
} derive(Eq, Debug)

///|
/// Matrix A uses row-major two-node edges with ternary source multiplicities.
fn exhaustive_matrix_a_edges() -> Array[ExhaustiveEncodedEdge] {
  [
    { edge: { from: 0, to: 0 }, divisor: 1 },
    { edge: { from: 0, to: 1 }, divisor: 3 },
    { edge: { from: 1, to: 0 }, divisor: 9 },
    { edge: { from: 1, to: 1 }, divisor: 27 },
  ]
}

///|
/// Matrix B uses row-major three-node edges with Boolean source presence.
fn exhaustive_matrix_b_edges() -> Array[ExhaustiveEncodedEdge] {
  [
    { edge: { from: 0, to: 0 }, divisor: 1 },
    { edge: { from: 0, to: 1 }, divisor: 2 },
    { edge: { from: 0, to: 2 }, divisor: 4 },
    { edge: { from: 1, to: 0 }, divisor: 8 },
    { edge: { from: 1, to: 1 }, divisor: 16 },
    { edge: { from: 1, to: 2 }, divisor: 32 },
    { edge: { from: 2, to: 0 }, divisor: 64 },
    { edge: { from: 2, to: 1 }, divisor: 128 },
    { edge: { from: 2, to: 2 }, divisor: 256 },
  ]
}

///|
/// Positive digits become signed source admissions while zero digits remain
/// absent, preserving canonical descriptor order without a mutable builder.
fn exhaustive_encoded_updates(
  graph_code : Int,
  radix : Int,
  edges : ArrayView[ExhaustiveEncodedEdge],
) -> Array[SourceUpdate] {
  edges.filter_map(encoded => {
    let weight = graph_code / encoded.divisor % radix
    if weight > 0 {
      Some(test_update(encoded.edge.from, encoded.edge.to, weight))
    } else {
      None
    }
  })
}

///|
/// Batching modes pin the three representative shell layouts independently of
/// logical source contents.
priv enum ExhaustiveBatching {
  CanonicalBatch
  PerUpdateBatch
  ReversedBatch
} derive(Eq, Debug)

///|
/// A configuration couples worker cardinality, deterministic scheduling, and
/// epoch-zero batching so each semantic case exercises one exact shell shape.
priv struct ExhaustiveConfiguration {
  worker_count : Int
  scheduler_seed : Int?
  batching : ExhaustiveBatching
  label : String
} derive(Eq, Debug)

///|
/// The bounded matrix keeps the prescribed N=1/2/4 configurations in stable
/// order for deterministic failure localization.
fn exhaustive_configurations() -> Array[ExhaustiveConfiguration] {
  [
    {
      worker_count: 1,
      scheduler_seed: None,
      batching: CanonicalBatch,
      label: "canonical",
    },
    {
      worker_count: 2,
      scheduler_seed: Some(7),
      batching: PerUpdateBatch,
      label: "per-update",
    },
    {
      worker_count: 4,
      scheduler_seed: Some(11),
      batching: ReversedBatch,
      label: "reversed",
    },
  ]
}

///|
/// Empty sources retain each mode's exact layout while every non-empty source
/// changes only shell batching or order, never logical oracle input.
fn exhaustive_batches(
  updates : Array[SourceUpdate],
  batching : ExhaustiveBatching,
) -> Array[Array[SourceUpdate]] {
  match batching {
    CanonicalBatch => [updates.copy()]
    PerUpdateBatch => updates.map(update => [update])
    ReversedBatch => [updates.rev()]
  }
}

///|
/// Canonical worker snapshots own sorted copies of mutable arrangements and
/// reachability so rejection checks cannot observe hash traversal or aliasing.
priv struct ExhaustiveWorkerSnapshot {
  worker : WorkerId
  edges : Array[WeightedEdge]
  reachable : Array[Reach]
  closed_epoch : Epoch?
} derive(Eq, Debug)

///|
/// Local mutation is confined to owned snapshot builders because nested worker
/// maps and sets are unordered and cannot be compared directly.
fn exhaustive_worker_snapshots(
  engine : Engine,
) -> Array[ExhaustiveWorkerSnapshot] {
  engine.workers.map(worker => {
    let edges : Array[WeightedEdge] = []
    worker.edge_by_from.each((from, by_target) => {
      by_target.each((to, weight) => {
        edges.push({ edge: { from, to }, weight: weight.0 })
      })
    })
    edges.sort()
    let reachable : Array[Reach] = []
    worker.reachable.each(reach => reachable.push(reach))
    reachable.sort()
    { worker: worker.id, edges, reachable, closed_epoch: worker.closed_epoch }
  })
}

///|
/// Equality failures print the mismatched snapshots and invariant name only on
/// the first failing scenario, keeping successful exhaustive runs silent.
fn[T : Eq + Debug] exhaustive_assert_equal(
  expected : T,
  actual : T,
  invariant : String,
  case_label : String,
) -> Unit raise {
  guard actual == expected else {
    debug_inspect(expected)
    debug_inspect(actual)
    fail("matrix A rejection changed \{invariant}: \{case_label}")
  }
}

///|
/// One comparison preserves structured rejection results while printing only
/// the first bounded case whose engine and independent oracle outcomes differ.
fn exhaustive_compare_epoch(
  engine : Engine,
  oracle : Oracle,
  epoch : Int,
  batches : Array[Array[SourceUpdate]],
  case_label : String,
) -> Result[Publication, ProtocolError] raise {
  let expected = oracle.apply(epoch, test_flatten_batches(batches))
  let actual = test_stage_batches(engine, epoch, batches)
  guard actual == expected else {
    debug_inspect(expected)
    debug_inspect(actual)
    fail("engine/oracle mismatch: \{case_label}; epoch=\{epoch}")
  }
  actual
}

///|
test "exhaustive two-node weighted transitions match oracle and preserve rejection atomicity" {
  let edges = exhaustive_matrix_a_edges()
  guard exhaustive_encoded_updates(0, 3, edges).is_empty() &&
    exhaustive_encoded_updates(80, 3, edges) ==
    [
      test_update(0, 0, 2),
      test_update(0, 1, 2),
      test_update(1, 0, 2),
      test_update(1, 1, 2),
    ] &&
    exhaustive_encoded_updates(1, 3, edges) == [test_update(0, 0, 1)] &&
    exhaustive_encoded_updates(3, 3, edges) == [test_update(0, 1, 1)] &&
    exhaustive_encoded_updates(9, 3, edges) == [test_update(1, 0, 1)] &&
    exhaustive_encoded_updates(27, 3, edges) == [test_update(1, 1, 1)] else {
    fail("matrix A radix encoding is invalid")
  }
  let configurations = exhaustive_configurations()
  let mut scenario_count = 0
  for graph_code in 0..<81 {
    let initial_updates = exhaustive_encoded_updates(graph_code, 3, edges)
    for encoded_edge in edges {
      for diff in [-2, -1, 1, 2] {
        for configuration in configurations {
          let case_label = "matrix=A; graph_code=\{graph_code}; N=\{configuration.worker_count}; batch=\{configuration.label}; edge_from=\{encoded_edge.edge.from}; edge_to=\{encoded_edge.edge.to}; diff=\{diff}"
          let engine = test_engine_with_seed(
            configuration.worker_count,
            configuration.scheduler_seed,
          )
          let oracle = Oracle()
          let initial = exhaustive_compare_epoch(
            engine,
            oracle,
            0,
            exhaustive_batches(initial_updates, configuration.batching),
            case_label,
          )
          guard initial is Ok(_) else {
            fail("matrix A initial epoch was rejected: \{case_label}")
          }
          let source_before = engine.source_snapshot()
          let reachable_before = engine.reachable_snapshot()
          let workers_before = exhaustive_worker_snapshots(engine)
          let publication_before = engine.last_publication_snapshot()
          let publication_count_before = engine.publication_count()
          let transition = exhaustive_compare_epoch(
            engine,
            oracle,
            1,
            exhaustive_batches(
              [test_update(encoded_edge.edge.from, encoded_edge.edge.to, diff)],
              configuration.batching,
            ),
            case_label,
          )
          match transition {
            Ok(_) => {
              guard engine.is_quiescent() && engine.workers_closed(Epoch(1)) else {
                fail("matrix A accepted epoch was incomplete: \{case_label}")
              }
            }
            Err(InvalidSourceMultiplicity(_, _)) => {
              exhaustive_assert_equal(
                source_before,
                engine.source_snapshot(),
                "source snapshot",
                case_label,
              )
              exhaustive_assert_equal(
                reachable_before,
                engine.reachable_snapshot(),
                "reachability snapshot",
                case_label,
              )
              exhaustive_assert_equal(
                workers_before,
                exhaustive_worker_snapshots(engine),
                "worker snapshots",
                case_label,
              )
              exhaustive_assert_equal(
                publication_before,
                engine.last_publication_snapshot(),
                "latest publication",
                case_label,
              )
              exhaustive_assert_equal(
                publication_count_before,
                engine.publication_count(),
                "publication count",
                case_label,
              )
              exhaustive_assert_equal(
                true,
                engine.is_quiescent(),
                "queue quiescence",
                case_label,
              )
              guard engine.phase is Ready(2) else {
                fail(
                  "matrix A rejection did not advance to Ready(2): \{case_label}",
                )
              }
              let recovered = exhaustive_compare_epoch(
                engine,
                oracle,
                2,
                exhaustive_batches([], configuration.batching),
                case_label,
              )
              guard recovered is Ok(_) else {
                fail("matrix A rejection did not recover: \{case_label}")
              }
            }
            Err(_) =>
              fail("matrix A produced an unexpected error: \{case_label}")
          }
          scenario_count = scenario_count + 1
        }
      }
    }
  }
  guard scenario_count == 3888 else {
    fail("matrix A scenario count changed: \{scenario_count}")
  }
}

///|
test "exhaustive three-node boolean closures match oracle at N=1/2/4" {
  let edges = exhaustive_matrix_b_edges()
  guard exhaustive_encoded_updates(0, 2, edges).is_empty() &&
    exhaustive_encoded_updates(511, 2, edges) ==
    [
      test_update(0, 0, 1),
      test_update(0, 1, 1),
      test_update(0, 2, 1),
      test_update(1, 0, 1),
      test_update(1, 1, 1),
      test_update(1, 2, 1),
      test_update(2, 0, 1),
      test_update(2, 1, 1),
      test_update(2, 2, 1),
    ] &&
    exhaustive_encoded_updates(1, 2, edges) == [test_update(0, 0, 1)] &&
    exhaustive_encoded_updates(256, 2, edges) == [test_update(2, 2, 1)] else {
    fail("matrix B radix encoding is invalid")
  }
  let configurations = exhaustive_configurations()
  let mut scenario_count = 0
  for graph_code in 0..<512 {
    let updates = exhaustive_encoded_updates(graph_code, 2, edges)
    for configuration in configurations {
      let case_label = "matrix=B; graph_code=\{graph_code}; N=\{configuration.worker_count}; batch=\{configuration.label}; edge=encoded-source; diff=n/a"
      let engine = test_engine_with_seed(
        configuration.worker_count,
        configuration.scheduler_seed,
      )
      let oracle = Oracle()
      let actual = exhaustive_compare_epoch(
        engine,
        oracle,
        0,
        exhaustive_batches(updates, configuration.batching),
        case_label,
      )
      guard actual is Ok(_) &&
        engine.is_quiescent() &&
        engine.workers_closed(Epoch(0)) else {
        fail("matrix B epoch did not complete: \{case_label}")
      }
      scenario_count = scenario_count + 1
    }
  }
  guard scenario_count == 1536 else {
    fail("matrix B scenario count changed: \{scenario_count}")
  }
}
