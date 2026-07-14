# Retention Benchmark Baseline

**Captured:** 2026-07-14  
**Commit:** 6d82aa8  
**Toolchain:** moon 0.1.20260703, moonc v0.10.3+16975d007  
**Target:** wasm-gc (`moon bench` default)  
**Hardware:** AMD Ryzen 7 6800H, Linux 6.6.114.1-microsoft-standard-WSL2, 8 vCPUs  
**Command:** `moon bench --release -p dowdiness/incr/tests -f retention_bench_test.mbt`  
**Samples:** 10 rounds with adaptive inner-run counts  
**Exit:** 0; 28 benchmarks passed

This snapshot measures the steady update cost of lifecycle orphaning: cells
that remain in the runtime after their user-visible handles are dropped. Each
fixture is fully constructed and primed before the timed body. The timed body
allocates no reactive cells. Counts are assertions over
`rt.dependents(root.id()).length()` and therefore remain useful even when
wall-clock results drift.

## Results

Times are mean nanoseconds per update. For fan-in, the count is per root and
all 12 roots have the same count.

| Scenario | N | Variant | ns/update | Root dependents | Prediction confirmed? |
|---|---:|---|---:|---:|:---:|
| 1 `uncomputed_pull_fanout` | 1,000 | — | 73.14 | 0 | yes |
| 1 `uncomputed_pull_fanout` | 10,000 | — | 72.22 | 0 | yes |
| 2 `primed_pull_fanout_no_push` | 1,000 | — | 72.35 | 1,000 | yes |
| 2 `primed_pull_fanout_no_push` | 10,000 | — | 85.87 | 10,000 | yes |
| 3 `primed_pull_fanout_distant_push` | 1,000 | — | 95.80 | 1,000 | yes |
| 3 `primed_pull_fanout_distant_push` | 10,000 | — | 90.86 | 10,000 | yes |
| 4 `primed_pull_fanout_same_root_live_push` | 1,000 | — | 24,260 | 1,001 | yes |
| 4 `primed_pull_fanout_same_root_live_push` | 10,000 | — | 757,530 | 10,001 | yes |
| 5 `dynamic_subgraph_churn_same_root` | 1,000 | — | 20,360 | 1,001 | yes |
| 5 `dynamic_subgraph_churn_same_root` | 10,000 | — | 638,320 | 10,001 | yes |
| 6 `abandoned_eager_fanout` | 1,000 | — | 274,870 | 1,000 | yes |
| 6 `abandoned_eager_fanout` | 10,000 | — | 6,560,000 | 10,000 | yes |
| 7a `scan_disposed_control` | 1,000 | — | 1,530 | 1 | no |
| 7a `scan_disposed_control` | 10,000 | — | 8,980 | 1 | no |
| 7b `scan_gc_control` | 1,000 | — | 1,500 | 1 | no |
| 7b `scan_gc_control` | 10,000 | — | 10,060 | 1 | no |
| 7c `eager_disposed_control` | 1,000 | — | 75.59 | 0 | yes |
| 7c `eager_disposed_control` | 10,000 | — | 75.99 | 0 | yes |
| 7d `eager_gc_control` | 1,000 | — | 76.10 | 0 | yes |
| 7d `eager_gc_control` | 10,000 | — | 70.65 | 0 | yes |
| 8a `chain_depth` | 1,000 | depth 1 | 24,390 | 1,001 | no |
| 8a `chain_depth` | 10,000 | depth 1 | 1,130,000 | 10,001 | no |
| 8a `chain_depth` | 1,000 | depth 4 | 33,410 | 1,001 | no |
| 8a `chain_depth` | 10,000 | depth 4 | 2,400,000 | 10,001 | no |
| 8b `fan_in` | 1,000 | set one root | 1,150,000 | 1,000/root | yes |
| 8b `fan_in` | 10,000 | set one root | 19,110,000 | 10,000/root | yes |
| 8b `fan_in` | 1,000 | batch all 12 roots | 1,320,000 | 1,000/root | yes |
| 8b `fan_in` | 10,000 | batch all 12 roots | 27,560,000 | 10,000/root | yes |

## Findings

The push gate is the discontinuity. Scenarios 2 and 3 retain up to 10,000
direct pull subscribers yet remain around 72–96 ns/update while that root has
no reachable push consumer. Adding one same-root push path changes the same
retention shape to 24.26 µs at 1,000 and 757.53 µs at 10,000. Dynamic churn
reproduces the same class of growth without allocating during measurement.

Abandoned eager cells are more expensive because every retained eager cell is
recomputed, not merely scanned: 274.87 µs at 1,000 and 6.56 ms at 10,000.
Explicit disposal and GC both restore the eager control to the clean-input
range of roughly 71–76 ns.

The known-positive controls fired. At N=10,000, scenario 7a is about 84× and
7b about 75× cheaper than scenario 4; scenarios 7c and 7d are more than
86,000× cheaper than scenario 6.

## Prediction contradictions

Scenarios 7a and 7b are not fully flat. Their subscriber count is fixed at one
after disposal/GC, but cost rises from about 1.5 µs at N=1,000 to 9–10 µs at
N=10,000. The stale subscriber scan is gone, as the positive-control ratio
shows, but retained/disposed pull-cell volume still affects the live eager
update path. This snapshot does not distinguish global SoA work from
heap/collector effects.

Scenario 8a is not depth-neutral in wall time despite equal asserted root
fanout. Depth 4 is 1.37× depth 1 at N=1,000 and 2.12× at N=10,000. The root BFS
can prune every stale chain at its first pull node, so this result indicates a
cost correlated with total retained nodes rather than traversed dependency
depth; a target-specific memory/GC probe would be needed to assign the cause.

Scenarios 4–6 and 8b grow faster than the ideal 10× expected from a tenfold N
increase. This does not contradict their predicted O(N) graph work, but it
does show that constants are not stable at 10,000 retained cells on this
wasm-gc host. Treat the measured values, not a per-cell extrapolation from
N=1,000, as the current baseline.

## Decision impact

Track 1 confirms that lifecycle orphaning is cheap only while the source-local
push gate stays closed. A same-root push consumer exposes retained pull edges,
and abandoned eager cells pay full recomputation. The results justify keeping
the benchmark as a regression probe, but they do not by themselves authorize
the detachable-scope or keyed-facade follow-up tracks; those retain the
separate evidence and value gates in the plan.
