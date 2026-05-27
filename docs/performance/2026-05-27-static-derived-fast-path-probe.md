# Static/Applicative Derived Fast-Path Probe

**Date:** 2026-05-27

**Last rerun:** 2026-05-28, after private hardening

**Backends:** wasm-gc (default), JS (Node + V8)

**Bench files:** [`tests/static_derived_probe_bench_test.mbt`](../../tests/static_derived_probe_bench_test.mbt), [`cells/static_derived_integrated_probe_bench_wbtest.mbt`](../../cells/static_derived_integrated_probe_bench_wbtest.mbt), [`cells/static_derived_ui_shape_bench_wbtest.mbt`](../../cells/static_derived_ui_shape_bench_wbtest.mbt)

**Question:** Does a fixed-dependency `Derived` path have enough measured headroom to justify a private generalized engine prototype?

## Why this exists

The constructive-traces feasibility study rejected constructive traces as the default latency optimization for local editor/UI workloads. Its more actionable near-term lead was the applicative-vs-monadic distinction: many UI-shaped derived values have fixed dependencies and do not need dynamic dependency discovery on every recompute.

This probe measures that idea before designing any public API. The lower-bound benches compare today's dynamically tracked `Derived` against manual fixed-dependency recomputation. The integrated prototype installs a real pull backend entry (`MemoData` / `PullMemo`) with fixed dependencies, real subscriber links, existing `pull_verify`, existing commit hooks, and no dynamic tracking frame or dependency diff during recompute.

## Measurements

10 internal iterations per bench; mean only, in nanoseconds per stale recompute. The dynamic `Derived` and manual lower-bound rows come from `tests/static_derived_probe_bench_test.mbt`; the generalized static prototype rows come from `cells/static_derived_integrated_probe_bench_wbtest.mbt`.

| Backend | Shape | Dynamic `Derived` lower-bound row | Manual lower bound | Dynamic `Derived` integrated row | Generalized static prototype |
|---|---:|---:|---:|---:|---:|
| wasm-gc | map1 | 284 ns | 55 ns | 300 ns | 187 ns |
| wasm-gc | map2 | 346 ns | 64 ns | 360 ns | 198 ns |
| wasm-gc | map3 | 417 ns | 75 ns | 401 ns | 202 ns |
| JS | map1 | 444 ns | 55 ns | 459 ns | 249 ns |
| JS | map2 | 509 ns | 58 ns | 572 ns | 287 ns |
| JS | map3 | 532 ns | 63 ns | 564 ns | 268 ns |

## Interpretation

The lower-bound gap is large enough to matter for tiny UI computations: dynamic tracking costs roughly 228–469 ns more than direct fixed-dependency recomputation in these shapes.

The generalized prototype does not merely win against an artificial baseline. It keeps the current pull scheduler, graph metadata, and commit-hook pairing, yet saves:

| Backend | Shape | Static vs integrated dynamic `Derived` | Dynamic/manual gap recovered by static prototype |
|---|---:|---:|---:|
| wasm-gc | map1 | 1.60× faster, -113 ns | 46% |
| wasm-gc | map2 | 1.82× faster, -162 ns | 55% |
| wasm-gc | map3 | 1.99× faster, -199 ns | 61% |
| JS | map1 | 1.84× faster, -210 ns | 52% |
| JS | map2 | 2.00× faster, -285 ns | 55% |
| JS | map3 | 2.10× faster, -295 ns | 59% |

The remaining distance to the manual lower bound is still material: about 127–134 ns on wasm-gc and 194–229 ns on JS. That residual is the cost of staying inside the real runtime path: cell lookup, revision checks, dependency verification, `Result` plumbing, closure dispatch, typed cache storage, and commit-hook pairing. It is acceptable for a private engine prototype because the generalized path still recovers about half or more of the theoretical headroom without bypassing the graph.

## UI-Shape Follow-Up

After the generalized scalar probe, `cells/static_derived_ui_shape_bench_wbtest.mbt` adds private static variants for the two UI-shape benches that actually contain derived nodes. Flat and sparse shapes are input-to-eager only, so they have no fixed-derived variant.

| Backend | Shape | Dynamic `Derived` | Static private `Derived` | Change |
|---|---:|---:|---:|---:|
| wasm-gc | layered 1000 eager leaves | 231 µs | 230 µs | within noise / -1 µs |
| wasm-gc | tree 1023 derived + 512 eager leaves | 577 µs | 426 µs | 1.35× faster, -151 µs |
| JS | layered 1000 eager leaves | 372 µs | 360 µs | 1.03× faster, -12 µs |
| JS | tree 1023 derived + 512 eager leaves | 893 µs | 618 µs | 1.45× faster, -275 µs |

Interpretation: the static path barely moves the layered fanout because the one derived recompute is amortized across 1000 eager leaves; push propagation and leaf evaluation dominate. The tree shape is the stronger driver: every interior derived node is a tiny fixed-dependency recompute, so avoiding tracking and dependency diffing still removes roughly 150–275 µs from a 1535-cell update on both deployment-relevant backends.

## Decision

Proceed with a **private generalized static path**.

This is not a decision to add public `Derived::map`, `map2`, `map3`, or `Scope::derived_static`. The Int-only whitebox probe has been replaced by a package-private generalized prototype that preserves the current pull/runtime invariants. UI-shape benches show the private path matters most for tree-shaped derived graphs. The follow-up private hardening pass found no blocker to writing a public-surface **options note** next, but that note should stay at the tradeoff/options level and avoid choosing or implementing a public API.

## Smallest private engine shape

Keep the first generalized implementation private and reuse the existing pull backend machinery:

1. **No new public handle and no new `CellRef` variant.** Static derived cells remain `PullMemo` entries backed by `MemoData`, so GC, subscribers, durability checks, watches, and introspection continue to use the existing pull backend.
2. **Package-private static installer.** Use a private helper such as `static_derived_probe` or `Runtime::install_static_derived` that accepts:
   - a fixed `Array[CellId]` dependency list;
   - an untracked compute closure;
   - a backdating equality function;
   - an optional label.
3. **One-time dependency registration.** Validate same-runtime dependencies, install subscriber links once at construction, compute durability from the fixed dependency list, and never run dependency-list diffing for that cell.
4. **Static recompute epilogue.** On stale verification, run the compute closure without `push_tracking` / `pop_tracking`, compare against the cached value, update `changed_at`, `verified_at`, and `has_been_computed`, and dispatch the existing commit hooks in the same paired before/success/abort shape as dynamic `Derived` backend recompute.
5. **Narrow source readers.** For the private prototype, feed compute closures through fixed source wrappers or map-specific constructors so recompute reads only the declared dependencies. Do not expose an arbitrary closure that can silently read undeclared dependencies.
6. **No accumulator support in the first private path.** Accumulator pushes require an active tracking frame, which is exactly the overhead this path avoids. Treat accumulator use inside static recompute as unsupported until a real driver requires it.

Validation gates before any public API design:

- correctness wbtests for fixed dependency registration, subscriber cleanup, GC dependencies, cross-runtime rejection, backdating, cycle detection through fixed dependencies, and event-hook pairing;
- wasm-gc and JS benches for map1/map2/map3 after the generalized private path replaces the Int-only prototype;
- UI-shape benches using the private path to ensure the win survives outside scalar microbenches;
- no public `.mbti` drift, and no new target-facade API.

Status: map and UI-shape benches now pass this measurement gate. The private hardening pass now covers static-to-static disposal and GC traversal, duplicate fixed-dependency normalization, compute-failure hook cleanup, cycle reporting through fixed dependencies, explicit accumulator rejection, and a declared-dependency-only static source read helper. The remaining unanswered question is not whether a static path can win, but how small and safe the eventual public surface can be.

## Reproduce

```bash
# wasm-gc lower-bound probes
moon bench --release -p dowdiness/incr/tests -f static_derived_probe_bench_test.mbt

# wasm-gc integrated prototype
moon bench --release -p dowdiness/incr/cells -f static_derived_integrated_probe_bench_wbtest.mbt

# JS lower-bound probes
moon bench --release --target js -p dowdiness/incr/tests -f static_derived_probe_bench_test.mbt

# JS integrated prototype
moon bench --release --target js -p dowdiness/incr/cells -f static_derived_integrated_probe_bench_wbtest.mbt

# wasm-gc UI-shape static variants
moon bench --release -p dowdiness/incr/cells -f static_derived_ui_shape_bench_wbtest.mbt

# JS UI-shape static variants
moon bench --release --target js -p dowdiness/incr/cells -f static_derived_ui_shape_bench_wbtest.mbt
```
