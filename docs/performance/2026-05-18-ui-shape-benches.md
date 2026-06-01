# UI-Shape Microbenchmark — 60 Hz Push-Engine Headroom

**Date:** 2026-05-18
**Backends:** wasm-gc (default), JS (Node + V8)
**Bench file:** [`tests/ui_shape_bench_test.mbt`](../../incr/tests/ui_shape_bench_test.mbt)
**Question:** Can incr's push engine — tuned for parser-shaped (deep, batchy) workloads — drive a UI library at 60 Hz with on the order of 1000 reactive cells?

## Why this exists

A design conversation about building a UI library on incr surfaced the worry that UI workloads are wide+shallow+continuous (hover, scroll, animation frames at 60–120 Hz), unlike parser workloads (deep trees, batchy edits). The fear: per-update cost above "a few µs" would force architectural compromises in any UI design.

Rather than design around the fear, write the microbenchmark first. The existing baseline `baseline: push propagation with 100 live reactives` runs at ~22 µs; linear extrapolation suggests 1000-fanout would cost ~220 µs, but that's pure fanout — not a tree, and not a realistic UI shape.

## Shapes measured

Five microbenchmarks, each measuring one root signal mutation:

| Bench | Shape |
|---|---|
| flat 100 reactives | 1 Signal → 100 Reactives. Baseline sanity check. |
| flat 1000 reactives | 1 Signal → 1000 Reactives. Worst-case wide fanout. |
| layered 1000 (Signal→Memo→1000 Reactives) | State → derived → DOM-effect. Closest analogue to a component tree consuming a memoized Context-style selector. |
| **flat 1000, only 10 subscribed (sparse mutation)** | 1000 Reactives exist; 10 subscribe to the mutated signal, 990 subscribe to an unrelated cold signal. The realistic per-frame case — hover state, scroll position, single-component local state. |
| tree 1023 memos + 512 leaf reactives | Balanced binary tree of Memos, depth 10, with a Reactive at each of the 512 deepest nodes. Component-tree analogue where each layer reads its parent's projection. |

## Measurements

10 internal iterations per bench; mean ± σ. Two independent runs per backend; values below are means across both. Tree-shape wasm-gc has higher run-to-run variance (~12%) than the others (within 3%); the per-run internal σ is small (~2%).

| Shape | wasm-gc | JS (Node v8) | JS / wasm-gc | % of 60 Hz frame (16.67 ms) on JS |
|---|---:|---:|---:|---:|
| flat 100 reactives | 15.2 µs | 36.7 µs | 2.41× | 0.22% |
| flat 1000 reactives | 216 µs | 459 µs | 2.13× | 2.75% |
| layered 1000 (1 Memo bridge) | 242 µs | 496 µs | 2.05× | 2.97% |
| **sparse 1000 (10 subscribed)** | **1.50 µs** | **3.61 µs** | 2.40× | **0.022%** |
| tree 1023 memos + 512 leaf reactives | 808 µs | 1.32 ms | 1.63× | 7.92% |

## Interpretation

**The "60 Hz at 1000 nodes" concern is not reproducible.** Even the worst case I could construct (deep balanced tree, 1535 cells, root mutation) consumes 4.8% of a 60 Hz frame on wasm-gc and 7.9% on JS. The realistic per-frame case (sparse mutation — most of the UI isn't subscribed to the changed signal) runs in 1.5–3.6 µs, confirming that incr's existing per-source subscriber gating works as designed.

Per-cell costs decompose roughly as:

- Pure `Reactive` push (flat fanout): **~216 ns/cell wasm-gc, ~459 ns/cell JS**
- `Signal → Memo → Reactive` (one bridge): **~242 ns/cell wasm-gc, ~496 ns/cell JS** (memo recompute amortized across leaves; the per-cell cost is only marginally higher than flat fanout because the Memo is computed once and broadcast)
- Tree push (Memo nodes pulled by Reactive leaves): **~527 ns/cell wasm-gc, ~860 ns/cell JS** (1535 total cells; per-cell cost is higher than flat because each Memo's compute reads its parent Memo)

JS is consistently 1.6–2.4× slower than wasm-gc. The slowdown ratio is smallest on workloads dominated by Memo recompute (tree at 1.63×) — V8's JIT optimizes the hot closure bodies well — and largest on workloads dominated by push-engine machinery and short closures (sparse and flat 100 at ~2.4×). Both backends remain comfortable for 60 Hz at this scale.

## Bench-code note

Compute closures inside `Memo::new` and `Reactive::new` are already tracked contexts. **Always use `cell.get()` from inside such closures, never `rt.read(cell)`** — the latter does one-shot observer lifecycle work meant for callers outside the reactive graph, which inflates per-cell cost (an early draft of these benches used `rt.read` in the layered and tree closures; the numbers above are after the fix). This applies to any incr bench measuring push-graph throughput.

## What this *does not* measure

- **Mount/unmount cost.** Steady-state propagation only. Component mount/unmount goes through `Reactive::new` / `dispose`, and bulk-disposing 1000 leaves on a route change is unmeasured. Worth a follow-up bench if/when a UI library prototype goes beyond steady-state.
- **Browser context.** The JS numbers come from Node's V8 isolate, not a browser tab. Real browsers add compositor competition, GC pressure from DOM allocation, and throttled background tabs. The 2× safety margin on the worst-case tree shape is comfortable for that, but if a UI library bench in a real browser tab shows >5 ms steady-state, re-investigate.
- **Continuous interaction.** A single `signal.set` per iteration is the unit. Animation-frame-driven patterns (`requestAnimationFrame` writing to a signal every 16 ms) aren't tested directly, but the per-update cost numbers extrapolate trivially.

## Decision

**The push engine handles UI-shaped workloads with comfortable headroom on both wasm-gc and JS at the 1000-node scale.** Any UI library design built on incr can pick its shape (fine-grained reactive, VDOM-with-memoization, two-tree hybrid, Datalog-driven views) based on API ergonomics rather than performance fear.

This bench is kept committed as a regression baseline. Numbers should stay within roughly ±20% of the values above on the same backend; larger swings warrant investigation. The sparse-mutation row is the most sensitive — it's checking subscriber-gating correctness, not just throughput, so a regression there would indicate a real change in dispatch semantics.

## Reproduce

```bash
# wasm-gc (default)
moon bench --release -p dowdiness/incr/tests -f ui_shape_bench_test.mbt

# JS backend
moon bench --release --target js -p dowdiness/incr/tests -f ui_shape_bench_test.mbt
```
