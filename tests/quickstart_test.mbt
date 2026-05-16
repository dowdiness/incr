// Drift-catch for README.md and docs/getting-started.md.
// If the public API surface used by the README's quickstart changes signature,
// this test fails and prompts a docs update.

///|
struct QuickstartApp {
  rt : Runtime
}

///|
// Mirrors README.md's "Database Pattern" exactly: `Runtime::new()` in the body,
// `MyApp()` constructor sugar at the call site. Any drift in the README's
// chosen idiom is supposed to break here.
fn QuickstartApp::QuickstartApp() -> QuickstartApp {
  { rt: Runtime::new() }
}

///|
impl @incr.Database for QuickstartApp with runtime(self) {
  self.rt
}

///|
test "quickstart: database pattern from README" {
  let app = QuickstartApp()
  let x = @incr.create_signal(app, 10)
  let y = @incr.create_signal(app, 20)
  let sum = @incr.create_memo(app, () => x.get() + y.get())
  // `.get()` is only legal inside a memo compute. Outside the graph
  // (top-level, tests, event handlers) use `rt.read(memo)` which
  // observes once and disposes.
  inspect(app.runtime().read(sum), content="30")
  x.set(5)
  inspect(app.runtime().read(sum), content="25")
}
