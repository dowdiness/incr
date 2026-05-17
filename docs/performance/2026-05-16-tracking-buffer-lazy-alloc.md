# Tracking-Buffer Lazy Allocation — Implementation Result

**Date:** 2026-05-16
**Backend:** wasm-gc (`moon bench --release`)
**Status:** Shipped. Implements the chosen direction from
[`2026-05-16-push-engine-cost-decomposition.md`](2026-05-16-push-engine-cost-decomposition.md)
("Per-recompute allocation elimination (tracking-buffer reuse)") with one
correction: **pool reuse was rejected by the probe; only lazy-allocation was
implemented.**

## What changed

`ActiveQuery` (`cells/internal/kernel/state.mbt`) now holds the two
accumulator-related collections as `Option<T>`:

```moonbit
pub(all) struct ActiveQuery {
  cell_id : CellId
  dependencies : Array[CellId]
  seen : @hashset.HashSet[CellId]
  mut accumulator_reads : @hashmap.HashMap[(AccumulatorId, CellId), Revision]?
  mut touched_accumulator_slots : @hashset.HashSet[AccumulatorId]?
}
```

`ActiveQuery::new` sets both to `None`. Write sites call
`ensure_accumulator_reads()` / `ensure_touched_accumulator_slots()` which
lazily allocate. Read sites pattern-match on the Option and treat `None` as
empty. `memo_commit_accumulator_phase` accepts `Option`-typed parameters
(no allocation needed when the frame had no accumulator interaction).

Push reactives and push effects never touch accumulators, so they pay zero
allocation cost for these two collections per recompute. Most memo frames
also don't read accumulators, so they benefit too.

## Microbench results

### Synthetic probe (allocation cost isolation)

A throwaway probe in `tests/alloc_probe_bench_test.mbt` mirrored the
ActiveQuery shape exactly, measuring fresh-per-iter vs reused-with-clear()
vs PushOnly-shape (3 of 5 allocs). All ran 10 × 100 000 iters.

| Variant | mean (ns) | Δ vs fresh | % |
|---------|----------:|-----------:|--:|
| noop baseline | 8.69 | — | — |
| K=0 floor — fresh 5-alloc | 50.83 | — | — |
| K=0 floor — PushOnly 3-alloc | 26.37 | **−24.5** | **−48%** |
| K=3 — fresh + 3 deps | 118.04 | — | — |
| K=3 — reused via clear() + 3 deps | 115.29 | −2.8 | −2% (within σ) |
| K=3 — PushOnly + 3 deps | 87.41 | **−30.6** | **−26%** |

**Two findings that reshaped the strategy:**

1. **Pool reuse via `clear()` is noise (~5%).** wasm-gc handles short-lived
   empty allocations cheaply, and `clear()` itself does work (fills entries
   with `None` on the hashset/hashmap, which roughly equals the cost saved).
   The original cost-decomposition doc's pool-reuse plan was dropped.
2. **Lazy-allocation of the 2 accumulator-only fields delivers ~5× the win**
   and is strictly simpler — no pool, no aliasing concerns with
   `pop_tracking` ownership transfer.

The K=0 floor isolates pure allocation cost: 5 allocs = ~42 ns; 3 allocs =
~17.7 ns; **the 2 accumulator-only allocs cost ~24.5 ns**, consistent with
the K=3 savings of ~30.6 ns.

### Real-world push fanout (validation)

Before/after on the unchanged push-fanout benches in `tests/bench_test.mbt`.
Before numbers were captured pre-implementation during the same
investigation session (the diagnostic benches added in this commit) and
recorded in
[`2026-05-16-push-engine-cost-decomposition.md`](2026-05-16-push-engine-cost-decomposition.md).
Same backend (wasm-gc, `moon bench --release`), same hardware, same
bench definitions; only `cells/internal/kernel/state.mbt` +
`cells/accumulator.mbt` differ.

| Bench | Before | After | Δ |
|-------|---:|---:|---:|
| 500 reactives steady-state set | 138 µs (276 ns/r) | **110.06 µs (220 ns/r)** | **−20.3%, −56 ns/r** |
| 1000 reactives steady-state set | 289 µs (289 ns/r) | **243.01 µs (243 ns/r)** | **−15.9%, −46 ns/r** |

Larger than the synthetic probe predicted (~30 ns) because the real
`pop_tracking` (non-full variant used by push reactives) discards the
ActiveQuery entirely — the two never-allocated collections save GC sweep
work, not just the alloc itself. Above the >10% threshold the investigation
discipline required for proceeding past the sub-step.

### Memo-heavy paths (regression check)

| Bench | After |
|-------|---:|
| `memo: get warm` | 98.12 ns |
| `memo: get stale` | 491.37 ns |
| `memo: deep chain get (100 levels, stale)` | 34.45 µs |
| `memo: wide fanout get (1 signal, 50 memos, stale)` | 22.24 µs |

No regression — within expected variance for memo paths. The Option
indirection at write sites is paid only when a memo actually reads an
accumulator; the read-site pattern-match on `None` is essentially free.

## Probe also verified MoonBit clear() semantics

Pre-implementation check confirmed all three relevant `clear()` impls retain
their underlying storage (not strictly needed once pool reuse was rejected,
but recorded for the next person who considers pooling):

| Type | impl | Retains buffer |
|------|------|---:|
| `Array::clear` | `unsafe_truncate_to_length(0)` (nulls buf slots + `len=0`; JS: `set_length(0)`) | yes |
| `HashSet::clear` | `entries.fill(None); size = 0` | yes (entries FixedArray) |
| `HashMap::clear` | `entries.fill(None); size = 0` | yes (entries FixedArray) |

Caveat: `Array::new()` is inline-empty — first push allocates the backing
buffer. So a pool only avoids re-growing capacity, not the first allocation.

## What was NOT changed (and why)

- **Pool of ActiveQuery instances.** Probe showed ~2% saving (noise).
  Rejected.
- **Per-memo `MemoData.accumulator_reads` (`cells/memo.mbt:77`).** Separate
  field on `MemoData`, not on `ActiveQuery`. Could be made lazy too, but
  that's a different ~30 ns saving per memo recompute on memos that don't
  use accumulators. Track separately if a memo-heavy driver surfaces it.
- **`MemoData.dependencies` array.** Pool reuse would be aliased with
  `pop_tracking` ownership transfer. Probe already showed pool reuse on
  ActiveQuery is noise, so this would be too.

## Next strategic targets (from cost-decomp doc)

1. **Disposed-cell anomaly investigation — retracted 2026-05-17.** Not a real
   anomaly; the original 240 ns/cell claim was a label-swap with the abandoned
   bench. See [`2026-05-16-push-engine-cost-decomposition.md`](2026-05-16-push-engine-cost-decomposition.md)
   §"Key finding (retracted 2026-05-17)" and the regression test at
   `cells/push_reactive_wbtest.mbt` "dispose: 100 reactives on one signal
   leave subscribers empty and node_count zero".
2. **Scheduler rewrite: priority-queue → level-bucketed dirty list** — ~30–50
   ns/reactive estimated. Gated on a driver demanding push-engine perf;
   none exists yet.
3. **Push-engine link-list port** — deprioritized in companion doc.

## What was NOT measured

- **JS backend.** Canopy ships to the web. The Option indirection cost on
  V8 is different from wasm-gc; verify on the JS backend before declaring
  victory there. The lazy-alloc change is structurally a clear win
  regardless (allocations avoided are allocations avoided), but the
  magnitude may differ.
- **Real-application workloads.** The lambda editor benchmark suite in
  `loom/examples/lambda/src/benchmarks/` is the natural sanity-check.
