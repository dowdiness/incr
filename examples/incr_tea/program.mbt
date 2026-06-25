///|
/// Experimental TEA program shell backed by `@incr`.
///
/// A program owns a component `Scope`, runs each message through
/// `Runtime::batch`, and exposes the pure view through a persistent `Watch`.
/// It is intentionally small: subscriptions, rAF, DOM rendering, and async
/// command adapters are follow-up edges for the Incremental TEA prototype.
pub struct Program[Msg, View] {
  priv runtime : @incr.Runtime
  priv scope : @incr.Scope
  priv update : (Msg) -> Cmd[Msg]
  priv messages : @queue.Queue[Msg]
  priv after_flush : @queue.Queue[((Cmd[Msg]) -> Unit) -> Unit]
  priv after_flush_schedulers : Array[() -> Unit]
  priv mut is_draining : Bool
  priv view_watch : @incr.Watch[View]
  priv subscriptions_watch : @incr.Watch[Subscriptions[Msg]]?
  priv sub_manager : SubscriptionsManager[Msg]?
  priv _view_id : @incr.CellId
}

///|
/// Creates a mounted program with a watched tracked view root.
///
/// The constructor registers the `Derived` view with `scope`, registers its
/// `Watch` with the same scope, and primes the watch once so `Runtime::gc()` can
/// see the view root's current upstream dependencies before the first external
/// read.
pub fn[Msg, View : Eq] Program::Program(
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
  guard view_root.id().runtime_id == runtime.id() else {
    abort("Program::Program called with a scope from another Runtime")
  }
  let view_watch = scope.add_watch(view_root.watch())
  ignore(view_watch.read_or_abort())

  {
    runtime,
    scope,
    update,
    messages: @queue.Queue([]),
    after_flush: @queue.Queue([]),
    after_flush_schedulers: [],
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
pub fn[Msg : Eq, View : Eq] Program::with_subscriptions(
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
  guard view_root.id().runtime_id == runtime.id() else {
    abort(
      "Program::with_subscriptions called with a scope from another Runtime",
    )
  }
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
    after_flush: @queue.Queue([]),
    after_flush_schedulers: [],
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
pub fn[Msg, View] Program::dispatch(
  self : Program[Msg, View],
  msg : Msg,
) -> Bool {
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
    AfterFlush(callback) => {
      self.after_flush.push(callback)
      self.request_after_flush()
    }
  }
}

///|
fn[Msg, View] Program::add_after_flush_scheduler(
  self : Program[Msg, View],
  schedule : () -> Unit,
) -> Unit {
  self.after_flush_schedulers.push(schedule)
}

///|
fn[Msg, View] Program::request_after_flush(self : Program[Msg, View]) -> Unit {
  for schedule in self.after_flush_schedulers {
    schedule()
  }
}

///|
fn[Msg, View] Program::drain_after_flush(self : Program[Msg, View]) -> Unit {
  guard !self.scope.is_disposed() else { return }
  let count = self.after_flush.length()
  for _ in 0..<count {
    guard !self.scope.is_disposed() else { return }
    match self.after_flush.pop() {
      Some(callback) => {
        callback(next => self.run_cmd(next))
        if !self.is_draining {
          self.drain_messages()
        }
      }
      None => ()
    }
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
pub fn[Msg, View] Program::read_view(self : Program[Msg, View]) -> View? {
  if self.scope.is_disposed() {
    None
  } else {
    Some(self.view_watch.read_or_abort())
  }
}

///|
/// Reads the current watched view and aborts if the program has been disposed.
pub fn[Msg, View] Program::read_view_or_abort(
  self : Program[Msg, View],
) -> View {
  match self.read_view() {
    Some(view) => view
    None => abort("Program::read_view_or_abort called after dispose")
  }
}

///|
/// Returns the runtime backing this program.
pub fn[Msg, View] Program::runtime(self : Program[Msg, View]) -> @incr.Runtime {
  self.runtime
}

///|
/// Returns whether the component instance has been disposed.
pub fn[Msg, View] Program::is_disposed(self : Program[Msg, View]) -> Bool {
  self.scope.is_disposed()
}

///|
/// Disposes the component scope, including the watched view root.
///
/// Disposal is idempotent.
pub fn[Msg, View] Program::dispose(self : Program[Msg, View]) -> Unit {
  match self.sub_manager {
    Some(manager) => manager.dispose()
    None => ()
  }
  self.scope.dispose()
}

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
  view : (Model) -> View,
  subscriptions? : (Model) -> Subscriptions[Msg],
  label? : String,
) -> Program[Msg, View] {
  let scope = @incr.Scope::new(runtime)
  let state : Ref[Model] = Ref(initial)
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
