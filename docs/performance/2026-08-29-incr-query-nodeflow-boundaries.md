# Incr Query Nodeflow boundary benchmarks

**Date:** 2026-08-29

**Reader:** maintainers deciding whether the Issue #496 Nodeflow evidence can become an optional production layer.

**Decision:** retain the operation-based boundary and do not optimize broad snapshots yet. At 10,000 nodes, deliberate edits and snapshots remain below 9 ms on the JS deployment target. Use the measured private lazy schema index for restoration validation: it removes per-binding Node scans without changing public or rejection semantics. Do not claim support for unconstrained dependency depth: a 10,000-node linear Formula chain overflows the JS and wasm-gc stacks and requires a separate Incr Query evaluation investigation or an explicit, typed product limit.

**Keep until:** a newer Nodeflow benchmark supersedes these measurements or the spike is deleted.

**Disposition:** permanent dated measurement snapshot; benchmark source remains a regression and attribution probe.

**Cold-depth correction:** the timing rows below describe the warmed `@bench.T` process before Nodeflow configured its Store evaluation limit, not a production-safe dependency-depth envelope. A direct cold release test passes depth 500 and fails 600 on JavaScript, passes 600 and fails 700 on wasm-gc, and passes at least 10,000 on native. The [production-readiness investigation](../research/2026-08-29-nodeflow-production-readiness-options.md) supersedes this snapshot's earlier depth interpretation; its direct file-path command is the acceptance probe. After adopting the 256-active-Query Store policy, the maintained successful N=1,000 benchmark uses active depth 250 and verifies a Current preflight before timing; its first release JS measurement is 861.58 µs ± 11.92 µs.

## Question

What does the public Nodeflow operation boundary cost at 100, 1,000, and 10,000 nodes, and does dependency depth expose a different limit from graph width?

## Benchmark seam

[`performance_bench_wbtest.mbt`](../../examples/spikes/incr_query_nodeflow_kernel/nodeflow/performance_bench_wbtest.mbt) uses white-box access to construct opaque documents directly instead of issuing a sequence of public `AddNode` operations. Fixture construction is always outside timing. The original edit and snapshot rows restore their fixtures before timing and use the public aggregate boundary. The restoration rows separately time private semantic validation or the complete public restore-and-close boundary.

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

## Restoration results

The dedicated 10,000-Node fixtures distinguish independent Nodes, a one-binding linear chain, a late-invalid chain, one-provider high fan-out, and two-bindings-per-Node dense data. The before and after measurements use the same committed fixture and release targets. They are benchmark snapshots rather than absolute CI timing gates.

### Semantic validation

| Shape | wasm-gc before → indexed | JavaScript before → indexed | native before → indexed |
|---|---:|---:|---:|
| Independent | 2.04 ms → 420.34 µs | 3.64 ms → 534.74 µs | 3.79 ms → 555.41 µs |
| Linear | 73.09 ms → 8.55 ms | 110.71 ms → 6.11 ms | 119.68 ms → 5.02 ms |
| Late invalid | 72.56 ms → 8.98 ms | 108.04 ms → 6.39 ms | 121.00 ms → 4.85 ms |
| High fan-out | 72.37 ms → 8.53 ms | 105.30 ms → 5.78 ms | 89.61 ms → 4.60 ms |
| Dense bindings | 143.02 ms → 9.97 ms | 209.80 ms → 6.73 ms | 249.32 ms → 5.13 ms |

The indexed validator builds one live-Node-sized identity Map during the existing uniqueness pass. Each private entry derives and memoizes its schema only when a binding target or provider needs it. Validation still visits Nodes and bindings in document order, so rejection precedence is unchanged. Memory follows live Nodes rather than the persisted identity frontier.

### Full restore and close

| Shape | wasm-gc before → indexed | JavaScript before → indexed | native before → indexed |
|---|---:|---:|---:|
| Independent | 60.11 ms → 68.19 ms | 96.26 ms → 62.51 ms | 40.10 ms → 35.28 ms |
| Dense bindings | 221.99 ms → 131.77 ms | 364.44 ms → 85.85 ms | 482.05 ms → 60.06 ms |

Independent full-restoration samples include substantial allocation and GC variance; the wasm-gc difference is not evidence of a reliable regression. Dense-document improvements are larger than the observed run variance on every target.

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
- **Restoration validation is indexed.** The dedicated fixture reproduced binding-dependent quadratic scans before the change. A private lazy schema index reduces every measured validation shape while preserving original-order rejection checks and sparse identity support.
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
