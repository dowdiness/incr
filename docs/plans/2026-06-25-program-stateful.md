# `Program::stateful` and `Program::stateful_cmd` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Program::stateful` and `Program::stateful_cmd` helpers to `examples/incr_tea/program.mbt` that hide the version-cell boilerplate, then migrate the Counter 7GUIs app to use them.

**Architecture:** Both helpers create their own `@incr.Scope`, a `Ref[Model]`, and a version `InputField[Int]` internally, then wire the user's pure `update`/`view`/`subscriptions` functions into the closures that `Program::Program` and `Program::with_subscriptions` expect. They return a plain `Program[Msg, View]` — no wrapper struct. `stateful` wraps `update` with `Cmd::none()`; `stateful_cmd` passes through the `(Model, Cmd[Msg])` tuple.

**Tech Stack:** MoonBit, `dowdiness/incr` reactive cells, `examples/incr_tea` TEA shell.

## Global Constraints

- All commands run from the workspace root: `/path/to/loom/incr/`
- `examples/incr_tea` has `preferred_target = "js"` — `moon test examples/incr_tea` uses JS automatically
- `examples/incr_tea_7guis/counter` has `supported_targets = "js"` — JS only
- Do NOT modify `Program::Program` or `Program::with_subscriptions`
- `stateful`/`stateful_cmd` live in `examples/incr_tea/program.mbt` only — not in `incr/`
- Use `raise?` (error polymorphism) on `view` and `subscriptions` parameters; fall back to `raise Failure` if the MoonBit compiler rejects the `raise?` form in that position
- After every file edit, run `moon check examples/incr_tea` before continuing

---

## Files

- **Modify:** `examples/incr_tea/program.mbt` — add `Program::stateful` and `Program::stateful_cmd`
- **Create:** `examples/incr_tea/stateful_test.mbt` — blackbox tests for both helpers
- **Modify:** `examples/incr_tea_7guis/counter/counter.mbt` — delete `App` struct and `App::App`, update `mount`
- **Modify:** `examples/incr_tea_7guis/counter/counter_wbtest.mbt` — rewrite test to use `Program::stateful` directly

---

## Task 1: Implement `Program::stateful` (TDD)

**Files:**
- Create: `examples/incr_tea/stateful_test.mbt`
- Modify: `examples/incr_tea/program.mbt`

**Interfaces:**
- Produces: `Program::stateful(runtime, initial, update, view, subscriptions?, label?) -> Program[Msg, View]`

---

- [ ] **Step 1: Create the test file with failing tests**

Create `examples/incr_tea/stateful_test.mbt`:

```moonbit
///|
priv struct SModel {
  count : Int
} derive(Eq, Debug)

///|
priv enum SMsg {
  Inc
  Dec
  Reset
} derive(Eq)

///|
fn s_update(msg : SMsg, model : SModel) -> SModel {
  match msg {
    Inc => { count: model.count + 1 }
    Dec => { count: model.count - 1 }
    Reset => { count: 0 }
  }
}

///|
fn s_view(model : SModel) -> Int {
  model.count
}

///|
test "stateful: initial view reflects initial model" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful(
    runtime,
    { count: 0 },
    s_update,
    s_view,
  )
  inspect(program.read_view_or_abort(), content="0")
  program.dispose()
}

///|
test "stateful: dispatch updates view" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful(
    runtime,
    { count: 0 },
    s_update,
    s_view,
  )
  ignore(program.dispatch(Inc))
  inspect(program.read_view_or_abort(), content="1")
  program.dispose()
}

///|
test "stateful: multiple dispatches accumulate correctly" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful(
    runtime,
    { count: 0 },
    s_update,
    s_view,
  )
  ignore(program.dispatch(Inc))
  ignore(program.dispatch(Inc))
  ignore(program.dispatch(Dec))
  inspect(program.read_view_or_abort(), content="1")
  program.dispose()
}

///|
test "stateful: disposal makes dispatch return false and view return None" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful(
    runtime,
    { count: 0 },
    s_update,
    s_view,
  )
  program.dispose()
  inspect(program.is_disposed(), content="true")
  inspect(program.dispatch(Inc), content="false")
  debug_inspect(program.read_view(), content="None")
}

///|
test "stateful: gc after mount preserves watched view" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful(
    runtime,
    { count: 0 },
    s_update,
    s_view,
  )
  runtime.gc()
  ignore(program.dispatch(Inc))
  inspect(program.read_view_or_abort(), content="1")
  program.dispose()
}

///|
test "stateful: subscriptions=None still works correctly" {
  let runtime = @incr.Runtime()
  let program : @incr_tea.Program[SMsg, Int] = @incr_tea.Program::stateful(
    runtime,
    { count: 0 },
    s_update,
    s_view,
    subscriptions=fn(_model) { @hashmap.HashMap([]) },
  )
  ignore(program.dispatch(Inc))
  inspect(program.read_view_or_abort(), content="1")
  program.dispose()
}
```

- [ ] **Step 2: Verify tests fail to compile (stateful not yet defined)**

```bash
moon check examples/incr_tea
```

Expected: error like `Value stateful not found in package` or similar — confirms the tests are wired up correctly.

- [ ] **Step 3: Implement `Program::stateful` in `program.mbt`**

Open `examples/incr_tea/program.mbt` and append at the end of the file:

```moonbit
///|
/// Convenience constructor that hides the version-cell boilerplate for
/// mutable-model apps.
///
/// Creates its own `Scope`, a `Ref[Model]`, and an `InputField[Int]` version
/// cell internally. The user supplies pure `update` and `view` functions that
/// take the model directly. The version bump and tracked read are wired
/// automatically.
///
/// Errors raised by `view` or `subscriptions` are captured by their `Derived`
/// cells and surface as aborts through `read_or_abort` — they are defects, not
/// recoverable failures.
pub fn[Msg : Eq, Model, View : Eq] Program::stateful(
  runtime : @incr.Runtime,
  initial : Model,
  update : (Msg, Model) -> Model,
  view : (Model) -> View raise?,
  subscriptions? : (Model) -> Subscriptions[Msg] raise?,
  label? : String,
) -> Program[Msg, View] {
  let scope = @incr.Scope::new(runtime)
  let state : Ref[Model] = { val: initial }
  let version = scope.input_field(
    0,
    label?=label.map(fn(l) { l + ".version" }),
  )
  let update_fn : (Msg) -> Cmd[Msg] = msg => {
    state.val = update(msg, state.val)
    version.set(version.peek() + 1)
    Cmd::none()
  }
  let view_fn : () -> View raise Failure = () => {
    ignore(version.get())
    view(state.val)
  }
  match subscriptions {
    None => Program::Program(runtime, scope, update_fn, view_fn, label?)
    Some(subs_fn) => {
      let subs : () -> Subscriptions[Msg] raise Failure = () => {
        ignore(version.get())
        subs_fn(state.val)
      }
      Program::with_subscriptions(
        runtime,
        scope,
        update_fn,
        view_fn,
        subs,
        label?,
      )
    }
  }
}
```

> **Note on `raise?`:** If the compiler rejects `view : (Model) -> View raise?` in the position of a function type passed to `view_fn : () -> View raise Failure`, change the parameter to `view : (Model) -> View raise Failure`. The behavior is identical — MoonBit lets noraise functions be passed where `raise Failure` is expected. Apply the same fallback to `subscriptions?`.

- [ ] **Step 4: Check that it compiles**

```bash
moon check examples/incr_tea
```

Expected: no errors.

- [ ] **Step 5: Run the stateful tests**

```bash
moon test examples/incr_tea -f stateful_test.mbt
```

Expected: all 6 tests pass.

- [ ] **Step 6: Run the full incr_tea test suite (regression check)**

```bash
moon test examples/incr_tea
```

Expected: all tests pass (same count as before plus 6 new ones).

- [ ] **Step 7: Commit**

```bash
git add examples/incr_tea/program.mbt examples/incr_tea/stateful_test.mbt
git commit -m "feat(incr_tea): add Program::stateful helper (#287)"
```

---

## Task 2: Implement `Program::stateful_cmd` (TDD)

**Files:**
- Modify: `examples/incr_tea/stateful_test.mbt`
- Modify: `examples/incr_tea/program.mbt`

**Interfaces:**
- Consumes: `Program::stateful` (Task 1)
- Produces: `Program::stateful_cmd(runtime, initial, update, view, subscriptions?, label?) -> Program[Msg, View]` where `update : (Msg, Model) -> (Model, Cmd[Msg])`

---

- [ ] **Step 1: Add failing tests for `stateful_cmd` to `stateful_test.mbt`**

Append to `examples/incr_tea/stateful_test.mbt`:

```moonbit
///|
/// Messages for the stateful_cmd tests — IncTwice chains a follow-up Inc.
priv enum CMsg {
  CInc
  CIncTwice
  CReset
} derive(Eq)

///|
fn c_update(msg : CMsg, model : SModel) -> (SModel, @incr_tea.Cmd[CMsg]) {
  match msg {
    CInc => ({ count: model.count + 1 }, @incr_tea.Cmd::none())
    CIncTwice => ({ count: model.count + 1 }, @incr_tea.Cmd::message(CInc))
    CReset => ({ count: 0 }, @incr_tea.Cmd::none())
  }
}

///|
test "stateful_cmd: initial view reflects initial model" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful_cmd(
    runtime,
    { count: 0 },
    c_update,
    s_view,
  )
  inspect(program.read_view_or_abort(), content="0")
  program.dispose()
}

///|
test "stateful_cmd: Cmd::none() update works as plain dispatch" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful_cmd(
    runtime,
    { count: 0 },
    c_update,
    s_view,
  )
  ignore(program.dispatch(CInc))
  inspect(program.read_view_or_abort(), content="1")
  program.dispose()
}

///|
test "stateful_cmd: Cmd::message triggers follow-up dispatch" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful_cmd(
    runtime,
    { count: 0 },
    c_update,
    s_view,
  )
  // CIncTwice increments to 1 and queues CInc which increments to 2
  ignore(program.dispatch(CIncTwice))
  inspect(program.read_view_or_abort(), content="2")
  program.dispose()
}

///|
test "stateful_cmd: disposal makes dispatch return false" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful_cmd(
    runtime,
    { count: 0 },
    c_update,
    s_view,
  )
  program.dispose()
  inspect(program.is_disposed(), content="true")
  inspect(program.dispatch(CInc), content="false")
  debug_inspect(program.read_view(), content="None")
}

///|
test "stateful_cmd: gc after mount preserves view" {
  let runtime = @incr.Runtime()
  let program = @incr_tea.Program::stateful_cmd(
    runtime,
    { count: 0 },
    c_update,
    s_view,
  )
  runtime.gc()
  ignore(program.dispatch(CInc))
  inspect(program.read_view_or_abort(), content="1")
  program.dispose()
}
```

- [ ] **Step 2: Verify tests fail to compile**

```bash
moon check examples/incr_tea
```

Expected: error about `stateful_cmd` not found.

- [ ] **Step 3: Implement `Program::stateful_cmd` in `program.mbt`**

Append immediately after `Program::stateful` in `examples/incr_tea/program.mbt`:

```moonbit
///|
/// Convenience constructor like `Program::stateful` but with full Cmd support.
///
/// The `update` function returns `(Model, Cmd[Msg])` — use `Cmd::none()` for
/// updates that need no follow-up effects.
pub fn[Msg : Eq, Model, View : Eq] Program::stateful_cmd(
  runtime : @incr.Runtime,
  initial : Model,
  update : (Msg, Model) -> (Model, Cmd[Msg]),
  view : (Model) -> View raise?,
  subscriptions? : (Model) -> Subscriptions[Msg] raise?,
  label? : String,
) -> Program[Msg, View] {
  let scope = @incr.Scope::new(runtime)
  let state : Ref[Model] = { val: initial }
  let version = scope.input_field(
    0,
    label?=label.map(fn(l) { l + ".version" }),
  )
  let update_fn : (Msg) -> Cmd[Msg] = msg => {
    let (new_model, cmd) = update(msg, state.val)
    state.val = new_model
    version.set(version.peek() + 1)
    cmd
  }
  let view_fn : () -> View raise Failure = () => {
    ignore(version.get())
    view(state.val)
  }
  match subscriptions {
    None => Program::Program(runtime, scope, update_fn, view_fn, label?)
    Some(subs_fn) => {
      let subs : () -> Subscriptions[Msg] raise Failure = () => {
        ignore(version.get())
        subs_fn(state.val)
      }
      Program::with_subscriptions(
        runtime,
        scope,
        update_fn,
        view_fn,
        subs,
        label?,
      )
    }
  }
}
```

- [ ] **Step 4: Check and test**

```bash
moon check examples/incr_tea && moon test examples/incr_tea -f stateful_test.mbt
```

Expected: all tests pass (the 6 from Task 1 plus 5 new cmd tests = 11 total).

- [ ] **Step 5: Full regression check**

```bash
moon test examples/incr_tea
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add examples/incr_tea/program.mbt examples/incr_tea/stateful_test.mbt
git commit -m "feat(incr_tea): add Program::stateful_cmd helper (#287)"
```

---

## Task 3: Migrate Counter to `Program::stateful`

**Files:**
- Modify: `examples/incr_tea_7guis/counter/counter.mbt`
- Modify: `examples/incr_tea_7guis/counter/counter_wbtest.mbt`

**Interfaces:**
- Consumes: `Program::stateful` (Task 1)

---

- [ ] **Step 1: Rewrite `counter.mbt`**

Replace the full contents of `examples/incr_tea_7guis/counter/counter.mbt` with:

```moonbit
///|
priv struct Model {
  count : Int
}

///|
enum Msg {
  Increment
  Reset
} derive(Eq)

///|
fn update_model(msg : Msg, model : Model) -> Model {
  match msg {
    Increment => { count: model.count + 1 }
    Reset => { count: 0 }
  }
}

///|
fn view_model(model : Model) -> @tea.Html[Msg] {
  @tea.article(attrs=[@tea.class_attr("task-card")], [
    @tea.div(attrs=[@tea.class_attr("task-heading")], [
      @tea.h2([@tea.text("Counter")]),
      @tea.p([@tea.text("Smallest possible model/update/view loop.")]),
    ]),
    @tea.div(attrs=[@tea.class_attr("task-body")], [
      @tea.div(attrs=[@tea.class_attr("counter-readout")], [
        @tea.text("\{model.count}"),
      ]),
      @tea.div(attrs=[@tea.class_attr("button-row")], [
        @tea.button(
          attrs=button_attrs(),
          events=[@tea.on_click(Increment)],
          "Count",
        ),
        @tea.button(
          attrs=button_attrs(),
          events=[@tea.on_click(Reset)],
          "Reset",
        ),
      ]),
    ]),
  ])
}

///|
fn button_attrs() -> Array[@tea.Attribute] {
  @tea.Attrs::build().attr("type", "button").to_array()
}

///|
/// Mounts the Counter task into `host` with its own runtime and browser renderer.
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

- [ ] **Step 2: Rewrite `counter_wbtest.mbt`**

Replace the full contents of `examples/incr_tea_7guis/counter/counter_wbtest.mbt` with:

```moonbit
///|
test "counter dispatch updates view state" {
  let runtime = @incr.Runtime()
  let program : @tea.Program[Msg, @tea.Html[Msg]] = @tea.Program::stateful(
    runtime,
    { count: 0 },
    update_model,
    view_model,
    label="7guis.counter.view",
  )
  let initial = program.read_view_or_abort()
  ignore(program.dispatch(Increment))
  let after_increment = program.read_view_or_abort()

  inspect(initial == view_model({ count: 0 }), content="true")
  inspect(after_increment == view_model({ count: 1 }), content="true")
  inspect(initial == after_increment, content="false")
  program.dispose()
}
```

- [ ] **Step 3: Check the 7guis module**

```bash
moon check examples/incr_tea_7guis
```

Expected: no errors.

- [ ] **Step 4: Run all tests**

```bash
moon test examples/incr_tea && moon test examples/incr_tea_7guis
```

Expected: all tests pass. The counter wbtest (1 test) passes.

- [ ] **Step 5: Regenerate interfaces**

```bash
moon info examples/incr_tea && moon fmt examples/incr_tea
moon info examples/incr_tea_7guis && moon fmt examples/incr_tea_7guis
```

Check that `pkg.generated.mbti` changes are only the expected additions (`Program::stateful`, `Program::stateful_cmd` appear; no unexpected removals from counter's public API — `mount` is unchanged).

```bash
git diff examples/incr_tea/pkg.generated.mbti
git diff examples/incr_tea_7guis/counter/pkg.generated.mbti
```

Expected for incr_tea: two new method signatures added.
Expected for counter: no changes (only `mount` is public, and it's unchanged).

- [ ] **Step 6: Commit**

```bash
git add examples/incr_tea/program.mbt \
        examples/incr_tea/pkg.generated.mbti \
        examples/incr_tea_7guis/counter/counter.mbt \
        examples/incr_tea_7guis/counter/counter_wbtest.mbt \
        examples/incr_tea_7guis/counter/pkg.generated.mbti
git commit -m "feat(incr_tea_7guis): migrate Counter to Program::stateful (#287)"
```
