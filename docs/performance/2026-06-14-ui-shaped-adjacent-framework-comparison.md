# UI-shaped adjacent-framework comparison plan — 2026-06-14

Issue [#257] asks for a shared benchmark plan, plus at least one measured slice
or a documented blocker, before `incr_tea` copies Rabbita, Luna, or Qwik-style
runtime ideas. This is a dated snapshot, not a replacement for the existing
`incr_tea` baselines.

## Why this exists

The current measurements are useful but internal:

- [2026-06-10 Incremental TEA vs dirty-cell baseline](2026-06-10-incr-tea-vs-dirty-cell-benches.md)
  compares `incr_tea` with a modeled dirty-cell renderer, not real Rabbita.
- [2026-06-12 Incremental TEA keyed DOM applier](2026-06-12-incr-tea-keyed-dom-applier-playwright.md)
  compares keyed reuse with a non-keyed `incr_tea` rebuild path, not Rabbita or
  Luna.
- [2026-06-12 Incremental TEA keyed planner optimization](2026-06-12-incr-tea-keyed-planner-optimization.md)
  measures the keyed planner optimization, not adjacent frameworks.

Per `moonbit-perf-investigation`, this comparison should produce evidence before
any direct-DOM, island-activation, or alternative-VDOM design is prioritized.

## Systems under comparison

| System | Local package used for this snapshot | Runtime shape to respect |
|---|---|---|
| `incr_tea` | `examples/incr_tea` | `@incr.InputField` model state, `Derived` watched roots, closure-free `Html : Eq`, browser renderer flushes. |
| Rabbita | `moonbit-community/rabbita@0.12.3` | TEA cells, dirty-cell flags, Rabbita `@html` values, keyed children as `Map[String, Html]`, browser VDOM diff/patch. |
| Luna | `mizchi/luna@0.23.0` | Fine-grained signals/resources, direct DOM updates for dynamic leaves, VNode/island abstractions, JS/browser target. |

The dependencies are pinned only in `examples/incr_tea`; no demo-only UI package
was added to core `dowdiness/incr`.

## Shared workload plan

| Workload | State shape | Operation matrix | Fair measurement slices | Caveats |
|---|---|---|---|---|
| Counter | one displayed count plus one unrelated field | increment displayed count; mutate unrelated field; initial mount | pure view build; mounted update+flush; bundle size | `incr_tea` can skip unrelated view reads; Rabbita only skips at cell boundaries; Luna updates one dynamic text leaf. |
| Keyed list | N rows with stable ids, label, and an uncontrolled input | prepend one; remove first; reverse; same-key text edit | pure view build; browser DOM operation+flush; focus/identity checks | Rabbita keyed children are `Map[String, Html]`, while `incr_tea` uses ordered keyed arrays. Luna needs a real keyed/`for_each` DOM path before reorder identity is comparable. |
| 100×100 grid | 10,000 cells with selected/dirty/error classes | edit one visible cell; select another cell; update hidden/dependent cell | browser DOM update; pure view build; bundle size | Must separate data-engine recomputation from renderer cost. A sparse visible slice may be fairer than full-grid rebuilds. |
| Hidden/visible panel | visible root plus hidden details/diagnostics | mutate hidden detail while closed; open; close; mutate while open | startup/activation; watched-root lifetime; DOM update | This is the key workload for #255 island activation, but requires explicit root/watch ownership semantics per framework. |
| Editor-shaped tree | semantic rows with stable ids, selection, diagnostics, inspector root | local text edit; move row; change diagnostics; change selection | browser DOM update; focus/selection invariants; recompute counters | Best final workload for Canopy, but only after the smaller counter/list/panel harnesses agree on measurement boundaries. |

Each workload should record four separate classes of evidence:

1. **Pure view/value construction** — MoonBit `moon bench --target js`; no DOM.
2. **Browser DOM update** — Playwright/Chromium wall time, hidden host attached
   to `document`, operation plus framework flush.
3. **Startup/activation** — mount/hydrate/island activation and first usable
   interaction.
4. **Bundle size** — release JS artifact size, separately minified/gzipped when
   comparing user cost.

Do not mix those numbers into one ranking. A system can win pure construction and
lose DOM patching, or vice versa.

## First measured slice: pure counter/list view construction

This snapshot adds `examples/incr_tea/ui_compare_bench_wbtest.mbt`, a small
`moon bench` slice that builds equivalent counter and list-shaped view values in
all three systems.

### What is measured

- `incr_tea`: closure-free `Html[String]` values using the same list row shape as
  `dom_bench_keyed_list` (`li > span + input` with a pure `on_input` descriptor).
- Rabbita: real `@rabbita_html` wrappers, a dummy `Emit[String]`, closure-valued
  events, and keyed children through `Map[String, @rabbita.Html]`.
- Luna: `@luna.h` / `@luna.text` VNodes with static attributes and no-op unit
  event handlers. The list carries `data-key` attributes, but this pure slice
  does **not** exercise Luna keyed reconciliation or direct DOM effects.

### What is not measured

- no real DOM creation, patching, focus retention, or browser paint;
- no Rabbita dirty-cell scheduling or VDOM patch loop;
- no Luna signal propagation, `render_vnode_to_dom`, or direct dynamic-leaf patch;
- no `@incr` `Derived` verification or watched-root skip path.

So this slice answers only: "what is the cost to construct an equivalent
UI-shaped value in each local API?" It is useful scaffolding for the shared
harness, not enough to choose #254/#255/#256.

## Environment

| | |
|---|---|
| Date | 2026-06-14 |
| CPU | AMD Ryzen 7 6800H (WSL2), 8 vCPU |
| Toolchain | moon 0.1.20260608 / moonc v0.10.0+e66899a54 |
| JS runtime | Node v24.14.1 |
| Packages | `moonbit-community/rabbita@0.12.3`, `mizchi/luna@0.23.0` |
| Command | `NEW_MOON_MOD=0 moon bench --release -p examples/incr_tea -f ui_compare_bench_wbtest.mbt --target js` |

The command was run twice after `NEW_MOON_MOD=0 moon check -p examples/incr_tea --deny-warn`.
The tables below use the second run.

## Results

### Counter pure view build

| System | Mean |
|---|---:|
| `incr_tea` | 163 ns ± 4.1 ns |
| Rabbita | 1.19 µs ± 0.027 µs |
| Luna | 95 ns ± 4.3 ns |

### Keyed/list-shaped pure view build

| N | `incr_tea` | Rabbita | Luna |
|---:|---:|---:|---:|
| 16 | 2.75 µs ± 0.046 µs | 22.57 µs ± 0.184 µs | 1.94 µs ± 0.086 µs |
| 64 | 11.07 µs ± 0.269 µs | 89.17 µs ± 0.815 µs | 7.70 µs ± 0.153 µs |
| 256 | 45.80 µs ± 1.10 µs | 376.13 µs ± 11.45 µs | 32.42 µs ± 0.783 µs |

## Interpretation

1. **Pure view construction is not the bottleneck that decides the runtime
   direction.** Even the largest measured `incr_tea` value build is ~46 µs; the
   prior browser DOM applier snapshot measured hundreds of microseconds per
   operation at N=256. The next comparison must move into a browser harness.
2. **Rabbita's value construction is heavier in this slice, but that is not a
   Rabbita runtime verdict.** The measurement includes `Map[String, Html]` keyed
   children and closure-valued event handlers, while Rabbita's real advantage is
   dirty-cell scheduling plus VDOM patching at mounted cell boundaries.
3. **Luna's VNode construction is cheap here, but direct DOM remains unmeasured.**
   The Luna row is a VNode with a `data-key` attribute and a no-op handler; it is
   not a keyed-list DOM identity test. Luna's relevant claim is dynamic leaf DOM
   locality, which needs `render_vnode_to_dom` plus signal updates in a real
   document or jsdom-backed benchmark.
4. **No new optimization priority follows from this slice alone.** It does not
   justify direct leaf patching (#254), island activation (#255), or WebComponent
   boundaries (#256). It just confirms that the comparison harness can import and
   build all three systems from example-local dependencies.

## Concrete guidance for follow-up work

- **Next measured slice:** extend the existing Playwright DOM harness to mount a
  counter in all three systems, then time displayed-count updates and unrelated
  updates. This is the smallest browser slice that can separate `incr_tea`
  backdating, Rabbita dirty-cell rerendering, and Luna dynamic text patching.
- **Then keyed list:** port the current `bench-keyed-dom.mjs` operation matrix
  (`prepend`, `remove-first`, `reverse`, N=16/64/256) to Rabbita and Luna. Record
  focus/identity caveats instead of forcing false equivalence.
- **Only after those:** use hidden/visible panel results to decide whether #255
  Watch activation islands deserve implementation, and use leaf-update results to
  decide whether #254 direct DOM patching is worth prototyping.

## Reproduction

```bash
NEW_MOON_MOD=0 moon update
NEW_MOON_MOD=0 moon check -p examples/incr_tea --deny-warn
NEW_MOON_MOD=0 moon bench --release -p examples/incr_tea \
  -f ui_compare_bench_wbtest.mbt --target js
```

For Rabbita and Luna API context, the benchmark was grounded in:

- `.mooncakes/moonbit-community/rabbita/README.mbt.md`
- `.mooncakes/moonbit-community/rabbita/html/README.mbt.md`
- `.mooncakes/moonbit-community/rabbita/internal/runtime/README.mbt.md`
- `mizchi/luna@0.23.0` README and `src/README.md` fetched via the Moon registry
- `mizchi/luna@0.23.0/src/_bench/dom_bench.mbt`

[#257]: https://github.com/dowdiness/incr/issues/257
