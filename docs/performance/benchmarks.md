# Benchmark Results

Microbenchmarks for `incr` core operations, measured with `moon bench --release`.

**Platform:** Linux (WSL2), MoonBit native backend
**Date:** 2026-03-08
**Commit:** `6c4a17c` (after hybrid dirty-marking removal)

## Results

| Benchmark | Mean | σ | Range |
|-----------|------|---|-------|
| signal: get | 0.01 µs | 0.00 µs | 0.01–0.01 µs |
| signal: set same value (no-op) | 0.00 µs | 0.00 µs | 0.00–0.00 µs |
| signal: set new value | 0.03 µs | 0.00 µs | 0.03–0.03 µs |
| memo: get warm | 0.02 µs | 0.00 µs | 0.02–0.02 µs |
| memo: get stale | 0.28 µs | 0.00 µs | 0.27–0.28 µs |
| memo: deep chain (100 levels, stale) | 24.86 µs | 0.77 µs | 24.01–26.26 µs |
| memo: wide fanout (1 sig, 50 memos, stale) | 13.28 µs | 0.37 µs | 12.90–14.11 µs |
| hybrid: get warm | 0.02 µs | 0.00 µs | 0.01–0.02 µs |
| hybrid: get stale | 0.30 µs | 0.00 µs | 0.29–0.30 µs |
| batch: 10 signals, single revision | 1.28 µs | 0.07 µs | 1.23–1.45 µs |

## Key Observations

### Signal operations are near-zero cost

- `get` is a field read + runtime ID check: **0.01 µs**
- `set` with same value (Eq short-circuit): **0.00 µs**
- `set` with new value (revision bump + changed_at update): **0.03 µs**

### Memo warm path is fast

- `get` when already verified: **0.02 µs** (verified_at comparison + cached value return)
- Same cost for both Memo and HybridMemo

### Memo vs HybridMemo stale path — parity achieved

After removing push dirty-marking, hybrid stale matches memo stale:

| | Before (with push dirty-marking) | After (verified_at only) |
|---|---|---|
| memo: get stale | 0.27 µs | 0.28 µs |
| hybrid: get stale | 0.36 µs | 0.30 µs |
| **gap** | **0.09 µs** | **0.02 µs** |

The gap was caused by `HybridMemo::new` incrementing `node_count`, which triggered the full `push_propagate_from` BFS (priority queue + subscriber traversal) on every `signal.set()` even when no push nodes existed. Fix: HybridMemo no longer increments `node_count`.

### Verification scales linearly with depth

- 100-level deep chain: **24.86 µs** (~0.25 µs per level, matching single-memo stale cost)
- 50-memo wide fanout: **13.28 µs** (~0.27 µs per memo, same per-memo cost)

### Batch amortizes revision bumps

- 10 signals batched: **1.28 µs** (vs 10 × 0.03 µs = 0.30 µs unbatched signal sets + overhead)
- Single revision bump + two-phase commit for all signals

## How to Run

```bash
cd loom/incr
moon bench --release -p dowdiness/incr/tests
```

Benchmark source: `tests/bench_test.mbt`

## History

| Date | Change | Impact |
|------|--------|--------|
| 2026-03-08 | MemoData unification (PullMemoData + HybridMemoData → MemoData) | No measurable change |
| 2026-03-08 | Remove push dirty-marking for HybridMemo | hybrid stale: 0.36 → 0.30 µs |
