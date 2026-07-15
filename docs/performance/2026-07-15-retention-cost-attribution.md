# Retention Cost Attribution

**Captured:** 2026-07-15  
**Issue:** [#399](https://github.com/dowdiness/incr/issues/399)  
**Cross-target baseline commit:** `0557674`  
**Control benchmark commit:** `d0cd538`  
**Toolchain:** moon 0.1.20260703, moonc v0.10.3+16975d007  
**Hardware:** AMD Ryzen 7 6800H, Linux 6.6.114.1-microsoft-standard-WSL2,
8 vCPUs  
**Targets:** wasm-gc (`moon bench` default) and native  
**Samples:** three complete runs per target; each reported benchmark mean uses
10 rounds with adaptive inner-run counts

This note follows up the unexplained residual in scenarios 7a and 7b of the
[2026-07-14 retention baseline](2026-07-14-retention-baseline.md). It answers
three questions:

1. Does the residual reproduce outside wasm-gc?
2. Which storage remains after disposal or runtime GC?
3. Does that retained storage make a push-free update slower by itself?

## Cross-target reproduction

Times below are microseconds per update. `Mean` is the mean of the three
complete-run means; `run range` is the minimum and maximum of those means.
The ratio compares N=10,000 with N=1,000.

| Target | Scenario | N=1,000 mean (run range) | N=10,000 mean (run range) | N ratio |
|---|---|---:|---:|---:|
| wasm-gc | 7a disposed pull + one live eager | 1.497 (1.48–1.53) | 8.327 (8.31–8.34) | 5.56× |
| wasm-gc | 7b GC pull + one watched eager | 1.520 (1.51–1.53) | 9.337 (9.29–9.36) | 6.14× |
| native | 7a disposed pull + one live eager | 1.673 (1.66–1.69) | 9.640 (9.57–9.76) | 5.76× |
| native | 7b GC pull + one watched eager | 1.727 (1.69–1.76) | 9.707 (9.62–9.77) | 5.62× |

Native reproduces both the magnitude and the N-dependent shape. MoonBit's
native/C backend uses reference counting, while wasm-gc uses the host garbage
collector. The residual is therefore not specific to wasm-gc root scanning.
See MoonBit's
[backend memory-management documentation](https://github.com/moonbitlang/moonbit-docs/blob/main/next/tutorial/for-go-programmers/index.md#memory-management).

Scenario 8a also reproduces on both targets. These results are included to
separate the 7a/7b cleanup residual from the known live root-fanout traversal.
Times are again microseconds per update.

| Target | Chain depth | N=1,000 mean (run range) | N=10,000 mean (run range) | N ratio |
|---|---:|---:|---:|---:|
| wasm-gc | 1 | 20.227 (19.78–20.60) | 646.327 (511.22–775.77) | 31.95× |
| wasm-gc | 4 | 30.517 (27.93–32.17) | 2,306.667 (1,930–2,520) | 75.59× |
| native | 1 | 15.570 (14.72–16.19) | 598.697 (497.59–749.08) | 38.45× |
| native | 4 | 23.757 (22.34–26.00) | 946.470 (908.58–972.21) | 39.84× |

Unlike 7a/7b, 8a intentionally keeps N direct root subscribers. Its growth is
consistent with live graph work plus target-dependent retained-memory effects;
it is not evidence that cleanup leaves N stale root edges.

## Post-cleanup storage facts

`incr/cells/retention_bench_fixture_wbtest.mbt` now pins the same facts for
both explicit disposal and `Runtime::gc()`. After constructing N primed pull
cells and retaining one eager consumer:

| State | Value after cleanup |
|---|---:|
| `rt.dependents(root.id()).length()` | 1 |
| remaining root subscriber | the live eager cell |
| `rt.core.cell_index.length()` | N + 2 |
| `rt.core.cell_ops.length()` | N + 2 |
| `rt.cell_lifecycle.length()` | N + 2 |
| `rt.pull.memos.length()` | N |
| `rt.pull.free_memos.length()` | N |
| `rt.push.node_count` | 1 |

Cleanup therefore removes every stale root edge and makes every pull slot
reusable, but it does not compact cumulative `CellId` dispatch/lifecycle arrays
or the pull-slot backing array. The tests first failed under deliberate
one-off mutations of `free_memos` and `cell_ops`, confirming that the
assertions detect plausible drift.

## Push-free controls

Scenarios 7e and 7f preserve the setup and cleanup shapes of 7a and 7b but do
not create the final live eager consumer. The timed body performs only
`root.set(value)`. Times are nanoseconds per update.

| Target | Scenario | N=1,000 mean (run range) | N=10,000 mean (run range) | N ratio |
|---|---|---:|---:|---:|
| wasm-gc | 7e disposed pull, no push | 71.99 (71.07–72.76) | 71.82 (69.90–74.00) | 1.00× |
| wasm-gc | 7f GC pull, no push | 71.78 (70.85–72.26) | 71.21 (70.78–71.46) | 0.99× |
| native | 7e disposed pull, no push | 91.27 (90.42–92.20) | 92.67 (90.00–96.80) | 1.02× |
| native | 7f GC pull, no push | 95.20 (91.08–103.16) | 97.46 (95.98–98.45) | 1.02× |

Retained free pull slots and cumulative dispatch arrays do not make the base
input update scale with N. The N-dependent residual appears only when the one
live eager cell activates push propagation.

## Attribution

The engine path is bounded as follows:

- `Input::force_set` passes one changed `CellId` to
  `Runtime::propagate_changes`.
- `kernel/propagate.mbt` advances one revision, stamps that one cell, and
  enters push propagation only when `push.node_count > 0`.
- `enqueue_reachable_push_subscribers` starts from the changed root. After
  cleanup its subscriber set contains only the live eager cell.
- One eager evaluation records one dependency, diffs one old source against
  one new source, and leaves the same edge in place.
- Each push propagation creates a priority queue and BFS worklist; dependency
  tracking creates an `ActiveQuery` with a dependency array and hash set.

No loop in this executed path is indexed by `cell_index.length()`,
`cell_ops.length()`, `cell_lifecycle.length()`, `pull.memos.length()`, or
`free_memos.length()`. The white-box counts and flat 7e/7f controls independently
exclude a stale-edge scan and a per-update cumulative-slot scan.

**Bounded observation:** the per-update engine work after cleanup is a
fixed-count eager push-evaluation path. The N-dependent cost appears only when
that path runs in a runtime with retained pull storage, and it appears on both
targets.

**Attribution result:** unresolved mixture. Temporary allocation/lifetime
behavior, cache locality, native reference-count traffic, and wasm-gc
collection frequency remain candidate contributors; the controls do not choose
between them. No native sampling or callgraph profiler (`perf`, `samply`, or
Valgrind) was available on the host. No named engine operation has been shown
to scale with retained slot count, so the evidence does not justify an engine
change.

## Slot-reclamation decision

**Decision: no-go for slot reclamation or compaction under #399.**

The pull slots are already reusable (`free_memos.length() == N`), the cumulative
arrays are not scanned by the timed path, and a push-free update stays flat at
N=10,000. Compacting slots might change allocator or locality behavior, but
this investigation has not established a causal or measurable reduction path.
Implementing compaction now would add identity-remapping and lifecycle risk
without a pinned engine bottleneck.

Reopen an engine optimization only when all three conditions hold:

1. a production-shaped workload reproduces a material user-visible cost;
2. a profiler identifies a named operation whose work scales with retained
   storage; and
3. an isolated reclamation or allocation-reuse prototype reduces that
   operation without changing `CellId`, dependency, disposal, or GC semantics.

Until then, keep 7a/7b as regression probes and 7e/7f as the negative controls.

## Commands

```bash
moon bench --release -p dowdiness/incr/tests -f retention_bench_test.mbt
moon bench --release --target native -p dowdiness/incr/tests -f retention_bench_test.mbt
moon bench --release -p dowdiness/incr/tests -f retention_bench_test.mbt -i 20-24
moon bench --release --target native -p dowdiness/incr/tests -f retention_bench_test.mbt -i 20-24
moon test incr/cells/retention_bench_fixture_wbtest.mbt
```
