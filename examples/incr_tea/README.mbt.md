# Incremental TEA prototype

Experimental `incr`-native TEA runtime skeleton for
[`dowdiness/incr#191`](https://github.com/dowdiness/incr/issues/191).

This is not a public `dowdiness/incr` API and not a Rabbita fork. The prototype
now proves the core loop with a pure counter component, a minimal
Rabbita-style `Cmd` scheduler, and a browser-rendering slice for watched
`Html` view roots — including pure event-payload descriptors and keyed children
(#211). Subscriptions, async command adapters, and benchmark comparisons are
follow-up issues.

## BSaLC / TEA mapping

| TEA concern | Prototype mapping |
| --- | --- |
| Scheduler | `CounterApp::dispatch` enqueues messages, runs each `update` in `Runtime::batch`, then executes returned `Cmd` values after the batch commits. The browser renderer schedules rAF flushing from the runtime change hook. |
| Store | Component model fields are `InputField` values owned by an `@incr.Scope`. |
| Task | `view` is a pure tracked `Derived` computation. |
| Rebuilder | The default `incr` verifying trace with backdating decides whether the view recomputes. |
| Lifetime | Mounted programs hold a persistent `Watch` on the terminal view and register it with the component scope. |
| Effects | `Cmd::effect` is a low-level synchronous edge hook. Effects run outside tracked view computations and re-enter by enqueuing commands/messages. |

## Component lifecycle

Creating a component starts one logical TEA instance: it allocates an
`@incr.Scope`, registers model `InputField` cells with that scope, creates the
terminal tracked view, registers a persistent `Watch` for the view root, and
primes that watch so `Runtime::gc()` can see the current upstream dependencies
before the first external read.

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
`BrowserRenderer::destroy` is the logical teardown: it tears down the DOM and
disposes the program scope when no sibling root still references it, so
destroying one of several mounts of a shared component leaves the others
working. Only `destroy` (and `dispose`, which destroys every owned root, mounted
or parked) touches the scope.

While the component instance is alive, the persistent `Watch` keeps the view
chain reachable across `Runtime::gc()`. After disposal, the scope and watch are
released so a later GC can reclaim component internals.

## Command scheduler

`update` returns a `Cmd` instead of running follow-up work directly. The
scheduler commits all model writes for the current message inside one
`Runtime::batch`, then executes the returned command tree. `Cmd::batch`
snapshots its input and runs left-to-right, and `Cmd::message` appends follow-up
messages to the FIFO queue, so a burst stays deterministic.

The low-level `Cmd::effect` hook is synchronous in this slice. Its callback runs
after the model batch commits and outside tracked `Derived` view computations;
it can enqueue another command to re-enter the TEA loop. Checked failure handling
is intentionally unsupported at the command layer for now. Represent
recoverable failures as messages carrying `Result`.

## Browser renderer slice

The renderer mounts package-private `Program[Msg, Html[Msg]]` roots, installs a
runtime `on_change` hook, and schedules one `requestAnimationFrame` flush for a
burst of model changes. A flush reads each root's persistent `Watch`; if the
cacheable `Html` value is equal to the last rendered value, the renderer records
a skipped patch and leaves the DOM alone. If the value changed, it records a
patch attempt and applies a small positional VDOM diff.

`Html` stores attributes, children, and pure event descriptors. DOM event
listener closures are created only by the renderer boundary and dispatch
messages back into the scheduler; they are not captured inside tracked
`Derived` view computations. Command effects still run through `Cmd::effect`,
after the model batch commits.

### Event payloads (#211)

An event descriptor is pure data with meaningful `Eq`. `on_click(msg)` stores a
fixed message; `on_input(tag~)` stores only a string `tag`. The renderer reads
the input element's value at the browser boundary and resolves `(tag, value) ->
Msg` through a mount-time resolver (`BrowserRenderer::mount(..., on_input=...)`),
so a DOM-payload event (a text input) flows through `Cmd`/message dispatch
**without storing a closure in the cacheable `Html` value**. Two `on_input`
descriptors are equal iff their tags match, so an unchanged view still backdates.

### Keyed children (#211)

`keyed_node(tag, children=[(key, child), ...])` builds a `KeyedElem` whose
children carry a stable business key (not an array index). On diff, the pure
`plan_keyed_diff` matches old children to new children by key, so
insert/remove/reorder reuse each key's existing DOM node (and its listeners)
instead of re-patching by position; positional `div`/`p`/… children keep the
simple index diff. The applier reconciles by removing vanished keys, then
re-appending survivors and new nodes in the new order (`appendChild` moves an
attached node), which preserves per-key identity. Keys must be unique and
stable; duplicate keys are a usage error that degrades (a node is reused once,
the rest are recreated) rather than crashing. This is not minimal-move — every
keyed child is re-appended when the list changes — so an anchor-based
minimal-move pass (LIS / two-ended) is a follow-up if focus-retention or a
benchmark justifies it. The browser regression test records the current split:
unchanged-list flushes keep focus on a keyed input, while any list-changing keyed
patch re-appends surviving rows and drops focus even though row identity and
uncontrolled input values are preserved.

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
- a text-input card (#211) whose `<input>` value is dispatched as a `Msg`
  payload and echoed back into the view;
- a keyed-list card (#211) with prepend / remove-first / reverse controls, where
  each row carries an uncontrolled notes `<input>` whose typed text follows its
  item across reorder because the keyed diff reuses the row's DOM node by key.
- a timer subscription demo where each subscription is declared from model state
  through a tracked `Derived[Subscriptions]` map and diffed into a side-effect
  handle set.
Instrumentation is visible in the demo and counts mounted-root view recomputes,
DOM patch attempts, skipped patches, and rAF flushes.

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
also keeps the current focus baseline explicit: a focused keyed input survives an
animation-frame flush when the list view is unchanged, but loses focus when a
list-changing keyed patch re-appends that surviving row. A future minimal-move
applier should update this baseline together with the implementation.

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

#### Keyed children and event payloads (#211)

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
  only a pure string tag (`on_input(tag~)`), and a resolver supplied at the js
  mount boundary (`mount(..., on_input=...)`) turns `(tag, value)` into a message,
  mirroring where the existing `dispatch` closure already lives. So Rabbita's
  keyed-child semantics are adopted wholesale, while its closure-valued event API
  is intentionally replaced with pure data plus a boundary resolver.

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
moon test examples/incr_tea
moon test --target js examples/incr_tea
moon build --target js --release
python3 -m http.server 8765
# then open http://127.0.0.1:8765/examples/incr_tea/index.html
```
