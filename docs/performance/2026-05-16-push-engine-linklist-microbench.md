# Push-Engine Link-List Port — Microbench-First Investigation

**Date:** 2026-05-16
**Backend:** wasm-gc (`moon bench --release`)
**Bench file:** `tests/bench_test.mbt`
**Investigation memory:** `memory/project_push_engine_linklist_port.md`
**Parent (closed) investigation:** `memory/project_per_mode_redesign_question.md` /
[`docs/decisions/2026-04-26-modal-runtime-split-not-warranted.md`](../decisions/2026-04-26-modal-runtime-split-not-warranted.md)
**Status:** Investigation closed 2026-05-16. **Link-list port deprioritized.** A
follow-up cost-decomposition pass surfaced higher-leverage targets (per-recompute
allocation elimination, disposed-cell anomaly, scheduler rewrite). See
[`2026-05-16-push-engine-cost-decomposition.md`](2026-05-16-push-engine-cost-decomposition.md)
for the broader analysis and chosen direction. This document remains the canonical
record of the Link-list-port-specific microbench evidence.

## Why this investigation

The closed per-mode runtime-split investigation (2026-04-26) surfaced one specific
structural change as the only real architectural win the comparison libraries
enable on top of incr's current design: replace push-engine subscriber storage
with alien-signals-style intrusive doubly-linked `Link` records, scoped strictly
to `cells/internal/push/`. Vue 3.6 reported a 3.47× speedup on its
`mutate-1000-refs` driver after porting alien-signals; the realistic gap for
incr is expected to be smaller because incr is already SoA (not Set-based).

The discipline (see [`memory/project_push_engine_linklist_port.md`](../../memory)
and `moonbit-perf-investigation` skill) is: write the microbench first, confirm
the gap empirically, write the ADR second, write the port last. This document
covers step 1.

## Hot-path target chosen for the bench

Two paths in the push engine are theoretically improved by a Link-list port:

1. **Subscriber-list iteration during push BFS**
   ([`cells/internal/kernel/push_propagate.mbt:145`](../../cells/internal/kernel/push_propagate.mbt) —
   `for sub_id in get_subscribers(core, id)`). `get_subscribers` returns
   `@hashset.HashSet[CellId].iter()`; Link-list replaces hashset traversal with
   pointer-chase.

2. **Source rebinding via `diff_and_update_subscribers`**
   ([`cells/internal/kernel/subscriber_diff.mbt`](../../cells/internal/kernel/subscriber_diff.mbt)). HashSet
   `contains` / `add` / `remove_and_check` each hash the `CellId`; Link-list
   eliminates the hashing per dep.

Path #1 was chosen as the *primary* target because (a) it is the path Vue 3.6
optimized, (b) it is exercised by steady-state mutation with no graph rewiring
(realistic interactive scenario), and (c) it isolates iteration cost from
`adjust_push_reachable` (which runs only on subscribe/unsubscribe and is
independent of Link-list).

Path #2 is benched as a fallback / contrast point.

## Benches

Added to `tests/bench_test.mbt`:

- `linklist-port: fanout 500 reactives, steady-state set`
- `linklist-port: fanout 1000 reactives, steady-state set`
- `linklist-port: branchy-rebind 100 reactives`

Existing benches re-used as baseline anchors:

- `baseline: push propagation with 100 live reactives` (line 183)
- `baseline: push propagation with 100 disposed reactives` (line 200)
- `signal: set new value` (no subscribers)

## Measurements

10-sweep × variable-iter, mean ± σ.

| Bench | N | total mean | per-reactive (mean / N) |
|---|---:|---:|---:|
| `signal: set new value` (no subscribers) | 0 | 5.45 ns ± 0.23 ns | — |
| `push propagation with 100 live reactives` | 100 | **1.73 µs ± 836 ns** | 17 ns (anomalously fast — see below) |
| `linklist-port: fanout 500 reactives` | 500 | **138.13 µs ± 3.21 µs** | 276 ns |
| `linklist-port: fanout 1000 reactives` | 1000 | **288.90 µs ± 2.48 µs** | 289 ns |
| `push propagation with 100 disposed reactives` | 100 dead | **24.21 µs ± 1.35 µs** | 242 ns (iter-only, compute skipped) |
| `linklist-port: branchy-rebind 100 reactives` | 100 | **76.70 µs ± 0.50 µs** | 767 ns |
| `push propagation with 100 abandoned reactives` | ~0 effective | 47.51 ns ± 3.86 ns | — |

### N=100 anomaly

The `100 live reactives` baseline runs at 1.73 µs ± 836 ns (range 842 ns to
2.97 µs) — significantly faster than would be predicted by linear scaling from
the N=500 / N=1000 numbers (which scale tightly). Likely explanations: small-N
HashSet fits in the initial bucket array with no resize; SoA arrays fit in L1
cache; benchmark warmup interacts oddly at low absolute cost. The N=500 and
N=1000 numbers are tight and proportional and are the relevant data points for
the port investigation.

### Disposed-reactives bench is the iter-only ceiling

The `100 disposed reactives` bench is the cleanest measurement of HashSet-iter
cost in isolation: sig still owns 100 entries in its subscriber HashSet, but
because the targets are `Disposed` in `cell_index`, the BFS match arm hits `_`
and skips. No compute, no priority queue, no diff. The 24 µs / 100 = **242 ns
per disposed subscriber** is the upper bound on what a Link-list iter speedup
can shave from the BFS walk.

## What the port would actually save

Per-iter cost breakdown at N=1000 fanout (289 ns/reactive/set):

| Component | Path | Approx cost (per reactive) | Link-list helps? |
|---|---|---:|---|
| Outer BFS step (sig.subscribers.iter()) | `push_propagate.mbt:145` | ~50–100 ns | **yes — iter** |
| Priority-queue push + pop (heap, log N) | `push_propagate.mbt:150, 178` | ~30–50 ns | no (orthogonal — would need scheduler rewrite) |
| Compute closure (sig.get + Int.add + Option match) | `push_reactive.mbt:28-36` | ~50–100 ns | no |
| `pop_tracking` returns new_seen HashSet (1 elem) | tracking.mbt | ~30–50 ns | no (allocation, not subscriber-set) |
| `diff_and_update_subscribers` early-exit | `subscriber_diff.mbt` | ~30 ns | partial — early-exit case |
| `recompute_level` | push_propagate.mbt | ~10 ns | no |

The disposed-reactives ceiling (242 ns iter-only) is consistent with **outer
BFS step ≈ 50–100 ns** in the live case after subtracting the priority-queue +
match overhead that the disposed path also pays. So the Link-list iter
replacement could save ~50–100 ns out of 289 ns per reactive — roughly
**1.2×–1.4× on the steady-state fanout path**.

For the branchy-rebind path (767 ns/reactive), the extra ~500 ns over
steady-state is split between `diff_and_update_subscribers` HashSet ops and
`adjust_push_reachable` traversal. Link-list replaces the HashSet portion;
estimate maybe 200–300 ns recoverable, for **1.3×–1.5× on the rebind path**.

## Verdict

**The win exists but is at the lower end of the threshold the investigation set
(>1.3×).** The Vue 3.6 "3× speedup" headline does not replicate here, because:

- incr's push engine is already SoA, so it does not start from Vue's pre-port
  Set-based baseline.
- incr's hot path includes additional machinery (`adjust_push_reachable`,
  `push_reachable_count`, priority-queue scheduling) that is **independent of
  Link-list** and is a meaningful fraction of per-reactive cost.
- The dominant per-reactive cost at N≥500 is the compute closure invocation +
  priority-queue heap ops, neither of which Link-list addresses.

**Realistic expected speedup:** 1.2×–1.5× on push-heavy workloads with steady
or near-steady source sets. Higher on pathological iter-only paths (the
disposed-reactives case), lower on workloads where the compute closure is
expensive (any real application).

## What this means for the discipline gate

Memory says: "If the microbench shows <1.3× headroom: close this investigation
as not-warranted." The data is **marginal** — at the threshold, not clearly
above it. Both interpretations are defensible:

- **Close as not-warranted:** the realistic gap is smaller than predicted, the
  implementation is significantly more complex than HashSet code (intrusive
  linked lists, Link-node lifecycle, free-list management per cell, version
  numbers for in-place sweep), and the headroom would shrink further on
  workloads with non-trivial compute closures.
- **Proceed to ADR:** 1.2–1.5× is real, the port is engine-internal, the
  `CellId` boundary survives, and the win compounds with other push-heavy
  improvements.

The user's call. The next session decides.

## What the port would look like (sketch only — no implementation this session)

If the user chooses to proceed, the sketch is below. Stop reading if the
verdict is to close the investigation.

### Layout

Replace `CellMeta.subscribers : @hashset.HashSet[CellId]` and the per-cell
`sources : Array[CellId]` field on push reactives/effects with a single
intrusive `Link` record type and head pointers:

```moonbit
// New file: cells/internal/push/link.mbt
pub(all) struct Link {
  /// The cell that depends on (subscribes to) `dep`.
  sub : CellId
  /// The cell being subscribed to.
  dep : CellId
  /// Prev/next in `dep.subscribers` list (the dep's view: who watches me).
  mut prev_sub : Link?
  mut next_sub : Link?
  /// Prev/next in `sub.sources` list (the subscriber's view: who do I watch).
  mut prev_dep : Link?
  mut next_dep : Link?
  /// Version stamp for alien-signals' "mark stale, sweep" rebinding pattern.
  mut version : Int
}
```

Modify `CellMeta` so subscribers are a head pointer:

```moonbit
pub(all) struct CellMeta {
  cell_id : CellId
  mut label : String?
  mut changed_at : Revision
  mut durability : Durability
  /// Head of the doubly-linked subscriber list. Replaces HashSet.
  mut subs_head : Link?
  mut push_reachable_count : Int
}
```

Modify `PushReactiveData` / `PushEffectData` so sources are a head pointer:

```moonbit
pub(all) struct PushReactiveData {
  meta : CellMeta
  mut compute : () -> Bool
  /// Head of the doubly-linked source list. Replaces sources : Array[CellId].
  mut deps_head : Link?
  mut level : Int
  mut dirty : Bool
}
```

### How the `CellId` boundary survives

The Link record carries `CellId` fields (`sub`, `dep`), so cross-engine code
that operates in terms of `CellId` (HybridMemo's bridge, Effect→Rule, the
kernel's cycle detection / gc / dispose paths) continues to address cells the
same way. Only `cells/internal/push/` and the BFS walker in
`cells/internal/kernel/push_propagate.mbt` see the Link layout. Pull engine,
datalog engine, and shared traits remain unchanged.

### How the kernel BFS continues to drive propagation

In `push_propagate.mbt:145`:

```moonbit
for sub_id in get_subscribers(core, id) { ... }   // current: HashSet iter
```

becomes:

```moonbit
let mut link = core.cell_ops[id.id].subs_head()
while link is Some(l) {
  let sub_id = l.sub
  // ... existing arm-match logic on sub_id ...
  link = l.next_sub
}
```

`get_subscribers` returns `Iter[CellId]` today; it would either return an iter
over the linked list or be replaced with a direct walk. The CellOps trait
method `subscribers()` either changes signature or grows a `subs_head()`
companion. The kernel walker doesn't care about Link internals — it operates
on `CellId`.

### How `diff_and_update_subscribers` becomes Link-reuse

Today's diff:

```
for dep in old_deps:
  if dep not in new_seen: remove_subscriber(dep, self)
for dep in new_deps:
  if dep not in old_seen: add_subscriber(dep, self)
```

becomes the alien-signals sweep pattern:

```
version += 1
for dep in tracked_deps_this_run:
  if dep has live Link with self: link.version = version (reuse)
  else: allocate Link, splice into both lists, link.version = version
walk self.deps_head:
  if link.version != version: unlink from both lists, recycle Link
```

This eliminates the HashSet contains/add/remove path entirely. Link records
recycle via a per-runtime free list.

### Test plan (mandatory before any port)

The discipline memory says ADR before code. The ADR must specify:

- Invariant: subscriber and dep lists are mutually consistent (every Link
  appears in exactly one subs list and exactly one deps list).
- Invariant: no Link survives dispose of either endpoint.
- Test: property test that randomly subscribes/unsubscribes and asserts after
  every op that for every cell `c`, `c.subs.iter().count() ==` number of Links
  with `dep = c`, and symmetric for deps.
- Test: existing push-propagation, HybridMemo, Effect→Rule integration tests
  continue to pass unchanged.
- Bench: re-run the three `linklist-port:` benches and the existing baselines.
  Predicted post-port speedup is 1.2–1.5× on fanout, 1.3–1.5× on rebind. If
  measured speedup is <1.3× or implementation complexity exceeds ADR estimate,
  revert.

### Rollback shape

The port is gated by a single moon.pkg `internal` boundary (`cells/internal/push/`).
A revert is `git revert` of the port commit. No public API surface changes,
no migration path needed.

## Recommendation to the user

Treat this as a **decision-required surface**, not an automatic proceed. The
microbench reproduces a smaller gap than the Vue 3.6 headline suggested; the
port's complexity (intrusive doubly-linked lists, Link-node lifecycle,
free-list, version-based sweep, kernel-walker plumbing) is non-trivial. The
realistic upside is 1.2–1.5× on push-heavy paths, lower on workloads with
real compute.

Two coherent paths forward:

- **Proceed to ADR.** Treat 1.2–1.5× as worth the implementation cost; record
  the smaller-than-Vue expectation in the ADR up front so the post-port
  measurement isn't compared against the wrong baseline.
- **Close as not-warranted.** Log the closure note next to the per-mode-split
  ADR. The expected gain doesn't clear the implementation cost bar. Revisit
  if a future driver (heavier fanout, faster compute closures, e.g.,
  fine-grained DOM updates) shifts the cost balance.

I have a slight preference for closing — the iter-only ceiling (242 ns) shows
that *even at the upper bound* the iter replacement saves under 100 ns per
reactive in realistic mixed workloads, and the structural complexity of
intrusive linked lists in MoonBit (especially around dispose / GC sweep
interactions) is a real maintenance cost. But the data does not force the
decision.
