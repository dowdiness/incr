# Static/Applicative Derived Fast-Path Probe

**Date:** 2026-05-27

**Last rerun:** 2026-05-31, after graduating the prototype to a package-private `Derived` path

**Backends:** wasm-gc (default), JS (Node + V8)

**Bench files:** [`tests/static_derived_probe_bench_test.mbt`](../../incr/tests/static_derived_probe_bench_test.mbt), [`cells/static_derived_integrated_probe_bench_wbtest.mbt`](../../incr/cells/static_derived_integrated_probe_bench_wbtest.mbt), [`cells/static_derived_ui_shape_bench_wbtest.mbt`](../../incr/cells/static_derived_ui_shape_bench_wbtest.mbt)

**Question:** Does a fixed-dependency `Derived` path have enough measured headroom to justify a private generalized engine path?

## Why this exists

The constructive-traces feasibility study rejected constructive traces as the default latency optimization for local editor/UI workloads. Its more actionable near-term lead was the applicative-vs-monadic distinction: many UI-shaped derived values have fixed dependencies and do not need dynamic dependency discovery on every recompute.

This probe measures that idea before designing any public API. The lower-bound benches compare today's dynamically tracked `Derived` against manual fixed-dependency recomputation. The integrated path installs a real pull backend entry (`MemoData` / `PullMemo`) with fixed dependencies, real subscriber links, existing `pull_verify`, existing commit hooks, and no dynamic tracking frame or dependency diff during recompute.

## Measurements

10 internal iterations per bench; mean only, in nanoseconds per stale recompute. The dynamic `Derived` and manual lower-bound rows come from `tests/static_derived_probe_bench_test.mbt`; the generalized static rows come from `cells/static_derived_integrated_probe_bench_wbtest.mbt`.

| Backend | Shape | Dynamic `Derived` lower-bound row | Manual lower bound | Dynamic `Derived` integrated row | Generalized static private path |
|---|---:|---:|---:|---:|---:|
| wasm-gc | map1 | 321 ns | 65 ns | 318 ns | 224 ns |
| wasm-gc | map2 | 377 ns | 81 ns | 375 ns | 242 ns |
| wasm-gc | map3 | 443 ns | 94 ns | 443 ns | 239 ns |
| JS | map1 | 494 ns | 61 ns | 495 ns | 313 ns |
| JS | map2 | 520 ns | 72 ns | 547 ns | 310 ns |
| JS | map3 | 564 ns | 77 ns | 586 ns | 311 ns |

## Interpretation

The lower-bound gap is large enough to matter for tiny UI computations: dynamic tracking costs roughly 257–487 ns more than direct fixed-dependency recomputation in these shapes.

The generalized private path does not merely win against an artificial baseline. It keeps the current pull scheduler, graph metadata, and commit-hook pairing, yet saves:

| Backend | Shape | Static vs integrated dynamic `Derived` | Dynamic/manual gap recovered by static path |
|---|---:|---:|---:|
| wasm-gc | map1 | 1.42× faster, -93 ns | 37% |
| wasm-gc | map2 | 1.55× faster, -133 ns | 45% |
| wasm-gc | map3 | 1.85× faster, -203 ns | 58% |
| JS | map1 | 1.58× faster, -182 ns | 42% |
| JS | map2 | 1.76× faster, -237 ns | 50% |
| JS | map3 | 1.89× faster, -275 ns | 54% |

The remaining distance to the manual lower bound is still material: about 145–161 ns on wasm-gc and 234–252 ns on JS. That residual is the cost of staying inside the real runtime path: cell lookup, revision checks, dependency verification, `Result` plumbing, closure dispatch, typed cache storage, and commit-hook pairing. The package-private path is weaker than the oldest standalone-handle prototype, but still acceptable because it recovers a large fraction of the theoretical headroom while returning the normal `Derived` facade and preserving normal watch/disposal semantics.

## UI-Shape Follow-Up

After the generalized scalar probe, `cells/static_derived_ui_shape_bench_wbtest.mbt` adds private static variants for the two UI-shape benches that actually contain derived nodes. Flat and sparse shapes are input-to-eager only, so they have no fixed-derived variant.

| Backend | Shape | Dynamic `Derived` | Static private `Derived` | Change |
|---|---:|---:|---:|---:|
| wasm-gc | layered 1000 eager leaves | 219 µs | 220 µs | within noise |
| wasm-gc | tree 1023 derived + 512 eager leaves | 601 µs | 543 µs | 1.11× faster, -58 µs |
| JS | layered 1000 eager leaves | 390 µs | 383 µs | within noise / 1.02× |
| JS | tree 1023 derived + 512 eager leaves | 892 µs | 719 µs | 1.24× faster, -173 µs |

Interpretation: the static path barely moves the layered fanout because the one derived recompute is amortized across 1000 eager leaves; push propagation and leaf evaluation dominate. The tree shape is the stronger driver: every interior derived node is a tiny fixed-dependency recompute, so avoiding tracking and dependency diffing still removes roughly 58 µs on wasm-gc and about 173 µs on JS from a 1535-cell update.

## Decision

Proceed with a **private generalized static path**. The 2026-05-31 implementation keeps this decision: scalar ratios remain material, and the UI tree-shaped bench still wins on both deployment-relevant targets.

This is not a decision to add public `Derived::map`, `map2`, `map3`, or `Scope::derived_static`. The Int-only whitebox probe has been replaced by a package-private generalized path that preserves the current pull/runtime invariants and returns the normal target `Derived` facade. UI-shape benches show the private path matters most for tree-shaped derived graphs. The public-surface **options note** remains at the tradeoff/options level and does not choose or implement a public API.

## Smallest private engine shape

Keep the generalized implementation private and reuse the existing pull backend machinery:

1. **No new public handle and no new `CellRef` variant.** Static derived cells remain `PullMemo` entries backed by `MemoData`, so GC, subscribers, durability checks, watches, and introspection continue to use the existing pull backend.
2. **Package-private static installer.** Use a private helper such as `static_derived` or `Runtime::install_static_derived` that accepts:
   - a fixed `Array[CellId]` dependency list;
   - an untracked compute closure;
   - a backdating equality function;
   - an optional label.
3. **One-time dependency registration.** Validate same-runtime dependencies, install subscriber links once at construction, compute durability from the fixed dependency list, and never run dependency-list diffing for that cell.
4. **Static recompute epilogue.** On stale verification, run the compute closure without `push_tracking` / `pop_tracking`, compare against the cached value, update `changed_at`, `verified_at`, and `has_been_computed`, and dispatch the existing commit hooks in the same paired before/success/abort shape as dynamic `Derived` backend recompute.
5. **Narrow source readers.** Feed compute closures through fixed source wrappers or map-specific constructors so recompute reads only the declared dependencies. Do not expose an arbitrary closure that can silently read undeclared dependencies.
6. **No accumulator support in the first private path.** Accumulator pushes require an active tracking frame, which is exactly the overhead this path avoids. Treat accumulator use inside static recompute as unsupported until a real driver requires it.

Validation gates before any public API design:

- correctness wbtests for fixed dependency registration, subscriber cleanup, GC dependencies, cross-runtime rejection, backdating, cycle detection through fixed dependencies, and event-hook pairing;
- wasm-gc and JS benches for map1/map2/map3 after the generalized private path replaces the Int-only prototype;
- UI-shape benches using the private path to ensure the win survives outside scalar microbenches;
- no public `.mbti` drift, and no new target-facade API.

Status: map and UI-shape benches pass this measurement gate. The private path now returns normal `Derived` handles while preserving static-to-static disposal and GC traversal, duplicate fixed-dependency normalization, compute-failure hook cleanup, cycle reporting through fixed dependencies, explicit accumulator rejection, declared-dependency-only source reads, `Watch` rooting, and honest `ReadError::Disposed` for direct disposed reads. The remaining unanswered question is not whether a static path can win, but how small and safe the eventual public surface can be.

## Findings to carry forward

- Treat standalone prototypes as upper bounds. The direction held after normal
  `Derived` integration, but the ratios narrowed once the path preserved normal
  handles, watches, disposal, and honest read errors.
- Prefer private engine capability before public API. This let the runtime learn
  the static/applicative path without committing to arity names, source wrapper
  shape, or `Scope` methods.
- Use the path for tree-shaped graphs of tiny fixed-dependency computations.
  Layered fanout barely moves because push propagation and eager leaves dominate.
- Always benchmark JS as well as wasm-gc. The deployment-relevant JS target can
  show a different magnitude than the default wasm-gc bench target.
- Future public surfaces should be driven by a concrete consumer, such as
  expression/formula lowering or a scope-owned attachment pipeline. Dynamic
  dependencies and accumulator reads should continue to use ordinary `Derived`.

## Reproduce

```bash
# wasm-gc lower-bound probes
moon bench --release -p dowdiness/incr/tests -f static_derived_probe_bench_test.mbt

# wasm-gc integrated private path
moon bench --release -p dowdiness/incr/cells -f static_derived_integrated_probe_bench_wbtest.mbt

# JS lower-bound probes
moon bench --release --target js -p dowdiness/incr/tests -f static_derived_probe_bench_test.mbt

# JS integrated private path
moon bench --release --target js -p dowdiness/incr/cells -f static_derived_integrated_probe_bench_wbtest.mbt

# wasm-gc UI-shape static variants
moon bench --release -p dowdiness/incr/cells -f static_derived_ui_shape_bench_wbtest.mbt

# JS UI-shape static variants
moon bench --release --target js -p dowdiness/incr/cells -f static_derived_ui_shape_bench_wbtest.mbt
```
