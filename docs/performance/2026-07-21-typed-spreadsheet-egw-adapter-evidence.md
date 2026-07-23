# Typed spreadsheet EGW adapter evidence — 2026-07-21

**Reader:** Maintainers evaluating Plan 013 and whether EGW changed-property
reporting has an application-independent driver.

**Decision:** The isolated sparse-workload advantage is reproducible, but no
EGW performance conclusion is authorized. The pre-adapter browser baseline
missed advisory budgets on this host, and no second driver confirms the same
container reporting need. Changed-property reporting therefore remains deferred
on performance grounds. The accepted
[EGW register-projection ADR](../decisions/2026-07-20-typed-spreadsheet-egw-register-projection.md)
records durable correctness and API-quality conclusions separately.

**Keep until:** Keep as an immutable dated performance snapshot; future numbers
belong in a new dated file.

**Disposition:** Retain in `docs/performance/` and supersede only by a newer
measurement record.

## Question and gate

EGW 0.4 exposes `get_property` but no property enumeration or changed-entity
report. The application-specific adapter therefore reads the canonical 50×50
address set on every projection. Plan 013 pre-registered a strict gate:

1. the existing pre-adapter browser baseline must meet its advisory p95 budget;
2. adapter FullScan must miss the same relevant budget in two independent runs;
3. a benchmark-only synthetic ChangedProperties path must restore it in both;
4. Loom or another second driver must confirm the application-independent need;
5. otherwise changed-property reporting stays deferred, regardless of isolated
   speedup.

The first condition failed, so the performance route is blocked. That blocker
does not invalidate bounded correctness, misuse-resistance, convenience, and
generality evidence, which is recorded in the accepted
[EGW register-projection ADR](../decisions/2026-07-20-typed-spreadsheet-egw-register-projection.md).
The microbenchmarks below remain useful cost attribution, but they are not
product-impact or general API evidence.

## Environment

| Item | Value |
|---|---|
| Baseline commit | `93314b4` plus the Phase 4 benchmark definitions in this snapshot's change |
| Moon | `0.1.20260713` (`75c7e1f`, 2026-07-13) |
| moonc | `v0.10.4+2cc641edf` (2026-07-15) |
| Node / npm | `v24.14.1` / `11.11.0` |
| Playwright | `1.61.1`, bundled headless Chromium |
| EGW | exact published `dowdiness/event-graph-walker@0.4.0` |
| Host | WSL2 Linux x86_64, AMD Ryzen 7 6800H, 8 logical CPUs |
| MoonBit target | JS release, Node/V8 |
| Moon bench sampling | 10 framework rounds per row; adaptive inner loops from 2 to 100,000; framework-managed warm-up is not reported separately |
| Browser sampling | 20 measured samples and 3 warm-ups per scenario per run |

Commands:

```bash
NEW_MOON_MOD=0 moon bench --release --target js \
  -p examples/typed_spreadsheet_incr_tea_demo/egw_adapter \
  -f adapter_bench_wbtest.mbt

cd examples/typed_spreadsheet_incr_tea_demo
BENCH_SAMPLES=20 BENCH_WARMUPS=3 npm run bench:dom
```

Both commands were run twice independently. Values are mean ± one standard
deviation for MoonBit rows and p95 for browser rows.

## Benchmark boundary

`adapter_bench_wbtest.mbt` owns a private hint model:

- **FullScan:** calls the same `snapshot_addresses` helper as production with
  all 2,500 canonical addresses.
- **ChangedProperties:** calls that helper with only benchmark-supplied changed
  addresses. EGW does not supply this list.

The synthetic transition's candidate state contains only that subset and is
never retained. It is deliberately a maximum lower bound, not a production
path.

A non-benchmark test pins 2,500 versus N `get_property` reads and equal semantic
decisions for the same valid changes, while production local and remote paths
continue to use FullScan.

The fixture's no-op draft/UI bindings let one `Runtime::batch` measure prepared
Worksheet operations without estimating a future UI binding cost. End-to-end
rows add authority property writes, snapshot acquisition, and core decode/diff
to that batch.

## Property reads

| Changed cells | FullScan reads | ChangedProperties reads |
|---:|---:|---:|
| 1 | 2,500 | 1 |
| 10 | 2,500 | 10 |
| 100 | 2,500 | 100 |
| 2,500 | 2,500 | 2,500 |

## Scan

| Changed | FullScan run 1 | FullScan run 2 | ChangedProperties run 1 | ChangedProperties run 2 |
|---:|---:|---:|---:|---:|
| 1 | 1.30 ms ± 60.23 µs | 1.31 ms ± 119.72 µs | 814.06 ns ± 3.86 ns | 816.75 ns ± 47.05 ns |
| 10 | 1.43 ms ± 29.33 µs | 1.32 ms ± 8.75 µs | 3.87 µs ± 59.92 ns | 3.84 µs ± 98.65 ns |
| 100 | 1.43 ms ± 75.88 µs | 1.39 ms ± 45.65 µs | 43.50 µs ± 592.44 ns | 41.60 µs ± 1.70 µs |
| 2,500 | 1.49 ms ± 43.05 µs | 1.45 ms ± 54.13 µs | 1.52 ms ± 41.76 µs | 1.41 ms ± 63.45 µs |

FullScan cost is approximately 1.2–1.5 ms regardless of sparse change count.
The synthetic scan converges to the same cost when all properties change.

## Decode only

| Changed | Run 1 | Run 2 |
|---:|---:|---:|
| 1 | 1.08 µs ± 26.64 ns | 1.05 µs ± 36.80 ns |
| 10 | 10.80 µs ± 351.27 ns | 10.23 µs ± 66.12 ns |
| 100 | 111.92 µs ± 7.16 µs | 102.55 µs ± 668.58 ns |
| 2,500 | 2.70 ms ± 58.34 µs | 2.63 ms ± 68.42 µs |

## Decode and diff

| Changed | FullScan run 1 | FullScan run 2 | ChangedProperties run 1 | ChangedProperties run 2 |
|---:|---:|---:|---:|---:|
| 1 | 665.99 µs ± 8.31 µs | 618.70 µs ± 21.78 µs | 426.80 µs ± 6.16 µs | 389.51 µs ± 5.45 µs |
| 10 | 701.86 µs ± 8.78 µs | 618.05 µs ± 7.39 µs | 442.80 µs ± 6.74 µs | 423.12 µs ± 12.39 µs |
| 100 | 822.60 µs ± 12.56 µs | 760.24 µs ± 24.17 µs | 634.74 µs ± 21.40 µs | 565.96 µs ± 10.39 µs |
| 2,500 | 5.40 ms ± 139.11 µs | 5.32 ms ± 291.86 µs | 5.55 ms ± 160.20 µs | 5.62 ms ± 314.66 µs |

Even a one-property synthetic snapshot retains a roughly 0.4 ms floor because
`compute_projection_transition` indexes the full 2,500-cell prior state before
processing entries. That pressure is adapter-core-local, not evidence for an
EGW reporting API.

## Prepared projection

| Changed | Run 1 | Run 2 |
|---:|---:|---:|
| 1 | 623.08 ns ± 14.08 ns | 659.12 ns ± 22.95 ns |
| 10 | 3.93 µs ± 120.21 ns | 4.33 µs ± 279.93 ns |
| 100 | 42.22 µs ± 1.72 µs | 46.05 µs ± 3.23 µs |
| 2,500 | 2.33 ms ± 216.44 µs | 2.94 ms ± 253.42 µs |

## Projection end to end

| Changed | FullScan run 1 | FullScan run 2 | ChangedProperties run 1 | ChangedProperties run 2 |
|---:|---:|---:|---:|---:|
| 1 | 2.04 ms ± 45.74 µs | 1.97 ms ± 76.46 µs | 451.98 µs ± 5.00 µs | 421.67 µs ± 5.43 µs |
| 10 | 2.16 ms ± 32.44 µs | 2.12 ms ± 76.55 µs | 566.77 µs ± 11.69 µs | 574.19 µs ± 49.69 µs |
| 100 | 3.36 ms ± 168.66 µs | 3.36 ms ± 229.31 µs | 1.86 ms ± 149.85 µs | 1.89 ms ± 232.32 µs |
| 2,500 | 36.35 ms ± 4.12 ms | 37.22 ms ± 2.41 ms | 37.11 ms ± 2.39 ms | 36.91 ms ± 4.02 ms |

The synthetic lower bound is about 4.5–4.7× faster at one changed cell and
3.7–3.8× at ten. The advantage narrows to about 1.8× at 100 and disappears at
2,500, where payload decode and Worksheet application dominate. This is
isolated shape evidence only.

## Pre-adapter browser gate

The existing browser executable was measured unchanged. No adapter or synthetic
path was added to it.

| Scenario | Budget | Run 1 p95 | Run 2 p95 | Gate |
|---|---:|---:|---:|---|
| selection | 16 ms | 19.8 ms | 16.0 ms | failed run 1 |
| formula-bar draft | 16 ms | 14.6 ms | 21.5 ms | failed run 2 |
| visible edit | 50 ms | 41.1 ms | 72.2 ms | failed run 2 |
| formula dependency | 100 ms | 41.9 ms | 60.6 ms | passed both |
| trace/evidence update | 100 ms | 45.0 ms | 53.4 ms | passed both |
| offscreen edit | 100 ms | 43.7 ms | 41.4 ms | passed both |

The host is unsuitable for the pre-registered browser comparison. Per the gate,
adapter-enabled FullScan and synthetic browser runs were not used to make an
EGW conclusion. A future run must first establish a stable baseline on the same
host/toolchain; only then may it add benchmark-only adapter A/B composition.

## Evidence ledger

| Pressure point | Evidence | Classification | Consequence |
|---|---|---|---|
| 2,500 bounded property reads on sparse changes | 1.2–1.5 ms FullScan; synthetic sparse scan is sub-µs to ~44 µs | Deferred performance candidate | Browser gate failed and no second driver confirms the same container need; evaluate non-performance pressure separately. |
| Full prior-state indexing in the pure reducer | ~0.4 ms synthetic decode/diff floor at one changed cell | Adapter-local | Revisit only after a valid product-level profile identifies it; do not optimize from this microbench alone. |
| Dense 2,500-cell projection | 36–37 ms mean end to end in both modes | Adapter/application-local | Changed hints do not help dense changes; decode and Worksheet application dominate. |
| `set_property` mutation observability | Existing read-back requirement, not measured as a performance cause | Deferred correctness evidence | Must use Plan 013's separate six-part correctness gate; timings do not authorize EGW changes. |
| Browser baseline variance | Three budget misses across two runs before adapter composition | Measurement environment | Blocks product-impact classification for this snapshot. |

## Conclusion

The full-scan cost and sparse synthetic advantage are real and reproducible in
the isolated JS release benchmark. They are insufficient to justify changed-
property reporting on performance grounds. The pre-adapter browser prerequisite
failed, no adapter browser A/B result is valid on this host, and Loom has not
confirmed the same container reporting need. Keep production remote
synchronization on FullScan while evaluating non-performance API pressure under
the separate gate.
