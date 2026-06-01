# Graph-Editor Recompute Path Benches

**Date:** 2026-06-01

**Backends:** wasm-gc (default), JS (Node + V8)

**Fixture/bench files:** [`tests/graph_editor_fixture_test.mbt`](../../incr/tests/graph_editor_fixture_test.mbt), [`tests/graph_editor_bench_test.mbt`](../../incr/tests/graph_editor_bench_test.mbt)

**Question:** For a future node-graph editor, how should `incr` consumers separate durable document recomputation from high-frequency ephemeral UI state such as hover, drag preview, pan, and zoom?

## Fixture

The benchmark models one graph document input and three UI inputs:

```text
Input[GraphDocument]       durable nodes, edges, parameters, committed positions
Input[Int]                 hovered/selected node for a sparse inspector
Input[GraphDrag]           live drag preview delta
Input[GraphViewport]       pan/zoom
```

The coarse full-render pipeline is the target-facade shape:

```text
Input[GraphDocument]
  -> Derived[validation]
  -> Derived[normalization]
  -> Derived[lowering]
  -> Derived[render]
       reads Input[GraphDrag] + Input[GraphViewport]
  -> Watch[render]
```

The per-node full-render pipeline keeps coarse validation/normalization, then replaces the coarse lowering stage with `DerivedMap[Int, GraphLoweredNode]`. Its render terminal still reads every node.

The sparse inspector pipeline uses the same validation/normalization plus `DerivedMap`, but mounts a child-scope `ReachableDerived` inspector that reads only the hovered node. It does not read drag or viewport inputs.

Each constructor primes the terminal `Watch` and runs `Runtime::gc()` before timing.

## Recompute records

Counts are derived closure executions after the priming read. They are pinned by tests in the fixture file.

| Operation | Terminal | validation | normalization | coarse lowering | per-node lowering | render | inspector |
|---|---|---:|---:|---:|---:|---:|---:|
| parameter edit | coarse full render | 1 | 1 | 1 | 0 | 1 | 0 |
| node add | coarse full render | 1 | 1 | 1 | 0 | 1 | 0 |
| node delete | coarse full render | 1 | 1 | 1 | 0 | 1 | 0 |
| edge connect | coarse full render | 1 | 1 | 1 | 0 | 1 | 0 |
| edge disconnect | coarse full render | 1 | 1 | 1 | 0 | 1 | 0 |
| viewport pan/zoom | coarse full render | 0 | 0 | 0 | 0 | 1 | 0 |
| live drag preview, 5 frames | coarse full render | 0 | 0 | 0 | 0 | 5 | 0 |
| `MoveNodes` commit at gesture end | coarse full render | 1 | 1 | 1 | 0 | 1 | 0 |
| hover change | sparse inspector | 0 | 0 | 0 | 1 | 0 | 1 |
| viewport pan/zoom | sparse inspector | 0 | 0 | 0 | 0 | 0 | 0 |
| drag preview | sparse inspector | 0 | 0 | 0 | 0 | 0 | 0 |
| parameter edit | sparse inspector | 1 | 1 | 0 | 1 | 0 | 1 |

The live-drag path updates only `Input[GraphDrag]`; durable validation, normalization, and lowering do not execute until the final durable `MoveNodes` commit.

## Measurements

10 internal iterations per bench; mean ± σ. Values are per operation except the live-drag rows, which measure one 60-frame preview sequence.

| Nodes | Shape / operation | wasm-gc | JS (Node v8) |
|---:|---|---:|---:|
| 100 | coarse parameter edit + full render | 7.39 µs ± 0.24 µs | 10.57 µs ± 0.86 µs |
| 1000 | coarse parameter edit + full render | 61.65 µs ± 2.20 µs | 86.95 µs ± 5.81 µs |
| 100 | per-node `DerivedMap` parameter edit + full render | 50.18 µs ± 2.11 µs | 78.55 µs ± 0.35 µs |
| 1000 | per-node `DerivedMap` parameter edit + full render | 610.95 µs ± 11.35 µs | 1.04 ms ± 92.92 µs |
| 100 | `ReachableDerived` sparse inspector parameter edit | 4.55 µs ± 0.05 µs | 6.90 µs ± 0.61 µs |
| 1000 | `ReachableDerived` sparse inspector parameter edit | 33.07 µs ± 1.40 µs | 54.52 µs ± 1.01 µs |
| 1000 | coarse viewport pan/zoom + full render | 11.11 µs ± 0.04 µs | 11.62 µs ± 0.13 µs |
| 1000 | per-node `DerivedMap` viewport pan/zoom + full render | 227.58 µs ± 6.81 µs | 401.62 µs ± 12.33 µs |
| 1000 | `ReachableDerived` sparse inspector hover change | 1.27 µs ± 0.04 µs | 2.42 µs ± 0.10 µs |
| 1000 | coarse live drag preview, 60 full-render frames | 694.98 µs ± 4.79 µs | 672.92 µs ± 6.44 µs |
| 1000 | per-node `DerivedMap` live drag preview, 60 full-render frames | 14.35 ms ± 237.46 µs | 23.11 ms ± 227.38 µs |
| 1000 | coarse `MoveNodes` commit + full render | 58.42 µs ± 0.51 µs | 81.46 µs ± 0.56 µs |

## Interpretation

For full-canvas reads, keep the durable graph path coarse. At 1000 nodes, per-node `DerivedMap` is about 9.9× slower on wasm-gc and 12.0× slower on JS for a parameter edit because the terminal still reads every key and pays one memo boundary per node.

`DerivedMap` becomes useful for sparse visible surfaces. The inspector reads one key, so a 1000-node parameter edit is faster than the coarse full render while still sharing whole-document validation/normalization. Hover-only inspector updates are effectively constant-size.

For high-frequency ephemeral state, split the UI inputs by consumer. Viewport and drag updates invalidate the render terminal, but they do not execute validation, normalization, or durable lowering. The 60-frame live-drag benchmark stays around 0.69 ms total on wasm-gc and 0.67 ms on JS for the coarse full-render path. The final durable `MoveNodes` commit costs about the same as any other durable document edit.

Do not use per-node `DerivedMap` for a full-canvas render during live pointer movement. The per-node full-render live-drag path spends 14.35 ms on wasm-gc and 23.11 ms on JS for the same 60 frames solely from per-key read overhead.

## Recommended target-facade pattern

Use one long-lived `Scope`, separate durable and ephemeral inputs, named derived stages, and a primed terminal `Watch`:

```text
let document = scope.input(initial_document, label="graph.document")
let drag = scope.input(idle_drag, label="graph.drag_preview")
let viewport = scope.input(initial_viewport, label="graph.viewport")

let validated = scope.derived(() => validate(document.get()), label="graph.validation")
let normalized = scope.derived(
  () => normalize(validated.get_or_abort()),
  label="graph.normalization",
)
let lowered = scope.derived(
  () => lower(normalized.get_or_abort()),
  label="graph.lowering",
)
let render = scope.derived(
  () => render(lowered.get_or_abort(), drag.get(), viewport.get()),
  label="graph.render",
)
let watch = scope.add_watch(render.watch())
ignore(watch.read_or_abort())
runtime.gc()
```

Mount sparse panels in child scopes with `ReachableDerived` and introduce `DerivedMap` only for keyed work that a visible surface reads sparsely. Keep viewport/drag inputs out of inspector closures unless the panel actually needs them.

No new public API is needed for this pattern.

## Reproduce

```bash
# wasm-gc (default)
moon bench --release -p dowdiness/incr/tests -f graph_editor_bench_test.mbt

# JS backend
moon bench --release --target js -p dowdiness/incr/tests -f graph_editor_bench_test.mbt
```
