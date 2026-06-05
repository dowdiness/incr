# Incremental TEA prototype

Experimental `incr`-native TEA runtime skeleton for
[`dowdiness/incr#191`](https://github.com/dowdiness/incr/issues/191).

This is not a public `dowdiness/incr` API and not a Rabbita fork. The first slice
proves the core loop with a pure counter component; browser rendering,
Rabbita-compatible HTML/VDOM, commands, subscriptions, and benchmark comparisons
are follow-up issues.

## BSaLC / TEA mapping

| TEA concern | Prototype mapping |
| --- | --- |
| Scheduler | `CounterApp::dispatch` handles one message at a time and wraps `update` in `Runtime::batch`. A later renderer will add queue draining and rAF flushing. |
| Store | Component model fields are `InputField` values owned by an `@incr.Scope`. |
| Task | `view` is a pure tracked `Derived` computation. |
| Rebuilder | The default `incr` verifying trace with backdating decides whether the view recomputes. |
| Lifetime | Mounted programs hold a persistent `Watch` on the terminal view and register it with the component scope. |
| Effects | Not implemented in this slice. Effects must stay at the TEA edge through future `Cmd`/`Sub` adapters, never inside tracked view computations. |

## Counter smoke test

```mbt check
///|
fn install_readme_recompute_counter(runtime : @incr.Runtime) -> Ref[Int] {
  let completed : Ref[Int] = { val: 0 }
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

  ignore(app.dispatch(@incr_tea.CounterMsg::SetUnrelated(1)))
  ignore(app.view_or_abort())
  inspect(recomputes.val, content="1")

  app.dispose()
  inspect(app.dispatch(@incr_tea.CounterMsg::Increment), content="false")
}
```

## Run

From the repository root:

```bash
moon check
moon test examples/incr_tea
```
