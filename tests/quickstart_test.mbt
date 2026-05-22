// Drift-catch for README.md and docs/getting-started.md.
// If the public API surface used by the README's quickstart changes signature,
// this test fails and prompts a docs update.

///|
struct QuickstartApp {
  rt : Runtime
}

///|
// Mirrors README.md's "RuntimeContext Pattern" exactly: `Runtime::new()` in
// the body, `MyApp()` constructor sugar at the call site. Any drift in the
// README's chosen idiom is supposed to break here.
fn QuickstartApp::QuickstartApp() -> QuickstartApp {
  { rt: Runtime::new() }
}

///|
impl @incr.RuntimeContext for QuickstartApp with runtime(self) {
  self.rt
}

///|
test "quickstart: runtime context pattern from README" {
  let app = QuickstartApp()
  let x = @incr.create_input(app, 10)
  let y = @incr.create_input(app, 20)
  let sum = @incr.create_derived(app, () => x.get() + y.get())
  inspect(sum.read_or_abort(), content="30")
  x.set(5)
  inspect(sum.read_or_abort(), content="25")
}
