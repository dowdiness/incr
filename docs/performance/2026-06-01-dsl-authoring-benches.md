# DSL-Shaped Authoring Pipeline Benches

**Date:** 2026-06-01

**Backends:** wasm-gc (default), JS (Node + V8)

**Bench file:** [`tests/dsl_authoring_bench_test.mbt`](../../tests/dsl_authoring_bench_test.mbt)

**Question:** For editor/control-side DSL authoring pipelines, should a facade start with coarse staged `Derived` recomputation or pay the complexity of per-node `DerivedMap` caching?

## Fixture

Each iteration applies one source edit that changes one node, then reads a primed terminal `Watch`. Constructors prime the terminal watch and run `Runtime::gc()` before timing so the measurements use the long-lived authoring shape documented in the cookbook rather than first-touch or GC-survival effects.

The coarse fixture is the target-facade recipe:

```text
Input[DslSource]
  -> Derived[parse]
  -> Derived[projection]
  -> Derived[semantic]
  -> Derived[normalized]
  -> Derived[lowered]
  -> Derived[terminal]
  -> Watch[terminal]
```

The per-node full-terminal fixture keeps coarse parse/projection stages, then uses one `DerivedMap[Int, Int]` for per-node semantic/normalize/lower work. Its terminal still reads every node.

The sparse inspector fixture uses the same parse/projection + `DerivedMap` cache but mounts one child-scope `ReachableDerived` inspector panel and watches only the selected node.

This is explicitly an authoring/control-side benchmark. It does not imply parser, projection, semantic, or lowering work belongs in an audio callback.

## Measurements

10 internal iterations per bench; mean ± σ. Values are per source edit plus terminal watch read.

| Nodes | Shape | wasm-gc | JS (Node v8) |
|---:|---|---:|---:|
| 20 | coarse staged terminal | 2.40 µs ± 0.04 µs | 5.03 µs ± 0.38 µs |
| 20 | per-node `DerivedMap`, full terminal | 7.83 µs ± 0.20 µs | 16.42 µs ± 0.34 µs |
| 20 | `ReachableDerived` sparse inspector | 1.42 µs ± 0.03 µs | 2.65 µs ± 0.03 µs |
| 100 | coarse staged terminal | 5.50 µs ± 0.08 µs | 14.17 µs ± 1.43 µs |
| 100 | per-node `DerivedMap`, full terminal | 37.08 µs ± 0.29 µs | 76.35 µs ± 0.89 µs |
| 100 | `ReachableDerived` sparse inspector | 2.47 µs ± 0.02 µs | 4.61 µs ± 0.13 µs |
| 500 | coarse staged terminal | 20.30 µs ± 0.17 µs | 50.33 µs ± 4.68 µs |
| 500 | per-node `DerivedMap`, full terminal | 210.73 µs ± 4.48 µs | 410.52 µs ± 20.18 µs |
| 500 | `ReachableDerived` sparse inspector | 7.37 µs ± 0.36 µs | 15.44 µs ± 0.87 µs |
| 1000 | coarse staged terminal | 39.27 µs ± 0.25 µs | 90.57 µs ± 12.95 µs |
| 1000 | per-node `DerivedMap`, full terminal | 493.66 µs ± 34.23 µs | 860.52 µs ± 19.75 µs |
| 1000 | `ReachableDerived` sparse inspector | 13.42 µs ± 0.17 µs | 29.10 µs ± 0.22 µs |

## Interpretation

For full-terminal authoring reads, coarse staged recomputation is the right default. At 1000 nodes, the per-node `DerivedMap` variant is about 12.6× slower on wasm-gc and 9.5× slower on JS because the terminal still verifies/reads every cached key and pays one memo boundary per node.

Per-node caching becomes useful only when the visible surface is sparse. The `ReachableDerived` inspector reads one selected node while still sharing coarse parse/projection work. At 1000 nodes it is about 2.9× faster than the coarse full terminal on wasm-gc and 3.1× faster on JS. It is still not O(1): parse/projection remain whole-source stages, so this shape is a panel/inspector optimization, not a replacement for the coarse pipeline.

The malformed-input / last-good-value variant is intentionally not included here. The cookbook literate test already pins that facade behavior; adding it to this microbench would mostly measure extra domain `Result` branching and last-good boundary state, not a new recomputation granularity. Add a separate benchmark only if diagnostics or last-good publishing becomes a measured concern.

## Decision

Start DSL authoring facades with named coarse `Derived` stages and a primed terminal `Watch`. Introduce `DerivedMap` for per-node semantic/lowering work only after a concrete measured surface reads a sparse subset, such as a visible inspector panel. Do not use these authoring/control-side numbers to justify realtime audio-thread recomputation.

## Reproduce

```bash
# wasm-gc (default)
moon bench --release -p dowdiness/incr/tests -f dsl_authoring_bench_test.mbt

# JS backend
moon bench --release --target js -p dowdiness/incr/tests -f dsl_authoring_bench_test.mbt
```
