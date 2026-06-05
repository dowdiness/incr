# Incremental TEA prototype

Experimental `incr`-native TEA runtime skeleton for
[`dowdiness/incr#191`](https://github.com/dowdiness/incr/issues/191).

This is not a public `dowdiness/incr` API and not a Rabbita fork. The prototype
now proves the core loop with a pure counter component, a minimal
Rabbita-style `Cmd` scheduler, and a browser-rendering slice for watched
`Html` view roots. Rabbita-compatible HTML/VDOM, subscriptions, async command
adapters, and benchmark comparisons are follow-up issues.

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

A future DOM renderer may remove and reinsert DOM nodes without disposing the
component. In that case the component scope and watch root must remain alive.
Only destroy the scope when the logical TEA component instance is gone.

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

The browser demo includes:

- a counter root with an unread field mutation that schedules a flush but does
  not recompute or patch the watched view;
- a conditional panel whose closed view does not depend on the detail field, so
  closed detail mutations are skipped until the panel opens;
- a small parent/child nested-root demo where updating the parent leaves the
  child watched root unchanged and skipped.

Instrumentation is visible in the demo and counts mounted-root view recomputes,
DOM patch attempts, skipped patches, and rAF flushes.

### Rabbita reuse/adaptation note

Before implementing this slice, the Rabbita references read were:

- `/home/antisatori/ghq/github.com/dowdiness/canopy/rabbita/doc/002_writing_html/readme.mbt.md`
- `/home/antisatori/ghq/github.com/dowdiness/canopy/rabbita/rabbita/html/README.mbt.md`
- `/home/antisatori/ghq/github.com/dowdiness/canopy/rabbita/rabbita/internal/runtime/README.mbt.md`
- `/home/antisatori/ghq/github.com/dowdiness/canopy/rabbita/rabbita/tea.mbt`

Reused ideas: an HTML value layer, event descriptors that re-enter a central
scheduler, FIFO command execution, and rAF-batched rendering. New here: the
view root is an `@incr.Derived` watched by `Program`, the renderer reads the
watch instead of calling `view(model)`, and patching is driven by `Html : Eq`
backdating rather than Rabbita cell dirty flags. This is not a Rabbita fork: it
imports no Rabbita runtime or HTML package and intentionally keeps the renderer
boundary narrow so a measured Rabbita VDOM/HTML subset can be swapped in later.

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
