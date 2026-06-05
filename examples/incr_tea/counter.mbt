///|
/// Messages understood by the Incremental TEA counter demo.
pub(all) enum CounterMsg {
  Increment
  Decrement
  Reset
  SetTitle(String)
  SetCount(Int)
  SetUnrelated(Int)
  SetBoth(next_count~ : Int, next_title~ : String)
} derive(Debug)

///|
/// Pure view data produced by the counter's tracked view computation.
pub(all) struct CounterView {
  title : String
  count : Int
} derive(Eq, Debug)

///|
/// Minimal counter component demonstrating field-level incremental views.
///
/// `count`, `title`, and `unrelated` are separate `InputField` values owned by
/// the component scope. The watched view reads only `count` and `title`, so
/// updating `unrelated` leaves the view root fresh.
pub struct CounterApp {
  priv program : Program[CounterMsg, CounterView]
  priv count : @incr.InputField[Int]
  priv title : @incr.InputField[String]
  priv unrelated : @incr.InputField[Int]
}

///|
/// Creates a counter app with a fresh `Runtime`.
pub fn CounterApp::CounterApp() -> CounterApp {
  CounterApp::with_runtime(@incr.Runtime())
}

///|
/// Creates a counter app on an existing `Runtime`.
pub fn CounterApp::with_runtime(runtime : @incr.Runtime) -> CounterApp {
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="counter.count")
  let title = scope.input_field("Counter", label="counter.title")
  let unrelated = scope.input_field(0, label="counter.unrelated")
  let update : (CounterMsg) -> Unit = (msg : CounterMsg) => {
    match msg {
      Increment => count.set(count.peek() + 1)
      Decrement => count.set(count.peek() - 1)
      Reset => count.set(0)
      SetTitle(next) => title.set(next)
      SetCount(next) => count.set(next)
      SetUnrelated(next) => unrelated.set(next)
      SetBoth(next_count~, next_title~) => {
        count.set(next_count)
        title.set(next_title)
      }
    }
  }
  let view : () -> CounterView raise Failure = () => {
    title: title.get(),
    count: count.get(),
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="counter.view",
  )
  { program, count, title, unrelated }
}

///|
/// Dispatches one counter message.
pub fn CounterApp::dispatch(self : CounterApp, msg : CounterMsg) -> Bool {
  self.program.dispatch(msg)
}

///|
/// Reads the current view, or `None` after disposal.
pub fn CounterApp::view(self : CounterApp) -> CounterView? {
  self.program.read_view()
}

///|
/// Reads the current view and aborts after disposal.
pub fn CounterApp::view_or_abort(self : CounterApp) -> CounterView {
  self.program.read_view_or_abort()
}

///|
/// Returns the current committed count field without recording a dependency,
/// or `None` after disposal.
pub fn CounterApp::count(self : CounterApp) -> Int? {
  if self.is_mounted() {
    Some(self.count.peek())
  } else {
    None
  }
}

///|
/// Returns the current committed title field without recording a dependency,
/// or `None` after disposal.
pub fn CounterApp::title(self : CounterApp) -> String? {
  if self.is_mounted() {
    Some(self.title.peek())
  } else {
    None
  }
}

///|
/// Returns the current committed unrelated field without recording a dependency,
/// or `None` after disposal.
pub fn CounterApp::unrelated(self : CounterApp) -> Int? {
  if self.is_mounted() {
    Some(self.unrelated.peek())
  } else {
    None
  }
}

///|
/// Returns the runtime backing this counter app.
pub fn CounterApp::runtime(self : CounterApp) -> @incr.Runtime {
  self.program.runtime()
}

///|
/// Returns whether the counter component is still mounted.
pub fn CounterApp::is_mounted(self : CounterApp) -> Bool {
  self.program.is_mounted()
}

///|
/// Disposes the counter component scope.
pub fn CounterApp::dispose(self : CounterApp) -> Unit {
  self.program.dispose()
}
