// Drift-catch for README.md and docs/getting-started.md.
// If the public API surface used by the README's quickstart changes signature,
// this test fails and prompts a docs update.

///|
struct QuickstartApp {
  rt : Runtime
}

///|
fn QuickstartApp::QuickstartApp() -> QuickstartApp {
  { rt: Runtime() }
}

///|
impl @incr.Database for QuickstartApp with runtime(self) {
  self.rt
}

///|
test "quickstart: database pattern from README" {
  let app = QuickstartApp::QuickstartApp()
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
