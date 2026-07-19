///|
/// End-to-end closed-epoch benchmarks for the dataflow spike.
/// Measures the fixed 10-edge cyclic workload (8-node ring plus a
/// 2-node tail) at `N=1` and `N=4` virtual workers. Each timed
/// iteration includes engine construction, input staging, close,
/// scheduling, and materialization — an end-to-end measurement,
/// not an isolated operator benchmark.
///
/// Benchmark workload: construct an engine, stage a fixed 10-edge
/// cyclic graph, close, and drain. Returns the reachable count.
fn benchmark_end_to_end_closed_epoch(worker_count : Int) -> Int {
  let engine = Engine(worker_count, scheduler_seed=7)
  let updates = [
    test_update(0, 1, 1),
    test_update(1, 2, 1),
    test_update(2, 3, 1),
    test_update(3, 4, 1),
    test_update(4, 5, 1),
    test_update(5, 6, 1),
    test_update(6, 7, 1),
    test_update(7, 0, 1),
    test_update(2, 8, 1),
    test_update(8, 9, 1),
  ]
  match test_stage_batches(engine, 0, [updates]) {
    Ok(publication) => publication.reachable.length()
    Err(_) => abort("benchmark epoch was rejected")
  }
}

///|
test "dataflow end-to-end closed epoch N=1" (b : @bench.T) {
  ignore(benchmark_end_to_end_closed_epoch(1))
  b.bench(fn() { b.keep(benchmark_end_to_end_closed_epoch(1)) })
}

///|
test "dataflow end-to-end closed epoch N=4 virtual workers" (b : @bench.T) {
  ignore(benchmark_end_to_end_closed_epoch(4))
  b.bench(fn() { b.keep(benchmark_end_to_end_closed_epoch(4)) })
}
