# Incr Query Nodeflow boundary benchmarks

**Date:** 2026-08-29

**Reader:** maintainers deciding whether the Issue #496 Nodeflow evidence can become an optional production layer.

**Decision:** retain the operation-based boundary and do not optimize broad snapshots yet. At 10,000 nodes, deliberate edits and snapshots remain below 9 ms on the JS deployment target. Do not claim support for unconstrained dependency depth: a 10,000-node linear Formula chain overflows the JS and wasm-gc stacks and requires a separate Incr Query evaluation investigation or an explicit, typed product limit.

**Keep until:** a newer Nodeflow benchmark supersedes these measurements or the spike is deleted.

**Disposition:** permanent dated measurement snapshot; benchmark source remains a regression and attribution probe.

**Cold-depth correction:** the timing rows below describe the warmed `@bench.T` process, not a production-safe dependency-depth envelope. A direct cold release test passes depth 500 and fails 600 on JavaScript, passes 600 and fails 700 on wasm-gc, and passes at least 10,000 on native. The [production-readiness investigation](../research/2026-08-29-nodeflow-production-readiness-options.md) supersedes this snapshot's earlier depth interpretation; its direct file-path command is the acceptance probe.

## Question

What does the public Nodeflow operation boundary cost at 100, 1,000, and 10,000 nodes, and does dependency depth expose a different limit from graph width?

## Benchmark seam

[`performance_bench_wbtest.mbt`](../../examples/spikes/incr_query_nodeflow_kernel/nodeflow/performance_bench_wbtest.mbt) uses white-box access only to construct one document directly instead of issuing a sequence of public `AddNode` operations. Document restoration and its current provider-validation scans happen before timing; this snapshot makes no fixture-setup or restoration-complexity claim. Every timed operation uses the public aggregate boundary.

| Scenario | Timed public operation | State varied per iteration |
|---|---|---|
| Structural snapshot | `Nodeflow::snapshot(empty demand)` | none; returned snapshot retained |
| Atomic rebind | `Nodeflow::apply(BindingChangeSet, empty demand)` | provider alternates between two Outputs |
| Demanded recomputation | `Nodeflow::apply(SetParameter, tail demand)` | source value increments |

The first two scenarios contain independent Number nodes plus the minimum rebind target. The 100- and 1,000-node recomputation rows use a linear active chain. The 10,000-node recomputation row has 10,000 total nodes but active depth 100; the remainder are unrelated Numbers. `apply` intentionally includes the contractually required structural Surface Snapshot.

## Environment

- MoonBit `0.1.20260819`, moonc `v0.10.9+6e6c44045`
- Node.js `v24.14.1`
- Linux x86_64 under WSL2
- 10 benchmark samples, release builds

## Results

| Scenario | Nodes / active depth | wasm-gc | JavaScript | native |
|---|---:|---:|---:|---:|
| Structural snapshot | 100 | 137.71 µs | 63.87 µs | 46.63 µs |
| Structural snapshot | 1,000 | 1.33 ms | 646.31 µs | 491.05 µs |
| Structural snapshot | 10,000 | 13.42 ms | 8.11 ms | 5.57 ms |
| Atomic rebind + snapshot | 100 | 146.41 µs | 65.88 µs | 49.66 µs |
| Atomic rebind + snapshot | 1,000 | 1.41 ms | 642.22 µs | 528.96 µs |
| Atomic rebind + snapshot | 10,000 | 14.12 ms | 8.16 ms | 6.54 ms |
| Source edit + demanded tail | 100 / 100 | 380.50 µs | 151.39 µs | 158.89 µs |
| Source edit + demanded tail | 1,000 / 1,000 | 3.84 ms | 1.65 ms | 1.81 ms |
| Source edit + demanded tail | 10,000 / 100 | 14.35 ms | 8.47 ms | 6.25 ms |

## Deep-chain probe

The initial matrix also ran a 10,000-node linear active chain.

| Target | Result |
|---|---|
| wasm-gc | `RangeError: Maximum call stack size exceeded` |
| JavaScript | `RangeError: Maximum call stack size exceeded` in recursive `QueryContext::get` evaluation |
| native | 35.10 ms ± 1.92 ms |

The 1,000-node chain succeeds on every target. This separates two concerns: width causes approximately linear snapshot work, while extreme depth reaches the web backends' recursive evaluation limit.

## Interpretation

- **No broad-snapshot optimization is justified yet.** The JS deployment target stays below 9 ms for all measured 10,000-node deliberate operations. This is not evidence for running full snapshots on pointer-move frames.
- **Structural projection dominates wide operations.** Rebinding adds little over an empty-demand snapshot at the same size because `apply` must return a complete Surface Snapshot.
- **Dependency depth is the blocker.** The failure occurs below Nodeflow's projection layer in recursive Incr Query evaluation. Caching, a Nodeflow scheduler, or a second semantic graph would not address it.
- **Restoration performance is unmeasured.** Fixture restoration is excluded from every row, and current semantic validation may scan document nodes per binding. Optimize it only after a dedicated restoration benchmark confirms it matters.
- **Production claim is bounded.** The optional layer is adoptable for the measured envelope, but arbitrary-depth publication is not production-ready until a separate kernel investigation proves iterative evaluation or the product chooses an explicit typed limit.

## Reproduce

```bash
NEW_MOON_MOD=0 moon bench --release \
  -p dowdiness/incr_query_nodeflow_kernel/nodeflow \
  -f performance_bench_wbtest.mbt

NEW_MOON_MOD=0 moon bench --release --target js \
  -p dowdiness/incr_query_nodeflow_kernel/nodeflow \
  -f performance_bench_wbtest.mbt

NEW_MOON_MOD=0 moon bench --release --target native \
  -p dowdiness/incr_query_nodeflow_kernel/nodeflow \
  -f performance_bench_wbtest.mbt
```
