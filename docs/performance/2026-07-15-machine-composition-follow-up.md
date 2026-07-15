# Machine composition invariant and instrumentation follow-up — 2026-07-15

This snapshot follows the
[2026-07-14 aggregate evidence](2026-07-14-machine-composition-evidence.md)
after the package-private request-sequence invariant and benchmark
instrumentation were hardened. It uses the same workload, environment,
toolchain, browser, sizes, warm-up, sample count, and 16,700 µs gate.

## Changes under verification

- request sequence now has one source in validation state;
- controlled-property attribution uses a private typed observer rather than a
  browser-global callback;
- timed runs disable decision and issued-command observer bookkeeping before
  warm-up;
- deterministic identity, mutation-locality, stale, and duplicate assertions
  run in the `incr_tea-machine-composition-dom` CI job. Timing remains manual.

## Invariant follow-up run

The first follow-up, after removing duplicated sequence storage, produced:

| children | run | total p50 | total p95 | transition p95 | view p95 | DOM patch p95 |
|---:|---:|---:|---:|---:|---:|---:|
| 64 | 1 | 100 | 200 | 0 | 100 | 100 |
| 64 | 2 | 0 | 200 | 0 | 100 | 100 |
| 64 | 3 | 0 | 100 | 0 | 100 | 100 |
| 256 | 1 | 100 | 500 | 100 | 200 | 200 |
| 256 | 2 | 200 | 500 | 100 | 300 | 200 |
| 256 | 3 | 100 | 200 | 100 | 100 | 200 |

All three 256-child p95 runs passed. This table preserves the already-recorded
invariant-follow-up snapshot; it is not the final instrumentation result.

## Observer-disabled final run

After replacing the global callback and disabling Program observer bookkeeping
during warm-up and timed dispatch, the final run produced:

| children | run | total p50 | total p95 | transition p95 | view p95 | DOM patch p95 |
|---:|---:|---:|---:|---:|---:|---:|
| 64 | 1 | 100 | 300 | 0 | 100 | 100 |
| 64 | 2 | 0 | 100 | 0 | 100 | 100 |
| 64 | 3 | 0 | 100 | 0 | 100 | 100 |
| 256 | 1 | 200 | 500 | 100 | 200 | 200 |
| 256 | 2 | 200 | 600 | 100 | 300 | 300 |
| 256 | 3 | 200 | 300 | 100 | 100 | 200 |

All three 256-child p95 runs pass the 16,700 µs gate and the 8,000 µs stretch
target. Timer granularity and run-to-run noise are larger than any useful claim
about the instrumentation change itself; this is regression evidence, not an
optimization result.

The final run emitted 6,000 raw records to
`/tmp/incr-machine-composition-raw.json` through:

```bash
rtk npm --prefix examples/incr_tea run bench:machine-composition
```

