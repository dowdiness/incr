///|
/// Experimental TEA program shell backed by `@incr`.
///
/// A program owns a component `Scope`, runs each message through
/// `Runtime::batch`, and exposes the pure view through a persistent `Watch`.
/// It is intentionally small: command scheduling, subscriptions, rAF, and DOM
/// rendering are follow-up edges for the Incremental TEA prototype.
struct Program[Msg, View] {
  runtime : @incr.Runtime
  scope : @incr.Scope
  update : (Msg) -> Unit
  view_watch : @incr.Watch[View]
}

///|
/// Creates a mounted program with a watched tracked view root.
///
/// The constructor registers the `Derived` view with `scope`, registers its
/// `Watch` with the same scope, and primes the watch once so `Runtime::gc()` can
/// see the view root's current upstream dependencies before the first external
/// read.
fn[Msg, View : Eq] Program::Program(
  runtime : @incr.Runtime,
  scope : @incr.Scope,
  update : (Msg) -> Unit,
  view : () -> View raise Failure,
  label? : String,
) -> Program[Msg, View] {
  guard !scope.is_disposed() else {
    abort("Program::Program called with a disposed scope")
  }
  let view_root = scope.derived(view, label?)
  let view_watch = scope.add_watch(view_root.watch())
  ignore(view_watch.read_or_abort())
  { runtime, scope, update, view_watch }
}

///|
/// Dispatches one message inside `Runtime::batch`.
///
/// Returns `false` when the component has already been disposed; this prototype
/// ignores post-disposal messages deterministically instead of aborting.
fn[Msg, View] Program::dispatch(self : Program[Msg, View], msg : Msg) -> Bool {
  guard !self.scope.is_disposed() else { false }
  self.runtime.batch(() => (self.update)(msg))
  true
}

///|
/// Reads the current watched view, or `None` after disposal.
fn[Msg, View] Program::read_view(self : Program[Msg, View]) -> View? {
  if self.scope.is_disposed() {
    None
  } else {
    Some(self.view_watch.read_or_abort())
  }
}

///|
/// Reads the current watched view and aborts if the program has been disposed.
fn[Msg, View] Program::read_view_or_abort(self : Program[Msg, View]) -> View {
  match self.read_view() {
    Some(view) => view
    None => abort("Program::read_view_or_abort called after dispose")
  }
}

///|
/// Returns the runtime backing this program.
fn[Msg, View] Program::runtime(self : Program[Msg, View]) -> @incr.Runtime {
  self.runtime
}

///|
/// Returns whether the component instance has been disposed.
fn[Msg, View] Program::is_disposed(self : Program[Msg, View]) -> Bool {
  self.scope.is_disposed()
}

///|
/// Disposes the component scope, including the watched view root.
///
/// Disposal is idempotent.
fn[Msg, View] Program::dispose(self : Program[Msg, View]) -> Unit {
  self.scope.dispose()
}
