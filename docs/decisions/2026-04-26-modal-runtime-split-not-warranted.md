# ADR: Modal Runtime Split — Not Warranted

**Date:** 2026-04-26
**Status:** Accepted — investigation closed; revisit only with concrete driver
**Supersedes:** the "Per-mode Runtime redesign — open question" deferral in `~/.claude/projects/.../memory/project_per_mode_redesign_question.md` (originSessionId `79d88085-e442-4f78-8e22-3d248c3333f2`, 2026-04-26)
**Anchors:** [R2 deferred](2026-04-26-r2-runtime-decomposition-deferred.md), [2026-04-20 architecture assessment](../design/specs/2026-04-20-architecture-assessment.md)

## Context

The user raised whether `Runtime` should be reshaped so consumers using only one propagation mode (pull / push / datalog) don't carry empty SoA state from the other modes ("luggage"), and so each mode could pick optimal data structures unconstrained by shared dispatch. The deferral memory recorded two premises that both needed empirical verification before any design work:

1. **Premise 1.** Unused-mode state inside `Runtime` imposes meaningful memory or allocation cost.
2. **Premise 2.** Each mode is constrained from picking better data structures because of shared dispatch, and someone can name a concrete X→Y change that would follow from physical separation.

Per the rule "if both premises refute, write a short ADR recording the measurements and the conversation, and stop," this document is that ADR.

## Premise 1 — measurement (refuted)

A microbench was added at `tests/bench_test.mbt:8` measuring `Runtime::new()` in isolation, on wasm-gc --release.

| Operation | Mean cost |
|---|---|
| **`Runtime::new()` (full — pull + push + datalog SoA + dispatch + 2 hashmaps)** | **0.11 µs** |
| `signal: get` | 0.02 µs |
| `signal: set new value` | 0.04 µs |
| `signal: create-dispose cycle` | 1.57 µs |
| `memo: create-dispose cycle` | 1.36 µs |

**Memory accounting.** The unused-mode "luggage" inside one Runtime is precisely:
- `PushState`: 4 empty `Array` headers + 1 `mut Int` (when push is unused).
- `DatalogState`: 3 empty `Array` headers (when datalog is unused).

That is roughly 7 empty Array headers, sub-KB per Runtime. Even at 1000 Runtimes — which incr has zero realistic use case for; typical apps run a single Runtime — total unused-mode memory stays under 1 MB.

**Verdict.** A full Runtime allocation costs 110 ns; the unused-mode portion is a fraction of that and **14× cheaper than creating a single signal**. Any real workload creates thousands of cells whose costs dwarf the Runtime setup. Premise 1 is refuted.

## Premise 2 — comparative research (refuted)

Three reference implementations were studied to find concrete per-mode design wishes:

| Library | Modes | Runtime shape | Per-cell layout |
|---|---|---|---|
| **incr (this lib)** | pull + push + datalog | Single `Runtime` with shared dispatch (`cell_index`, `cell_ops`, `cell_lifecycle`, `gc_root_counts`, accumulator state) + per-mode SoA | SoA arrays + free-lists, `CellId` is index |
| **salsa (Rust)** | pull only | Single unified `Database` for input / tracked-fn / tracked-struct / interned / accumulator | Per-ingredient storage |
| **ripple (mizchi, MoonBit)** | pull only — direct Salsa port | Small `Runtime { current_revision, query_stack, durability_revisions, verifiers: HashMap }` + `Database` facade | Per-ingredient storage |
| **signals.mbt (mizchi, MoonBit)** | push only — alien-signals port | **No Runtime.** Module-level `Ref` globals (`active_sub`, `batch_depth`, `cycle`, `queued`) | Doubly-linked `Link` records bridging dep↔sub |

### Three algorithmic families, not one

The literature reveals three competing architectures:

1. **Graph-coloring lazy-pull** (Reactively, Salsa, **incr's pull mode**): Red/Green/Clean states; lazy walk-up on read finds first red ancestor.
2. **Doubly-linked push-pull** (Preact, alien-signals, signals.mbt): No Array/Set/Map; no recursion; O(1) dep reshuffle by reusing existing tail link.
3. **SoA with shared dispatch** (**incr's push + datalog modes**): Cache-friendly bulk traversal; uniform `CellId` enables cross-mode seams.

**incr is the only library here that combines two families inside one runtime.** Salsa, ripple, signals.mbt are all single-mode. None of them have a "split runtime per mode" architecture worth borrowing because the design space simply doesn't exist in single-mode libraries.

### Industrial validation: Vue 3.6 alien-signals port (PR #12349)

| Workload | Speedup vs Vue 3.5 |
|---|---|
| Read 1000 computed (with effects) | **3.63×** |
| Mutate 1000 refs | **3.47×** |
| Branch toggle 1000 refs (dynamic deps) | **3.26×** |
| Tracking 1000 refs | 1.65× |
| Memory at scale | **13% reduction** (2.3MB → 2.0MB) |

This is the upper bound on what incr's push mode could potentially gain by adopting the link-list. Vue 3.5 was Set-based; incr is already SoA-Array-based, so the realistic gap for incr is smaller than 3×.

### Incr's actual push-mode numbers (wasm-gc --release)

| incr operation | Cost | Per-element |
|---|---|---|
| memo: deep chain 100 levels stale | 34.56 µs | ~346 ns / level |
| memo: wide fanout 1→50 memos stale | 21.57 µs | ~431 ns / memo |
| **push: propagation 100 live reactives** | **17.39 µs** | **~174 ns / reactive** |

A link-list port might reduce 174 ns → ~75 ns per notification. On a 1000-effect re-run that's ~75–125 µs saved — meaningful only when workloads regularly touch thousands of effects per frame.

### The single concrete X→Y candidate, and why it fails the constraint

> "If push were separated, push could replace SoA `Array[PushReactiveData]` + free-list with alien-signals-style doubly-linked `Link` records. Reason: O(1) dep reshuffle by reusing the existing tail link instead of paying subscriber-diff cost on every effect rerun, plus removal of `cell_index`/`cell_ops` indirection on every `signal.get()`."

This is the only candidate the research surfaced that is technically defensible. It is also **incompatible with the cross-mode integration constraint** the user fixed at investigation start:

- `HybridMemo` straddles the pull/push seam and requires a uniform `CellId` to look up cells regardless of which mode owns them.
- `Effect→Rule` (push effect bodies driving datalog rule reactivation) requires shared cell identity at the push/datalog seam.
- Both depend on the shared dispatch layer that physical mode separation would dissolve.

Any redesign that breaks these is — by the user's own framing — the wrong redesign, because they are the library's main value proposition. Premise 2 is refuted: the only concrete wish that survived literature review fails the hard constraint.

## What incr did give up

To stay honest about the trade, the SoA-with-shared-dispatch choice imposes three measurable costs on the push path specifically:

1. **~2× slower per-notification** vs. a hypothetical alien-signals port (174 ns → ~75 ns estimate).
2. **~13% extra push memory** at scale (Vue port number; concretely, `cell_index` + `cell_ops` slots per push cell).
3. **Per-effect-rerun dep-diff cost** — incr does subscriber_diff every recompute; alien-signals reuses unchanged links in O(1).

These costs exclusively buy capabilities that no comparison library offers:

- **HybridMemo** (pull/push seam) and **Effect→Rule** (push/datalog seam) — cross-mode integration is incr's distinctive contribution.
- **Multi-Runtime isolation** — alien-signals' module globals can't support multiple isolated computation contexts in one process.
- **Cache-friendly bulk traversal** for GC sweep, accumulator iteration, batch dispose.
- **Snapshot/replay testability** via `RuntimeCore`.

Salsa + ripple **validate the unified-Runtime choice** for the modes they share. signals.mbt **shows the radical alternative** (module globals) that loses isolation. Neither suggests "split per mode" as a viable third path.

## Decision

1. **Do not split `Runtime` per propagation mode.** No PR, no plan, no spike.
2. **Retire the per-mode-split question from rolling memory.** Update `project_per_mode_redesign_question.md` to point at this ADR.
3. **Flag the actually-actionable follow-up.** The link-list win is real; the right scope is "can `cells/internal/push/` adopt alien-signals-style link records while keeping the `CellId`/`cell_ops` boundary intact?" That is a much smaller refactor, scoped to one engine package, preserving all cross-mode integration. It has a concrete driver (Vue's 3× push-bench result) and would not appear on the deferred list. If pursued, it should be opened as its own ADR with a microbench-first investigation per the moonbit-perf-investigation skill.

## Trade-offs accepted

- **Accept the 2× push-notification cost** (174 ns vs. ~75 ns hypothetical) as the price of cross-mode integration. If incr ever has a pure-push workload that genuinely needs alien-signals-class throughput, the right answer is to investigate the scoped engine-internal port (item 3 above), not to split the Runtime.
- **Accept that the per-mode catalog framing is closed.** Together with the 2026-04-26 R2 deferral, the post-R1 structural-tracks list now reduces to the two T-tracks documented in the 2026-04-20 architecture assessment (T1b MemoCommitPhase, T3 RuntimeRegistry), both gated on their own drivers.

## Verification

- `Runtime::new()` measurement: confirmed against `tests/bench_test.mbt:8` on wasm-gc --release.
- Comparison libraries surveyed: salsa-rs/salsa, mizchi/ripple, mizchi/signals.mbt, stackblitz/alien-signals, vuejs/core PR #12349, milomg.dev Reactively writeup, preactjs.com signal-boosting writeup.
- No existing ADR or written spec proposed per-mode Runtime separation prior to this investigation; the question lived only in rolling memory.
