///|
/// Experimental TEA program shell backed by `@incr`.
///
/// A program owns a component `Scope`, runs each message through
/// `Runtime::batch`, and exposes the pure view through a persistent `Watch`.
/// It is intentionally small: subscriptions, rAF, DOM rendering, and async
/// command adapters are follow-up edges for the Incremental TEA prototype.
struct Program[Msg, View] {
  runtime : @incr.Runtime
  scope : @incr.Scope
  update : (Msg) -> Cmd[Msg]
  messages : @queue.Queue[Msg]
  mut is_draining : Bool
  view_watch : @incr.Watch[View]
  subscriptions_watch : @incr.Watch[Subscriptions[Msg]]?
  sub_manager : SubscriptionsManager[Msg]?
  _view_id : @incr.CellId
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
  update : (Msg) -> Cmd[Msg],
  view : () -> View raise Failure,
  label? : String,
) -> Program[Msg, View] {
  guard !scope.is_disposed() else {
    abort("Program::Program called with a disposed scope")
  }
  let view_root = scope.derived(view, label?)
  let view_watch = scope.add_watch(view_root.watch())
  ignore(view_watch.read_or_abort())

  {
    runtime,
    scope,
    update,
    messages: @queue.Queue([]),
    is_draining: false,
    view_watch,
    subscriptions_watch: None,
    sub_manager: None,
    _view_id: view_root.id(),
  }
}

///|
/// Creates a mounted program with an additional tracked subscription spec root.
///
/// The `subscriptions` closure is evaluated as a tracked `Derived` and compared
/// against the previous rendered subscriptions after each handled message.
fn[Msg : Eq, View : Eq] Program::with_subscriptions(
  runtime : @incr.Runtime,
  scope : @incr.Scope,
  update : (Msg) -> Cmd[Msg],
  view : () -> View raise Failure,
  subscriptions : () -> Subscriptions[Msg] raise Failure,
  label? : String,
) -> Program[Msg, View] {
  guard !scope.is_disposed() else {
    abort("Program::with_subscriptions called with a disposed scope")
  }
  let view_root = scope.derived(view, label?)
  let view_watch = scope.add_watch(view_root.watch())
  ignore(view_watch.read_or_abort())
  let subscriptions_root = scope.derived(subscriptions)
  let subscriptions_watch = scope.add_watch(subscriptions_root.watch())
  ignore(subscriptions_watch.read_or_abort())
  let program = {
    runtime,
    scope,
    update,
    messages: @queue.Queue([]),
    is_draining: false,
    view_watch,
    subscriptions_watch: Some(subscriptions_watch),
    sub_manager: Some(SubscriptionsManager::SubscriptionsManager()),
    _view_id: view_root.id(),
  }
  program.reconcile_subscriptions()
  program
}

///|
/// Dispatches one message into the scheduler.
///
/// Returns `false` when the component has already been disposed; this prototype
/// ignores post-disposal messages deterministically instead of aborting.
fn[Msg, View] Program::dispatch(self : Program[Msg, View], msg : Msg) -> Bool {
  guard !self.scope.is_disposed() else { false }
  self.messages.push(msg)
  if !self.is_draining {
    self.drain_messages()
  }
  true
}

///|
fn[Msg, View] Program::drain_messages(self : Program[Msg, View]) -> Unit {
  guard !self.is_draining else { return }
  self.is_draining = true
  while self.messages.pop() is Some(msg) {
    self.handle_message(msg)
  }
  self.is_draining = false
}

///|
fn[Msg, View] Program::handle_message(
  self : Program[Msg, View],
  msg : Msg,
) -> Unit {
  guard !self.scope.is_disposed() else { return }
  let cmd : Ref[Cmd[Msg]] = Ref(Cmd::none())
  self.runtime.batch(() => cmd.val = (self.update)(msg))
  self.run_cmd(cmd.val)
  self.reconcile_subscriptions()
}

///|
fn[Msg, View] Program::run_cmd(
  self : Program[Msg, View],
  cmd : Cmd[Msg],
) -> Unit {
  guard !self.scope.is_disposed() else { return }
  match cmd.command {
    None => ()
    Batch(cmds) =>
      for next in cmds {
        self.run_cmd(next)
      }
    Message(msg) => self.messages.push(msg)
    Effect(callback) => callback(next => self.run_cmd(next))
  }
}

///|
fn[Msg, View] Program::reconcile_subscriptions(
  self : Program[Msg, View],
) -> Unit {
  match (self.subscriptions_watch, self.sub_manager) {
    (Some(watch), Some(manager)) => {
      let desired = watch.read_or_abort()
      manager.reconcile(desired, msg => ignore(self.dispatch(msg)))
    }
    _ => ()
  }
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
  match self.sub_manager {
    Some(manager) => manager.dispose()
    None => ()
  }
  self.scope.dispose()
}
