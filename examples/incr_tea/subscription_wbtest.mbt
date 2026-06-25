///|
enum SubTestMsg {
  Enable
  Disable
  SetFast
  SetSlow
  TouchUnrelated
} derive(Eq, Debug)

///|
fn subscription_program(runtime : @incr.Runtime) -> Program[SubTestMsg, Int] {
  let scope = @incr.Scope::new(runtime)
  let running = scope.input_field(false, label="subtest.running")
  let interval = scope.input_field(300, label="subtest.interval")
  let use_fast_handler = scope.input_field(true, label="subtest.use_fast")
  let unrelated = scope.input_field(0, label="subtest.unrelated")

  let subscriptions : () -> Subscriptions[SubTestMsg] raise Failure = () => {
    let subscriptions = @hashmap.HashMap([])
    if running.get() {
      subscriptions.set(
        SubKey::SubKey("timer-test", "subscription"),
        SubSpec::Timer(
          interval.get(),
          if use_fast_handler.get() {
            SubTestMsg::SetFast
          } else {
            SubTestMsg::SetSlow
          },
        ),
      )
    }
    subscriptions
  }

  let update : (SubTestMsg) -> Cmd[SubTestMsg] = msg => {
    match msg {
      Enable => {
        running.set(true)
        Cmd::none()
      }
      Disable => {
        running.set(false)
        Cmd::none()
      }
      SetFast => {
        use_fast_handler.set(true)
        Cmd::none()
      }
      SetSlow => {
        use_fast_handler.set(false)
        Cmd::none()
      }
      TouchUnrelated => {
        unrelated.set(unrelated.peek() + 1)
        Cmd::none()
      }
    }
  }

  let view : () -> Int raise Failure = () => if running.get() { 1 } else { 0 }

  Program::with_subscriptions(
    runtime,
    scope,
    update,
    view,
    subscriptions,
    label="subtest.subscription.view",
  )
}

///|
fn[Msg] active_timer(
  manager : SubscriptionsManager[Msg],
  key : SubKey,
) -> TimerSub[Msg]? {
  match manager.active.get(key) {
    Some(Timer(timer)) => Some(timer)
    Some(Keydown(_)) | None => None
  }
}

///|
fn[Msg] active_keydown(
  manager : SubscriptionsManager[Msg],
  key : SubKey,
) -> KeydownSub[Msg]? {
  match manager.active.get(key) {
    Some(Keydown(sub)) => Some(sub)
    Some(Timer(_)) | None => None
  }
}

///|
fn[Msg] has_active_keydown(
  manager : SubscriptionsManager[Msg],
  key : SubKey,
) -> Bool {
  match active_keydown(manager, key) {
    Some(_) => true
    None => false
  }
}

///|
fn[Msg] active_timer_count(manager : SubscriptionsManager[Msg]) -> Int {
  manager.active.to_array().length()
}

///|
fn[Msg] has_active_timer(
  manager : SubscriptionsManager[Msg],
  key : SubKey,
) -> Bool {
  match active_timer(manager, key) {
    Some(_) => true
    None => false
  }
}

///|
test "panic subscriptions: constructor rejects a scope from another Runtime" {
  let runtime = @incr.Runtime()
  let foreign_runtime = @incr.Runtime()
  let foreign_scope = @incr.Scope::new(foreign_runtime)
  let update : (SubTestMsg) -> Cmd[SubTestMsg] = _ => Cmd::none()
  let view : () -> Int raise Failure = () => 0
  let subscriptions : () -> Subscriptions[SubTestMsg] raise Failure = () => {
    @hashmap.HashMap([])
  }
  ignore(
    Program::with_subscriptions(
      runtime,
      foreign_scope,
      update,
      view,
      subscriptions,
      label="subtest.runtime_mismatch.view",
    ),
  )
}

///|
test "subscriptions: enable and disable starts/stops timer handle" {
  let runtime = @incr.Runtime()
  let key = SubKey::SubKey("timer-test", "subscription")
  let program = subscription_program(runtime)
  let manager = match program.sub_manager {
    Some(manager) => manager
    None => abort("expected subscription manager")
  }

  inspect(has_active_timer(manager, key), content="false")
  inspect(active_timer_count(manager), content="0")

  let start_count_before = next_timer_debug_id.val
  inspect(program.dispatch(Enable), content="true")
  let start_count_after_enable = next_timer_debug_id.val
  inspect(start_count_after_enable == start_count_before + 1, content="true")
  inspect(active_timer_count(manager), content="1")

  inspect(program.dispatch(Disable), content="true")
  inspect(has_active_timer(manager, key), content="false")
  inspect(active_timer_count(manager), content="0")
}

///|
test "subscriptions: unrelated field changes do not churn subscription timer" {
  let runtime = @incr.Runtime()
  let program = subscription_program(runtime)
  let manager = match program.sub_manager {
    Some(manager) => manager
    None => abort("expected subscription manager")
  }

  inspect(program.dispatch(Enable), content="true")
  let start_count_before = next_timer_debug_id.val
  inspect(program.dispatch(TouchUnrelated), content="true")
  inspect(active_timer_count(manager), content="1")
  inspect(next_timer_debug_id.val == start_count_before, content="true")
}

///|
test "subscriptions: same key handler change updates timer in-place" {
  let runtime = @incr.Runtime()
  let key = SubKey::SubKey("timer-test", "subscription")
  let program = subscription_program(runtime)
  let manager = match program.sub_manager {
    Some(manager) => manager
    None => abort("expected subscription manager")
  }

  inspect(program.dispatch(Enable), content="true")
  let timer_before = match active_timer(manager, key) {
    Some(timer) => timer
    None => abort("missing timer after enable")
  }
  let handled_fast_before = match timer_before.message.val {
    SubTestMsg::SetFast => true
    _ => false
  }
  inspect(handled_fast_before, content="true")

  let start_count_before = next_timer_debug_id.val
  inspect(program.dispatch(SetSlow), content="true")
  let timer_after = match active_timer(manager, key) {
    Some(timer) => timer
    None => abort("missing timer after handler swap")
  }
  let handled_slow_after = match timer_after.message.val {
    SubTestMsg::SetSlow => true
    _ => false
  }

  inspect(handled_slow_after, content="true")
  inspect(next_timer_debug_id.val == start_count_before, content="true")
  inspect(active_timer_count(manager), content="1")
}

// ── WindowKeydown subscription lifecycle tests ──────────────────────────────

///|
enum KeydownTestMsg {
  EnableKey
  DisableKey
  SwitchToKeyB
  KeepKeyA
  TouchUnrelatedKd
} derive(Eq, Debug)

///|
fn keydown_subscription_program(
  runtime : @incr.Runtime,
) -> Program[KeydownTestMsg, Int] {
  let scope = @incr.Scope::new(runtime)
  let running = scope.input_field(false, label="kdtest.running")
  let use_key_b = scope.input_field(false, label="kdtest.use_key_b")
  let unrelated = scope.input_field(0, label="kdtest.unrelated")

  let subscriptions : () -> Subscriptions[KeydownTestMsg] raise Failure = () => {
    let subs = @hashmap.HashMap([])
    if running.get() {
      let key_name = if use_key_b.get() { "b" } else { "a" }
      subs.set(
        SubKey::SubKey("kd-test", "keydown"),
        SubSpec::WindowKeydown(key_name, KeydownTestMsg::KeepKeyA),
      )
    }
    subs
  }

  let update : (KeydownTestMsg) -> Cmd[KeydownTestMsg] = msg => {
    match msg {
      EnableKey => {
        running.set(true)
        Cmd::none()
      }
      DisableKey => {
        running.set(false)
        Cmd::none()
      }
      SwitchToKeyB => {
        use_key_b.set(true)
        Cmd::none()
      }
      KeepKeyA | TouchUnrelatedKd => {
        unrelated.set(unrelated.peek() + 1)
        Cmd::none()
      }
    }
  }

  let view : () -> Int raise Failure = () => if running.get() { 1 } else { 0 }

  Program::with_subscriptions(
    runtime,
    scope,
    update,
    view,
    subscriptions,
    label="kdtest.view",
  )
}

///|
test "subscriptions: enable and disable starts/stops keydown listener" {
  let runtime = @incr.Runtime()
  let key = SubKey::SubKey("kd-test", "keydown")
  let program = keydown_subscription_program(runtime)
  let manager = match program.sub_manager {
    Some(m) => m
    None => abort("expected subscription manager")
  }

  inspect(has_active_keydown(manager, key), content="false")
  inspect(manager.active.to_array().length(), content="0")

  let id_before = next_keydown_debug_id.val
  inspect(program.dispatch(EnableKey), content="true")
  inspect(next_keydown_debug_id.val == id_before + 1, content="true")
  inspect(has_active_keydown(manager, key), content="true")
  inspect(manager.active.to_array().length(), content="1")

  inspect(program.dispatch(DisableKey), content="true")
  inspect(has_active_keydown(manager, key), content="false")
  inspect(manager.active.to_array().length(), content="0")
  program.dispose()
}

///|
test "subscriptions: unrelated field changes do not churn keydown listener" {
  let runtime = @incr.Runtime()
  let program = keydown_subscription_program(runtime)
  let manager = match program.sub_manager {
    Some(m) => m
    None => abort("expected subscription manager")
  }

  inspect(program.dispatch(EnableKey), content="true")
  let id_before = next_keydown_debug_id.val
  inspect(program.dispatch(TouchUnrelatedKd), content="true")
  inspect(manager.active.to_array().length(), content="1")
  inspect(next_keydown_debug_id.val == id_before, content="true")
  program.dispose()
}

///|
test "subscriptions: message-only update does not restart keydown listener" {
  let runtime = @incr.Runtime()
  let key = SubKey::SubKey("kd-test", "keydown")
  let program = keydown_subscription_program(runtime)
  let manager = match program.sub_manager {
    Some(m) => m
    None => abort("expected subscription manager")
  }

  inspect(program.dispatch(EnableKey), content="true")
  let sub_before = match active_keydown(manager, key) {
    Some(s) => s
    None => abort("missing keydown after enable")
  }
  inspect(sub_before.key_name, content="a")

  let id_before = next_keydown_debug_id.val
  ignore(program.dispatch(KeepKeyA))
  inspect(next_keydown_debug_id.val == id_before, content="true")
  inspect(manager.active.to_array().length(), content="1")
  program.dispose()
}

///|
test "subscriptions: key name change restarts keydown listener" {
  let runtime = @incr.Runtime()
  let key = SubKey::SubKey("kd-test", "keydown")
  let program = keydown_subscription_program(runtime)
  let manager = match program.sub_manager {
    Some(m) => m
    None => abort("expected subscription manager")
  }

  inspect(program.dispatch(EnableKey), content="true")
  let id_before = next_keydown_debug_id.val

  inspect(program.dispatch(SwitchToKeyB), content="true")
  inspect(next_keydown_debug_id.val == id_before + 1, content="true")

  let sub_after = match active_keydown(manager, key) {
    Some(s) => s
    None => abort("missing keydown after key switch")
  }
  inspect(sub_after.key_name, content="b")
  inspect(manager.active.to_array().length(), content="1")
  program.dispose()
}
