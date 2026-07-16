# Incremental TEA prototype

Experimental `incr`-native TEA runtime skeleton for
[`dowdiness/incr#191`](https://github.com/dowdiness/incr/issues/191).

This is not a stable `dowdiness/incr` API and not a Rabbita fork. The prototype
now exposes an experimental in-repo framework surface for other workspace
examples: `Program`, `Cmd`, cacheable `Html`, `Attrs`, pure event descriptors,
payload ids, and `BrowserRenderer` roots/stats. It proves the core loop with a
pure counter component, a minimal Rabbita-style `Cmd` scheduler, and a
browser-rendering slice for watched `Html` view roots — including typed pure
event-payload descriptors (#211/#249/#270), keyed children (#211), a small
semantic-keyed editor driver (#251), post-render commands for DOM work that
must run after a flush (#268), and DOM-preserving inactive roots for activation
island experiments (#255). Async command adapters and deeper browser/runtime
benchmark comparisons remain follow-up issues; a first pure adjacent-framework
benchmark slice is documented below.

## BSaLC / TEA mapping

| TEA concern | Prototype mapping |
| --- | --- |
| Scheduler | `CounterApp::dispatch` enqueues messages, runs each `update` in `Runtime::batch`, then executes returned `Cmd` values after the batch commits. The browser renderer schedules rAF flushing from the runtime change hook. |
| Store | Component model fields are `InputField` values owned by an `@incr.Scope`. |
| Task | `view` is a pure tracked `Derived` computation. |
| Rebuilder | The default `incr` verifying trace with backdating decides whether the view recomputes. |
| Lifetime | Mounted programs hold a persistent `Watch` on the terminal view and register it with the component scope. |
| Effects | `Cmd::effect` is a low-level synchronous edge hook before DOM flush. `Cmd::after_flush` queues post-render effects that run after the browser renderer has committed a patch. Effects run outside tracked view computations and re-enter by enqueuing commands/messages. |

## Component lifecycle

Creating a component starts one logical TEA instance: it allocates an
`@incr.Scope`, registers model `InputField` cells with that scope, creates the
terminal tracked view, registers a persistent `Watch` for the view root, and
primes that watch so `Runtime::gc()` can see the current upstream dependencies
before the first external read. `Program` constructors reject a `Runtime`/`Scope`
mismatch; the renderer relies on the program runtime for flush scheduling.

Disposal is component teardown, not ordinary DOM detachment. `dispose()` is
idempotent; it disposes the scope, releases the view `Watch`, and closes the
public boundary. After disposal, `is_disposed()` returns `true`, dispatch
returns `false`, and view/model getters return `None` instead of exposing
disposed-cell aborts.

The browser renderer keeps DOM detachment and component disposal separate
(#209). `BrowserRenderer::detach` removes a root's DOM subtree but keeps its
`Program` scope and watch alive, parking the root so a flush skips it; the
renderer still owns it, so `BrowserRenderer::reattach` re-mounts the same root
with its state preserved, and `dispose` reclaims it rather than leaking it.
`BrowserRenderer::deactivate` is a narrower DOM-preserving state for #255: the
root remains mounted and attached, with the same `Program` and view `Watch`, but
scheduled flushes skip `root.flush()` until `BrowserRenderer::activate` performs
one catch-up flush. `BrowserRenderer::destroy` is the logical teardown: it tears
down the DOM and disposes the program scope when no sibling root still
references it, so destroying one of several mounts of a shared component leaves
the others working. Only `destroy` (and `dispose`, which destroys every owned
root, mounted or parked) touches the scope.

While the component instance is alive, the persistent `Watch` keeps the view
chain reachable across `Runtime::gc()`. After disposal, the scope and watch are
released so a later GC can reclaim component internals.

## Command scheduler

`update` returns a `Cmd` instead of running follow-up work directly. The
scheduler commits all model writes for the current message inside one
`Runtime::batch`, then executes the returned command tree. `Cmd::batch`
snapshots its input and runs left-to-right, and `Cmd::message` appends follow-up
messages to the FIFO queue, so a burst stays deterministic.

The low-level `Cmd::effect` hook is synchronous. Its callback runs after the
model batch commits and outside tracked `Derived` view computations, but before
the next browser DOM flush; it can enqueue another command to re-enter the TEA
loop. Checked failure handling is intentionally unsupported at the command layer
for now. Represent recoverable failures as messages carrying `Result`.

`Cmd::after_flush` queues the same callback shape for the renderer's post-flush
phase. `Program` stores these callbacks outside cacheable `Html`, and
`BrowserRenderer` drains active mounted roots after `root.flush()` has rendered
or diffed the DOM. If a program has no active mounted root, its callbacks wait
until activation's catch-up flush; callbacks are still program-scoped when one
`Program` backs multiple roots. This is the boundary for DOM work that needs
nodes created by the current patch, such as focusing and selecting an inline
editor:

```mbt nocheck
///|
fn[Msg] focus_inline_editor_cmd(id : String) -> Cmd[Msg] {
  Cmd::focus_element_by_id(id, select=true)
}
```

A mounted `BrowserRenderer` schedules a flush when an `after_flush` command is
queued, even if the model update does not change the `Html` value. A post-flush
callback may enqueue follow-up commands/messages. Follow-up model writes run in
normal `Runtime::batch` dispatch and, if they change the view, are rendered by a
later animation-frame flush rather than recursively patching the current DOM
frame.

## Browser renderer slice

The renderer mounts experimental public `Program[Msg, Html[Msg]]` roots,
installs a runtime `on_change` hook, and schedules one `requestAnimationFrame`
flush for a burst of model changes. A flush reads each active root's persistent
`Watch`; if the cacheable `Html` value is equal to the last rendered value, the
renderer records a skipped patch and runs only the narrow controlled form-property
repair for live `value`/`checked`/`disabled`/`selected` drift. String `value`
properties are controlled on `<input>` and `<select>` elements; select values
are reconciled after their option children are mounted or diffed. If the value
changed, it records a patch attempt and applies a small positional VDOM diff.
Inactive mounted roots stay in the owned root set and keep their DOM attached, but the
scheduled frame records an inactive skip instead of reading the watched view;
activation records a catch-up flush and reads/diffs once. The chosen trigger
policy is manual-first hybrid: product/semantic UI actions should use
`BrowserRootActivationController::show` / `hide`, which wrap the existing
`BrowserRenderer::activate` / `deactivate` lifecycle without adding a core
scheduler. Visibility or idle triggers may call `prewarm` only for roots where
early activation side effects are acceptable, because prewarm uses the same
catch-up flush and after-flush drain as `show`. See the
[#280 ADR](../../docs/decisions/2026-06-17-incr-tea-inactive-root-activation-policy.md).

`Html` stores attributes, children, and pure event descriptors. DOM event
listener closures are created only by the renderer boundary and dispatch
messages back into the scheduler; they are not captured inside tracked
`Derived` view computations. Synchronous command effects still run through
`Cmd::effect` after the model batch commits; DOM-dependent effects use
`Cmd::after_flush` or the convenience `Cmd::focus_element_by_id` command so they
run after the renderer boundary has patched the DOM.

### Event payloads and actions (#211, #249, #270)

An event descriptor is pure data with meaningful `Eq`. `on_click(msg)` stores a
fixed message; the spreadsheet-oriented fixed-message descriptors add
`on_submit(msg)`, `on_blur(msg)`, `on_focus(msg)`, and `on_dblclick(msg)`.
`on_submit` prevents the browser's native form submission by default. Payload
descriptors store typed pure ids (`TextInputId`, `KeyEventId`, `PointerEventId`)
plus a DOM event name; the renderer extracts the browser payload at the boundary
and resolves `(id, payload) -> Msg` through mount-time resolvers (`on_input` for
text/value-change payloads, `on_key`, and `on_pointer`). Text input and
value-change descriptors forward `value`; keyboard descriptors forward
key/code/modifiers/repeat, and pointer descriptors forward pointer id/type,
viewport coordinates (`client_x`/`client_y`), target-element-local offsets
(`offset_x`/`offset_y`, from the browser's `offsetX`/`offsetY`), buttons, and
modifiers. Use `on_change(tag=...)` for committed values from selects and
range/date controls. No closure or DOM event object is stored in cacheable
`Html`, so equal descriptors still backdate.
Checkbox/radio checked-state payloads use `on_checked_change(tag=...)` with
`CheckedInputId` and `CheckedPayload{checked: Bool}`, following the same pure-id
pattern. The renderer reads `event.target.checked` at the boundary and resolves
`(id, payload) -> Msg` through the mount-time `on_checked_change` resolver:

```mbt nocheck
renderer.mount(
  host,
  program,
  on_checked_change=(id, payload) => {
    match id.name {
      "subscribe" => Some(SetSubscribed(payload.checked))
      _ => None
    }
  },
)
```

Static `prevent_default` / `stop_propagation` flags are pure descriptor data, and
the actual DOM calls are made only by the renderer listener. Keyboard handlers
that need payload-dependent actions use the mount-boundary `on_key_event`
resolver, which returns `KeyEventDispatch`:

```mbt nocheck
renderer.mount(
  host,
  program,
  on_key_event=(id, payload) => {
    if id == KeyEventId("sheet.keys") {
      match payload.key {
        "Enter" => Some(
          KeyEventDispatch::message(
            ApplyInlineEdit,
            prevent_default=true,
            stop_propagation=true,
          ),
        )
        "Escape" => Some(
          KeyEventDispatch::message(
            CancelInlineEdit,
            prevent_default=true,
            stop_propagation=true,
          ),
        )
        _ => None
      }
    } else {
      None
    }
  },
)
```

This keeps spreadsheet keyboard policy beside the payload-to-message resolver,
not inside cached `Html`.

### Direct leaf patch prototype (#254)

The row/leaf benchmark includes an experimental `incr_tea-direct` path. It is a
narrow Luna-inspired locality probe, not a replacement renderer: `Html` may carry
pure direct text/attribute ids and fallback values, while live `Watch[String]`
leaves and resolver callbacks stay at the renderer/benchmark boundary. The
prototype renders the static row/list shape once, collects the direct DOM leaves,
and later flushes only those collected text/class leaves.

The dated result is recorded in
[`docs/performance/2026-06-15-incr-tea-direct-leaf-patching-prototype.md`](../../docs/performance/2026-06-15-incr-tea-direct-leaf-patching-prototype.md).
At N=256 it brings the row text/class/hot-leaf cells down to roughly 4–5 µs while
preserving closure-free `Html : Eq` for the cached view data.

### HTML authoring ergonomics (#248)

The HTML layer now has a small Rabbita-informed convenience surface while keeping
`Html` closure-free and `Eq`-comparable:

```mbt nocheck
///|
let row_attrs = Attrs::build()
  .class("editor-row is-selected")
  .data("semantic-id", "sem-binding")
  .role("option")
  .aria_bool("selected", true)
  .to_array()
```

Conventions:

- Use `Attrs::build()` for common demo/editor attributes (`class`, `role`,
  `value`, `placeholder`, `data-*`, and `aria-*`). Use `.attr(name, value)` as
  the explicit escape hatch when a wrapper is missing a one-off attribute.
- Attribute order is part of the `Html : Eq` value. Keep builder calls stable
  across renders; do not generate attributes from unordered maps.
- Children are explicit ordered arrays of `Html`. Wrap string content with
  `text("...")`; `button(..., label)` is a narrow convenience for the common
  labeled-button case, not a general string-children overload.
- Prefer `ul` for ordinary ordered child arrays and `keyed_ul` / `keyed_ol` /
  `keyed_node` for keyed children. Keyed children remain ordered
  `Array[(String, Html)]` values, not maps, because both child order and key
  identity feed deterministic diffing and value-level backdating.
- Event helpers stay pure descriptors. Do not add closure-valued event handlers
  to `Html`; payload-to-message logic and payload-dependent keyboard actions
  belong at `BrowserRenderer::mount`.
- String `value` properties are controlled on `<input>` and `<select>` elements
  when supplied as `attr("value", value)`; the renderer writes the DOM property
  directly and equal-view flushes repair browser drift. Select values are
  applied after option children are mounted or diffed, so a newly added selected
  option is restored in the same render.
- Boolean form-control properties (`checked`, `disabled`, `selected`) use
  `Attrs::checked(Bool)`, `Attrs::disabled(Bool)`, and `Attrs::selected(Bool)`.
  Calling the helper with either `true` or `false` makes the property controlled:
  the renderer writes the DOM property directly and equal-view flushes repair live
  browser drift. Omitting the helper leaves that property uncontrolled and
  browser-owned. For a one-off boolean property, use `prop_bool(name)` directly.

### Semantic editor driver (#251)

The browser demo includes an editor-shaped workload because generic counters and
todo-style lists do not exercise Canopy/Loom's hard path: semantic identity is
stable while projection positions, local text, selection, diagnostics, and
inspector views change independently. The demo keeps three semantic nodes
(`sem-module`, `sem-binding`, `sem-call`) in a reorderable projection keyed by
semantic id rather than position. A local text edit updates one semantic node,
while keyed DOM reconciliation preserves unrelated row identity and browser
focus on the edited input.

The inspector is a separate watched view root that reads a different dependency
slice from the projection: selection, selected text, and diagnostics, but not row
order or viewport state. Diagnostic edits patch the inspector while the
projection root is skipped; viewport/order edits patch the projection while the
inspector is skipped. The shared renderer instrumentation reports the resulting
view recomputes, patch attempts, and skipped patches.

Selection/focus behavior is intentionally narrow: pointer or text-input payloads
select a semantic id, the selected row gets `aria-selected`, and browser tests
assert that a focused semantic input survives a local keyed text edit. Moving a
focused row is not yet a focus-retention guarantee because the current keyed DOM
applier still re-appends moved survivors.

### Keyed children (#211)

`keyed_node(tag, children=[(key, child), ...])` builds a `KeyedElem` whose
children carry a stable business key (not an array index). On diff, the pure
`plan_keyed_diff` matches old children to new children by key, so
insert/remove/reorder reuse each key's existing DOM node (and its listeners)
instead of re-patching by position; positional `div`/`p`/… children keep the
simple index diff. If the key order is unchanged, children are diffed in place so
local editor-row updates do not reparent focused inputs. If keys are inserted,
removed, or reordered, the applier removes vanished keys, then re-appends
survivors and new nodes in the new order (`appendChild` moves an attached node),
which preserves per-key identity. Keys must be unique and stable; duplicate keys
are a usage error that degrades (a node is reused once, the rest are recreated)
rather than crashing. Reorders are not minimal-move — moved keyed children are
re-appended — so an anchor-based minimal-move pass (LIS / two-ended) is a
follow-up if focus/selection behavior or a benchmark justifies it. The browser
regression test records the current split without treating moved keyed survivors
as focus loss: unchanged-list flushes and same-order local editor edits keep
focus on a keyed input, focused-row removal moves focus out of the list, and row
identity plus uncontrolled input values are preserved across reorder.

The renderer stores the two additive runtime listener ids it registers (#210)
— the `on_change` flush trigger and the derived-event view-recompute counter —
and removes them on `dispose`, so a torn-down renderer stops reacting to runtime
changes. `dispose` also destroys every mounted root. A queued `requestAnimationFrame`
that fires after `dispose` is a no-op, and `mount` after `dispose` is rejected.

The browser demo includes:

- a counter root with an unread field mutation that schedules a flush but does
  not recompute or patch the watched view;
- a conditional panel whose closed view does not depend on the detail field, so
  closed detail mutations are skipped until the panel opens;
- a small parent/child nested-root demo where updating the parent leaves the
  child watched root unchanged and skipped;
- child-lifecycle controls (#209) that detach the child (DOM removed, program
  parked but alive), reattach it (state preserved), destroy it (program disposed
  when no sibling root references it), and dispose the whole renderer (which also
  reclaims parked roots);
- a payload card (#211/#249/#286) whose text-input, keyboard, pointer, and
  checkbox checked-change payloads dispatch as `Msg` values and echo back
  into the view;
- a semantic editor card (#251) whose projection rows are keyed by semantic ids,
  support local text edits and position changes, preserve focused keyed inputs
  on local edits, and drive a separate inspector root that reads diagnostics and
  selected-node state instead of viewport/order state;
- a keyed-list card (#211) with prepend / remove-first / reverse controls, where
  each row carries an uncontrolled notes `<input>` whose typed text follows its
  item across reorder because the keyed diff reuses the row's DOM node by key.
- a timer subscription demo where each subscription is declared from model state
  through a tracked `Derived[Subscriptions]` map and diffed into a side-effect
  handle set.
Instrumentation is visible in the demo and counts mounted-root view recomputes,
DOM patch attempts, skipped patches, rAF flushes, inactive skipped flushes, and
activation catch-up flushes.

## DOM applier benchmark

The keyed DOM applier benchmark runs the renderer in a real Chromium document via
Playwright and compares keyed reuse against a non-keyed list rebuild baseline:

```bash
cd examples/incr_tea
npm install
npx playwright install chromium   # one-time browser install if needed
npm run bench:dom
```

The script builds the MoonBit browser-bench entry point, serves `bench.html`, and
prints Markdown tables plus raw JSON. Tune the sampling budget with
`INCR_TEA_DOM_BENCH_ITERATIONS` and `INCR_TEA_DOM_BENCH_SAMPLES`. The dated
snapshot is recorded in
[`docs/performance/2026-06-12-incr-tea-keyed-dom-applier-playwright.md`](../../docs/performance/2026-06-12-incr-tea-keyed-dom-applier-playwright.md).

## Controlled-property reconciliation benchmark (#394)

The equal-view controlled-property benchmark runs the production
`BrowserRenderer::flush_all` path in Chromium. It varies rendered-tree size
(0/100/1,000/10,000 nodes) and controlled-property count (0/1/16/256), then
reports median and p95 latency across individual flushes, separately for equal
views with no browser drift and equal views that repair deliberate
`value`/`checked`/`disabled`/`selected` drift. The runner enables
cross-origin isolation for a 5 µs timer probe and marks cells below 10 timer
quanta as below-resolution instead of treating their quantized p95 as a tail
measurement.

```bash
cd examples/incr_tea
npm install
npx playwright install chromium   # one-time browser install if needed
npm run bench:controlled-reconcile
```

The harness dispatches a monotonically changing unrelated input before every
flush, including warmups, so equal-value input updates cannot skip the path.
The timed window excludes mount, tree construction, browser-property mutation,
and model dispatch. The dated results and environment are recorded in
[`docs/performance/2026-07-15-incr-tea-controlled-reconciliation.md`](../../docs/performance/2026-07-15-incr-tea-controlled-reconciliation.md).

## Adjacent-framework pure comparison benchmark

The first #257 comparison slice builds the same counter and list-shaped view
values in `incr_tea`, Rabbita, and Luna. It is a pure JS-target `moon bench`
measurement only — no browser DOM patching, dirty-cell flush, or Luna signal
update is included:

```bash
NEW_MOON_MOD=0 moon bench --release -p incr_tea \
  -f ui_compare_bench_wbtest.mbt --target js
NEW_MOON_MOD=0 moon bench --release -p examples/incr_tea/ui_compare_bench \
  --target js
```

The root package remains wasm-gc benchable; the Rabbita/Luna half of the slice
lives in the JS-only `ui_compare_bench` subpackage. The dated plan and snapshot
are recorded in
[`docs/performance/2026-06-14-ui-shaped-adjacent-framework-comparison.md`](../../docs/performance/2026-06-14-ui-shaped-adjacent-framework-comparison.md).

## Adjacent-framework mounted matrix browser benchmark

The #257 mounted browser harness runs a batch matrix across `incr_tea`, Rabbita,
and Luna in hidden attached Chromium hosts. It covers the original counter rows,
keyed-list prepend/remove-first/reverse at N=16/64/256, hidden/visible panel
updates, row/leaf locality rows for same-order row text/class and hot nested
text leaf updates at N=16/64/256, a #255 workspace-island slice comparing
collapsed, hidden-mounted, and visible editor/sidebar/inspector updates, and an
`incr_tea`-only inactive-root slice that measures active hidden-mounted updates,
inactive DOM-preserving updates, and activation catch-up:

```bash
cd examples/incr_tea
npm install
npm run bench:ui-compare-dom
```

The original counter-only snapshot is recorded in
[`docs/performance/2026-06-14-mounted-counter-adjacent-framework-comparison.md`](../../docs/performance/2026-06-14-mounted-counter-adjacent-framework-comparison.md).
The mounted matrix snapshot is recorded in
[`docs/performance/2026-06-14-mounted-matrix-adjacent-framework-comparison.md`](../../docs/performance/2026-06-14-mounted-matrix-adjacent-framework-comparison.md).
The row/leaf locality follow-up is recorded in
[`docs/performance/2026-06-14-mounted-row-leaf-locality-comparison.md`](../../docs/performance/2026-06-14-mounted-row-leaf-locality-comparison.md).
The activation-islands measurement gate is recorded in
[`docs/performance/2026-06-15-incr-tea-activation-islands-measurement.md`](../../docs/performance/2026-06-15-incr-tea-activation-islands-measurement.md).
The inactive-root prototype follow-up is recorded in
[`docs/performance/2026-06-15-incr-tea-inactive-root-prototype.md`](../../docs/performance/2026-06-15-incr-tea-inactive-root-prototype.md).

## Keyed DOM browser regression tests

The keyed DOM regression test runs the real browser demo through Playwright, so
prepend / remove-first / reverse exercise the same `diff_keyed_children` path a
user sees in Chromium:

```bash
cd examples/incr_tea
npm install
npx playwright install chromium   # one-time browser install if needed
npm run test:dom
```

The test distinguishes identity from focus behavior. It asserts that keyed rows
reuse their DOM nodes across prepend, remove-first, and reverse, and that
uncontrolled notes `<input>` values follow their keyed rows across reorder. It
also keeps the current focus baseline explicit without baselining moved-row focus
loss: a focused keyed input survives an animation-frame flush when the list view
is unchanged; same-order local editor edits keep focus on the edited input; and
removing the focused key moves focus out of the list. The same browser run covers
the semantic editor driver: semantic rows preserve DOM identity when their
positions change, and a local text edit keeps focus on the edited semantic input
while the inspector reflects the selected node. A future minimal-move applier
should update this baseline together with the implementation when it intentionally
changes focus/selection behavior.

## Subscription keys and collisions

Subscriptions are keyed by `SubKey`, which is a pair:
`(namespace, identity)`. `namespace` groups ownership (for example, the
timer demo uses `"demo"`), while `identity` identifies the logical resource
within that namespace.

This stable key guarantees that unrelated model changes do not cause churn: only
values read by the subscription `Derived` can invalidate it, and the resulting
map is reconciled by key.

Collision risk is explicit: two different logical subscriptions that reuse the
same `(namespace, identity)` pair will be treated as one subscription and
updated in place. Choose unique namespaces and identities for independent
streams, and keep identities stable across renders unless you intentionally want
explicit replacement semantics.

### Rabbita reuse/adaptation note

Before implementing this slice, the Rabbita references read were:

- [`rabbita/doc/002_writing_html/readme.mbt.md`](https://github.com/dowdiness/rabbita/blob/5f828eb7270cb14970f2be592dba25990a513c61/doc/002_writing_html/readme.mbt.md)
- [`rabbita/rabbita/html/README.mbt.md`](https://github.com/dowdiness/rabbita/blob/5f828eb7270cb14970f2be592dba25990a513c61/rabbita/html/README.mbt.md)
- [`rabbita/rabbita/internal/runtime/README.mbt.md`](https://github.com/dowdiness/rabbita/blob/5f828eb7270cb14970f2be592dba25990a513c61/rabbita/internal/runtime/README.mbt.md)
- [`rabbita/rabbita/tea.mbt`](https://github.com/dowdiness/rabbita/blob/5f828eb7270cb14970f2be592dba25990a513c61/rabbita/tea.mbt)

Reused ideas: an HTML value layer, event descriptors that re-enter a central
scheduler, FIFO command execution, and rAF-batched rendering. New here: the
view root is an `@incr.Derived` watched by `Program`, the renderer reads the
watch instead of calling `view(model)`, and patching is driven by `Html : Eq`
backdating rather than Rabbita cell dirty flags. This is not a Rabbita fork: it
imports no Rabbita runtime or HTML package and intentionally keeps the renderer
boundary narrow so a measured Rabbita VDOM/HTML subset can be swapped in later.
The broader Rabbita/Qwik/Luna comparison and roadmap live in
[`docs/research/incr-tea-ui-direction.md`](../../docs/research/incr-tea-ui-direction.md).

#### Keyed children and event payloads (#211, #249, #270)

The reference read for this slice was
[`rabbita/rabbita/html/README.mbt.md`](https://github.com/dowdiness/rabbita/blob/5f828eb7270cb14970f2be592dba25990a513c61/rabbita/html/README.mbt.md)
(the "Keyed Children" and "Event Handlers" sections).

- **Keyed children — reused, adapted.** Rabbita's idea is taken directly: a
  stable, unique business key (not an array index) is matched across updates to
  reuse a node, and changing a key drops the old node and creates a new one.
  Rabbita expresses keyed children as `Map[String, Html]`; this prototype uses an
  ordered `Array[(String, Html)]` instead, because the child order is part of the
  `Eq`-cacheable view value and the diff must be deterministic — an unordered map
  would lose both.
- **Event payloads — deliberately NOT reused.** Rabbita writes payload handlers
  as closures in the view (`on_mousedown=m => emit(StartDraw(m))`). That cannot
  work here: the view value is a tracked `Derived` output that must stay `Eq` and
  closure-free for backdating, and a fresh closure per recompute would never
  compare equal. Instead the payload→message mapping is split — the `Html` stores
  typed pure ids (`TextInputId`, `CheckedInputId`, `KeyEventId`, `PointerEventId`)
  and event names, while resolvers supplied at the JS mount boundary
  (`mount(..., on_input=..., on_checked_change=..., on_key=..., on_pointer=...,
  on_key_event=...)`) turn typed browser payloads into messages and
  payload-dependent keyboard actions, mirroring where the existing `dispatch`
  closure already lives. So
  Rabbita's keyed-child semantics are adopted wholesale, while its closure-valued
  event API is intentionally replaced with pure data plus boundary resolvers.
- **Qwik-style boundary — similar discipline, not QRL resumability.** Qwik stores
  serializable lazy handler references and loads code on demand. This prototype
  does not serialize roots or lazy-load handlers yet; it only keeps the same hard
  boundary: `Html` carries stable data, and executable payload mapping lives
  outside the value at an explicit browser/mount edge.

## Counter smoke test

```mbt check
///|
fn install_readme_recompute_counter(runtime : @incr.Runtime) -> Ref[Int] {
  let completed : Ref[Int] = Ref(0)
  try! runtime.on_derived_event(event => {
    match event {
      @incr.DerivedEvent::Completed(_) => completed.val = completed.val + 1
      _ => ()
    }
  })
  completed
}

///|
test "README: counter incremental view" {
  let runtime = @incr.Runtime()
  let app = @incr_tea.CounterApp::with_runtime(runtime)
  let recomputes = install_readme_recompute_counter(runtime)

  let initial = app.view_or_abort()
  inspect(initial.count, content="0")
  inspect(initial.title, content="Counter")
  inspect(recomputes.val, content="0")

  ignore(app.dispatch(@incr_tea.CounterMsg::Increment))
  let after_increment = app.view_or_abort()
  inspect(after_increment.count, content="1")
  inspect(recomputes.val, content="1")

  ignore(app.dispatch(@incr_tea.CounterMsg::IncrementTwice))
  let after_command = app.view_or_abort()
  inspect(after_command.count, content="3")
  inspect(recomputes.val, content="2")

  ignore(app.dispatch(@incr_tea.CounterMsg::SetUnrelated(1)))
  ignore(app.view_or_abort())
  inspect(recomputes.val, content="2")

  app.dispose()
  inspect(app.dispatch(@incr_tea.CounterMsg::Increment), content="false")
}
```

## Run

From the repository root:

```bash
moon check
moon test incr_tea
moon test --target js incr_tea
moon build --target js --release
python3 -m http.server 8765
# then open http://127.0.0.1:8765/examples/incr_tea/index.html
```
