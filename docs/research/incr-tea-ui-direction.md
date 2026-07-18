# Incremental TEA direction after Rabbita, Qwik, and Luna comparison

`examples/incr_tea` is an experimental renderer for answering one question: what
happens when a TEA-style UI is driven by `incr` dependency tracking instead of a
coarse dirty-component signal? It should stay a research substrate for semantic
incremental UI, not become a general-purpose Rabbita or Luna replacement.

## Comparison summary

| System | Primary goal | Update model | Best fit |
|---|---|---|---|
| Rabbita | Practical MoonBit TEA framework | Dirty `Cell` boundaries plus VDOM diff/patch | Ordinary MoonBit web apps that need ergonomic HTML, commands, subscriptions, DOM/HTTP support |
| `incr_tea` | Measure and prototype UI on top of `@incr` | `InputField` reads tracked by `Derived` view roots; `Watch` + `Html : Eq` backdating decide recompute/patch | Editor-shaped UI where most changes touch a small semantic slice |
| Qwik | Web app startup performance through resumability | Server-serialized listener/state/reactivity metadata plus lazy QRL-loaded handlers/signals | SSR/SSG TypeScript apps where avoiding hydration and initial JS is central |
| Luna UI | MoonBit/JS fine-grained UI plus islands | Signals/effects/memos update DOM directly; islands hydrate on load/idle/visible/media/manual triggers | MoonBit UI apps that want Solid-style reactivity, partial hydration, and WebComponent boundaries |

The overlap is real but limited. All four care about not doing unnecessary UI
work. They optimize different bottlenecks:

- Rabbita optimizes authoring and avoids work at explicit `Cell` boundaries.
- `incr_tea` optimizes post-startup local updates by proving which view roots
  actually read changed inputs.
- Qwik optimizes startup by avoiding eager hydration and by lazy-loading handlers
  only when interaction requires them.
- Luna optimizes runtime DOM locality and activation cost with fine-grained
  signals, direct DOM updates, and island hydration triggers.

## Direction

The durable goal for `incr_tea` is:

> A semantic incremental rendering substrate where stable semantic IDs preserve
> DOM identity, and `@incr` dependency tracking skips view recomputation and DOM
> patching for unrelated model changes.

This points toward projectional/editor workloads rather than generic todo apps.
The motivating UI should include semantic identity, focus/selection retention,
viewports, diagnostics, hover/inspector panels, and CRDT/editor state updates
where most state changes are local.

## What to borrow

### From Rabbita

Borrow the authoring ergonomics, not the runtime model wholesale:

- wrapper-style HTML authoring and optional parameters;
- an Eq-safe attribute-builder escape hatch for common editor/demo attributes;
- keyed-child conventions based on stable business IDs;
- TEA vocabulary (`Model`, `Msg`, `update`, `view`, `Cmd`, subscriptions);
- post-render command boundaries for DOM effects such as inline-editor focus.

Do **not** copy closure-valued event handlers into `Html`. `incr_tea` relies on
`Html : Eq` for backdating, so event descriptors must stay pure data and DOM
payload extraction must stay at the renderer boundary. The #249 slice extends
that rule with typed text-input, keyboard, and pointer payload ids/resolvers; the
#270 slice extends the same pattern to submit/focus/blur/double-click descriptors
and payload-dependent keyboard actions. The #248 slice adds attribute/list
ergonomics without changing the event boundary.

### From Qwik

Borrow the boundary discipline, not the full Qwik runtime:

- handler/listener references should be serializable or at least pure data;
- browser activation should happen at explicit lazy boundaries;
- avoid assuming every handler or component must be eagerly materialized;
- keep enough metadata around to resume work without walking the whole UI tree.

Do **not** make Qwik-style resumability a near-term requirement. Qwik solves
SSR/hydration and initial-JS costs; `incr_tea` is currently validating runtime
locality. The right near-term work is to keep `Html` and event descriptors
serializable-friendly, then research resumability separately. Follow-up: [#252].

### From Luna UI

Borrow the runtime-locality and island-boundary ideas, not a generic signal UI
framework:

- direct DOM updates are worth studying for hot leaf paths;
- island activation triggers map well to visible/collapsed/idle editor panels;
- WebComponent/custom-element boundaries may clarify host integration;
- shared Rabbita/Luna/`incr_tea` benchmarks can prevent design-by-slogan.

Do **not** make "no VDOM" a goal by itself. `incr_tea`'s cacheable `Html` value
is useful because it gives `Html : Eq`, deterministic skip decisions, and
backdating. A Luna-inspired direct patch path should start as a measured leaf
optimization while the existing value-level renderer remains the baseline.
Follow-ups: [#254], [#255], [#256], [#257].

## Post-matrix locality lessons

The mounted matrix snapshot in
[`docs/performance/2026-06-14-mounted-matrix-adjacent-framework-comparison.md`](../performance/2026-06-14-mounted-matrix-adjacent-framework-comparison.md)
and the row/leaf locality follow-up in
[`docs/performance/2026-06-14-mounted-row-leaf-locality-comparison.md`](../performance/2026-06-14-mounted-row-leaf-locality-comparison.md)
update the research priorities:

- **Counter and initial mount remain non-drivers.** All systems stay in the
  tens-of-microseconds range for tiny counters, so counter mount/leaf updates
  should not decide renderer architecture.
- **List/row/leaf locality is now the direct-patching gate.** `incr_tea` beats
  Rabbita on the comparable N=256 keyed-list rows, while Luna's direct DOM
  path is still much faster. The follow-up row/leaf snapshot isolates same-order
  row text/class changes and hot nested text leaves: `incr_tea` lands around
  141–143 µs at N=256, Rabbita around 1.49–1.54 ms, and Luna around 3–4 µs.
- **Activation islands are not justified by collapsed conditionals, but
  DOM-present hidden subtrees now have a measured cost.** Closed panel and
  collapsed workspace updates are already single-digit to low-teens microseconds
  in `incr_tea`; the #255 workspace-island slice shows hidden-mounted editor-shaped
  updates at hundreds of microseconds when the DOM stays present and watched.
- **Raw closures should stay out of cacheable `Html`.** Closure-like ergonomics
  are welcome only when they lower to pure `Eq`/serializable descriptors. Live
  callbacks, watches, DOM payload extraction, and live `preventDefault` /
  `stopPropagation` calls belong at the renderer/mount boundary so `Html : Eq`
  and backdating remain meaningful.

## Direct leaf prototype result

The #254 prototype is recorded in
[`docs/performance/2026-06-15-incr-tea-direct-leaf-patching-prototype.md`](../performance/2026-06-15-incr-tea-direct-leaf-patching-prototype.md).
It adds an experimental `incr_tea-direct` row/leaf benchmark path where `Html`
stores only pure direct text/attribute ids and fallback values. The live
`Watch[String]` leaves are resolved through renderer/benchmark-boundary callbacks,
not stored in `Html`.

At N=256, the direct path lands around 4.4–4.7 µs for row text, row class, and
hot nested text leaves versus the existing `incr_tea` path around 152–161 µs in
the same run. Treat this as evidence that leaf subscription locality is valuable,
not as a reason to discard the ordinary `Html : Eq` renderer: structural list
edits, keyed identity/focus semantics, and general changed views still use the
existing diff path.

## Activation-islands measurement result

The #255 measurement gate is recorded in
[`docs/performance/2026-06-15-incr-tea-activation-islands-measurement.md`](../performance/2026-06-15-incr-tea-activation-islands-measurement.md).
It adds an editor/sidebar/inspector-shaped `workspace-island` browser benchmark
without changing activation semantics. Collapsed updates stay flat at roughly
8–14 µs for `incr_tea`, while hidden-mounted updates with the subtree still in
the DOM cost roughly 104 µs at N=64, 297 µs at N=256, and 617 µs at N=512.

That narrows the #255 prototype target: only DOM-preserving inactive roots or
panels justify visibility/idle/manual `Watch` activation experiments. Ordinary
collapsed conditionals should keep using the current dynamic-dependency skip.
The first prototype adds `BrowserRenderer::deactivate` / `activate`: inactive
roots remain mounted with DOM attached and their `Program`/`Watch` alive, but
scheduled frames skip their watched-view reads until activation performs one
catch-up flush. The first prototype benchmark is recorded in
[`docs/performance/2026-06-15-incr-tea-inactive-root-prototype.md`](../performance/2026-06-15-incr-tea-inactive-root-prototype.md): inactive updates stay around 4–7 µs across N=64/256/512, while activation catch-up pays the deferred visible-scale flush once. The amortized follow-up is recorded in
[`docs/performance/2026-06-15-incr-tea-inactive-root-amortized.md`](../performance/2026-06-15-incr-tea-inactive-root-amortized.md): 1000 inactive updates plus activation measured roughly 3.8–4.2 ms across N=64/256/512.

## Controlled form-property gate (#286)

The #286 slice is accepted as a renderer-boundary contract, not a generic DOM
property system. `Html` remains closure-free and `Eq`-comparable: `value` is
controlled only for `<input>` and `<select>`, boolean helpers explicitly opt
into `checked`/`disabled`/`selected`, and `on_change(tag=...)` resolves browser
values at `BrowserRenderer::mount`. Select repair is post-order so option
children cannot override the parent-controlled value.

The browser smoke fixture covers non-first initial values, a value change,
same-render option addition, date/range controls, equal-view drift repair, node
identity, and the selected-property interaction. This is sufficient evidence
for the current boundary. Do not widen `attr("value", ...)` to `<textarea>`,
contenteditable, or custom elements without a concrete consumer and a new
semantics decision; ergonomic select/option/date/range constructors remain a
separate API follow-up.

## Near-term roadmap

1. **Keep the current renderer safe to evolve.** The keyed DOM browser baseline
   now lives in `examples/incr_tea/scripts/test-keyed-dom.mjs` and runs with
   `npm run test:dom`: it pins row identity, uncontrolled input retention,
   unchanged-list and same-order local-edit focus retention, and focus loss when
   the focused key is removed. It intentionally does not baseline focus loss for
   moved keyed survivors. Any future keyed-diff optimization should update this
   baseline deliberately. Baseline issue: [#250].
2. **Keep keyed diff changes benchmark-led.** Issue [#241] replaced the pure
   planner's large-list duplicate-free O(n²) scan with a key-map path after the
   2026-06-10 pure bench and 2026-06-12 Playwright DOM bench established the
   baseline. The N=256 pure planner now improves 7.46× on reverse, 2.91× on
   prepend, and 2.66× on unchanged lists; browser reverse improves 395→271 µs.
   The DOM applier diffs in place when key order is unchanged, but still
   re-appends moved keyed children; treat any future move-minimization pass as a
   separate measured change.
3. **Expose only the experimental surface needed by real in-repo drivers.**
   Issue [#268] starts this by making `Program`, cacheable `Html`, `Attrs`, pure
   event descriptors, payload ids, and `BrowserRenderer` roots/stats importable
   by sibling examples. Keep the surface explicitly experimental until a
   side-by-side typed spreadsheet proves it.
4. **Keep DOM effects at the post-render boundary.** `Cmd::effect` remains the
   synchronous post-batch hook; `Cmd::after_flush` and
   `Cmd::focus_element_by_id` run after `BrowserRenderer` flushes mounted roots,
   which is the right place for inline-editor focus/select without storing
   closures or DOM objects in `Html`.
5. **Expand Eq-safe events.** The #249 slice adds typed pure descriptors for
   text input, keyboard, and pointer payload events while keeping resolver logic
   at the mount/browser boundary. The #270 slice adds submit, focus/blur,
   double-click, static `stop_propagation`, and payload-dependent keyboard
   actions through the same descriptor/resolver pattern. Future editor demos can
   add composition or selection families without changing the boundary.
6. **Make authoring tolerable without sacrificing backdating.** Issue [#248]
   added a small `Attrs::build()` convenience layer plus `ul` and keyed list
   wrappers. It keeps `Html` closure-free, uses explicit ordered child
   arrays, and treats `.attr(name, value)` as the escape hatch rather than
   adopting Rabbita's closure-valued event handlers or map-shaped keyed
   children.
7. **Advance the existing editor-shaped evidence.** The semantic-keyed editor
   demo from #251 already covers stable semantic ids, local text edits,
   selection/focus checks, a viewport/order projection root, and a separate
   inspector/diagnostics root. The completed Machine composition experiment
   covered pure parent/child composition, add/remove/reorder, identity reuse,
   incarnation-safe late results, stale/duplicate completion rejection,
   history, commands, and aggregate `Program::stateful_cmd`. The
   [Machine composition ADR](../decisions/2026-07-14-machine-composition-domain-functions.md)
   records the result: no `Machine` type or per-key reactive graph. Keep the
   existing demo/renderer fixture coupling unchanged until the module identity
   ADR's disentanglement trigger is handled.
8. **Keep direct patching narrow and measured.** The #254 prototype shows that
   pure direct leaf/attribute descriptors plus mount-boundary watched string
   resolvers can patch the row/leaf hot path in ~4–5 µs at N=256 without
   storing closures or watches in `Html`. Generalize only behind similarly
   shaped editor evidence; keep the existing value-level renderer as the
   fallback for structural and keyed-identity cases.
9. **Prototype island-style activation only for DOM-present hidden subtrees.**
   The #255 benchmark shows that collapsed conditionals are already cheap, while
   hidden-mounted editor-shaped subtrees pay visible-update costs. The initial
   `BrowserRenderer::deactivate` / `activate` slice pauses watched-view reads
   without discarding DOM, benchmarks inactive updates at collapsed-update scale,
   and now has an amortized burst cost model. The #280 policy chooses a
   manual-first hybrid: product/semantic actions activate directly, while
   visibility/idle triggers are advisory prewarm hints only.
   Baseline issues: [#255], [#280]. Policy ADR:
   [manual-first hybrid](../decisions/2026-06-17-incr-tea-inactive-root-activation-policy.md).
10. **Explore host-framework boundaries.** Test whether custom-element style
   mounts make `incr_tea` roots easier to embed and lifecycle-test. Follow-up:
   [#256].
11. **Compare against real adjacent systems.** Use shared workloads before copying
   Rabbita VDOM, Luna direct DOM, or Qwik lazy-boundary patterns. Follow-up:
   [#257].

## Non-goals

- Reimplement all of Rabbita inside `examples/incr_tea`.
- Reimplement Luna as a generic signal/effect UI framework.
- Stabilize `incr_tea` as a public `dowdiness/incr` API.
- Add raw closure-valued event handlers to cacheable `Html` values; ergonomic
  handler APIs must lower to pure descriptors instead.
- Adopt Qwik resumability, QRL machinery, or Luna island hydration before the
  renderer has an editor-shaped driver.
- Treat "no VDOM" as a goal independent of measured editor workload wins.
- Optimize keyed diff or direct patching without rerunning the pure and browser
  benchmarks.

## Success metrics

`incr_tea` should be judged by editor-shaped measurements and invariants:

- unread-field or unrelated-semantic changes keep view recompute O(1);
- unchanged child roots skip patching across parent updates;
- keyed semantic nodes preserve DOM identity across insert/remove/reorder;
- focus/selection behavior is explicit and tested;
- hidden/collapsed/offscreen roots have explicit watch/reachability semantics;
- same-order row and hot leaf updates have measured list/row/leaf locality;
- direct leaf patch experiments beat the existing renderer on a measured hot path
  before becoming permanent;
- browser DOM benchmarks remain reproducible after renderer changes;
- any ergonomic API still preserves `Html : Eq` and closure-free event data.

## Issue map

- [#241] Optimized `plan_keyed_diff` with a key-map large-list path (N=256 pure planner: 7.46× reverse, 2.91× prepend, 2.66× unchanged); avoid duplicating this work elsewhere.
- [#248] Added an Eq-safe `Attrs::build()` HTML ergonomics layer informed by Rabbita.
- [#249] Expanded typed pure payload descriptors for text input, keyboard, and pointer events.
- [#270] Add Eq-safe spreadsheet event descriptors and renderer-boundary keyboard actions.
- [#250] Add browser tests for keyed DOM identity and focus retention — baseline
  covered by `examples/incr_tea/scripts/test-keyed-dom.mjs` / `npm run test:dom`.
- [#251] Build an editor-shaped semantic-key rendering demo: initial browser
  driver covers stable semantic ids, local edits, focus retention, viewport/order
  updates, and a separate inspector diagnostics slice.
- [#252] Research Qwik-style serializable and lazy UI boundaries.
- [#254] Prototype Luna-style direct leaf DOM patch tasks.
- [#255] Prototype visibility/idle-driven Watch activation for UI islands.
- [#256] Explore WebComponent/custom-element mount boundaries.
- [#257] Compare Rabbita, Luna, and `incr_tea` on shared UI-shaped benchmarks.
- [#268] Make `examples/incr_tea` reusable enough for a side-by-side typed
  spreadsheet demo without sacrificing `Html : Eq`.
- [#286] Shipped Eq-safe controlled form support: pure value-change
  descriptors, controlled input/select values, boolean property repair, and
  browser smoke coverage. Residual ergonomic constructors remain gated on a
  concrete consumer.

[#241]: https://github.com/dowdiness/incr/issues/241
[#248]: https://github.com/dowdiness/incr/issues/248
[#249]: https://github.com/dowdiness/incr/issues/249
[#250]: https://github.com/dowdiness/incr/issues/250
[#251]: https://github.com/dowdiness/incr/issues/251
[#252]: https://github.com/dowdiness/incr/issues/252
[#254]: https://github.com/dowdiness/incr/issues/254
[#255]: https://github.com/dowdiness/incr/issues/255
[#256]: https://github.com/dowdiness/incr/issues/256
[#257]: https://github.com/dowdiness/incr/issues/257
[#268]: https://github.com/dowdiness/incr/issues/268
[#286]: https://github.com/dowdiness/incr/issues/286
[#270]: https://github.com/dowdiness/incr/issues/270
[#280]: https://github.com/dowdiness/incr/issues/280
