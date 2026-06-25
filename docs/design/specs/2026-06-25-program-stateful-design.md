# Design: `Program::stateful` and `Program::stateful_cmd`

**Date:** 2026-06-25
**Issue:** #287
**Scope:** `examples/incr_tea/` only — not a stable `dowdiness/incr` public API.

## Problem

Every 7GUIs app repeats identical boilerplate: a `Ref[Model]` to hold mutable
state, an `InputField[Int]` version cell to trigger incremental recomputation
on state change, a wrapper `App` struct to keep the `Ref` alive, and manual
wiring of `Program::Program`. The version-bump pattern is a purely mechanical
consequence of using `@incr` for TEA-style mutable state, not application logic.

## Solution

Two new constructors in `examples/incr_tea/program.mbt` that hide the version
cell, `Scope` creation, and `Ref` lifecycle. Callers write pure
`update`/`view`/`subscriptions` functions of the model.

## API

```moonbit
// Simple: update returns just the new Model (no Cmd)
pub fn[Msg : Eq, Model, View : Eq] Program::stateful(
  runtime : @incr.Runtime,
  initial : Model,
  update : (Msg, Model) -> Model,
  view : (Model) -> View,
  subscriptions? : (Model) -> Subscriptions[Msg],
  label? : String,
) -> Program[Msg, View]

// Full: update returns (Model, Cmd[Msg])
pub fn[Msg : Eq, Model, View : Eq] Program::stateful_cmd(
  runtime : @incr.Runtime,
  initial : Model,
  update : (Msg, Model) -> (Model, Cmd[Msg]),
  view : (Model) -> View,
  subscriptions? : (Model) -> Subscriptions[Msg],
  label? : String,
) -> Program[Msg, View]
```

`view` and `subscriptions` take non-raising functions; internal adapter closures
(`view_fn`, `subs_closure`) carry `raise Failure` for `Scope::derived`. MoonBit
accepts non-raising functions where `raise Failure` is expected, so callers need
no annotation. Any errors raised inside adapters surface as aborts via
`read_or_abort` — they are defects, not recoverable failures.

## Internal Wiring

Both functions share the same wiring; `stateful` wraps `update` with
`Cmd::none()`.

```
stateful / stateful_cmd
  ├─ Scope::new(runtime)               — owned by returned Program
  ├─ Ref(initial)                      — captured by closures, alive as long as Program
  ├─ scope.input_field(0,              — version cell
  │      label?= label + ".version")
  ├─ update_fn : (Msg) -> Cmd[Msg]
  │    applies update(msg, state.val)
  │    sets state.val = new_model
  │    bumps version.set(version.peek() + 1)
  │    returns cmd (or Cmd::none() for stateful)
  ├─ view_fn : () -> View raise Failure
  │    ignore(version.get())           — tracks version dependency
  │    view(state.val)                 — calls user's view with current model
  └─ if subscriptions is Some(subs_fn):
       subs_closure : () -> Subscriptions[Msg] raise Failure
         ignore(version.get())
         subs_fn(state.val)
       → Program::with_subscriptions(runtime, scope, update_fn, view_fn, subs_closure,
                                     label?=label + ".subscriptions")
     else:
       → Program::Program(runtime, scope, update_fn, view_fn, label?)
```

Labels:
- Version cell: `label + ".version"` when label provided, unlabeled otherwise.
- Subscriptions root label: passed as `label?` to `with_subscriptions`
  (which uses it for the view root; subscriptions derived root gets no label
  from `with_subscriptions` today — this is pre-existing, not introduced here).

## Lifecycle / Disposal

`scope` is passed into `Program::Program` / `Program::with_subscriptions` and
owned by the returned `Program`. `program.dispose()` disposes the scope,
which disposes the version cell and view/subscription roots — identical
lifecycle to the hand-written boilerplate.

The `Ref[Model]` and `InputField[Int]` are captured by the `update_fn` and
`view_fn` closures. They are kept alive for the lifetime of `Program` and
released when the program is GC'd after disposal.

## Counter Migration (before/after)

**Before:**
```moonbit
priv struct App {
  program : @tea.Program[Msg, @tea.Html[Msg]]
  _state : Ref[Model]
}

fn App::App(runtime : @incr.Runtime) -> App {
  let scope = @incr.Scope::new(runtime)
  let state = Ref({ count: 0 })
  let version = scope.input_field(0, label="7guis.counter.version")
  let update : (Msg) -> @tea.Cmd[Msg] = msg => {
    state.val = update_model(msg, state.val)
    version.set(version.peek() + 1)
    @tea.Cmd::none()
  }
  let view : () -> @tea.Html[Msg] raise Failure = () => {
    ignore(version.get())
    view_model(state.val)
  }
  let program = @tea.Program::Program(
    runtime, scope, update, view, label="7guis.counter.view",
  )
  { program, _state: state }
}

pub fn mount(host : @tea.DomElement) -> Unit {
  let runtime = @incr.Runtime()
  let app = App(runtime)
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(renderer.mount(host, app.program))
}
```

**After:**
```moonbit
pub fn mount(host : @tea.DomElement) -> Unit {
  let runtime = @incr.Runtime()
  let program = @tea.Program::stateful(
    runtime,
    { count: 0 },
    update_model,
    view_model,
    label="7guis.counter.view",
  )
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(renderer.mount(host, program))
}
```

`App` struct and `App::App` constructor are eliminated.

## Acceptance Criteria

- `Program::stateful` and `Program::stateful_cmd` implemented in `program.mbt`.
- Counter (`incr_tea_7guis/counter/counter.mbt`) migrated to `stateful`.
- `moon check --target js examples/incr_tea_7guis` passes.
- `moon test --target js examples/incr_tea` and `moon test --target js examples/incr_tea_7guis` pass.
- `Program::Program` and `Program::with_subscriptions` remain unchanged.

## Non-Goals

- Exposing `stateful` in the stable `dowdiness/incr` module.
- Supporting view errors other than `Failure` (callers needing custom errors must use `Program::Program` directly).
- Migrating all 7GUIs apps (Counter is sufficient for the initial PR; others may follow).
