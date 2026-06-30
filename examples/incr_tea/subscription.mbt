///|
/// A stable, namespaced identifier for one logical subscription.
///
/// The pair is part of the map key, so only exact matches restart/update/stop each
/// subscription.
///
/// # Collision risk
///
/// If two logical sources use the same `(namespace, identity)` pair, they
/// intentionally collide and share one live subscription. Use unique namespaces
/// and identities for distinct subscriptions.
pub struct SubKey {
  namespace_id : String
  identity : String
} derive(Eq, Hash, Debug)

///|
pub fn SubKey::SubKey(namespace_id : String, identity : String) -> SubKey {
  { namespace_id, identity }
}

///|
/// Desired subscription behavior for one key.
///
/// More variants can be added alongside `Timer` as the platform evolves.
pub(all) enum SubSpec[Msg] {
  Timer(Int, Msg)
  WindowKeydown(String, Msg)
  AnimationFrame(Msg)
} derive(Eq, Debug)

///|
/// A keyed collection of requested subscriptions.
pub type Subscriptions[Msg] = @hashmap.HashMap[SubKey, SubSpec[Msg]]

///|
#cfg(target="js")
#external
priv type TimerHandleId

///|
#cfg(not(target="js"))
let next_timer_id : Ref[Int] = Ref(0)

///|
#cfg(not(target="js"))
type TimerHandleId = Int

///|
let next_timer_debug_id : Ref[Int] = Ref(0)

///|
#cfg(target="js")
extern "js" fn dom_set_interval(
  callback : () -> Unit,
  interval_ms : Int,
) -> TimerHandleId =
  #| (callback, intervalMs) => {
  #|   if (typeof window === "undefined" || window === null) {
  #|     return 0;
  #|   }
  #|   return window.setInterval(callback, intervalMs);
  #| }

///|
#cfg(not(target="js"))
fn dom_set_interval(
  _callback : () -> Unit,
  _interval_ms : Int,
) -> TimerHandleId {
  next_timer_id.val = next_timer_id.val + 1
  next_timer_id.val
}

///|
#cfg(target="js")
extern "js" fn dom_clear_interval(timer_id : TimerHandleId) -> Unit =
  #| (timerId) => {
  #|   if (typeof window !== "undefined" && window !== null) {
  #|     window.clearInterval(timerId)
  #|   }
  #| }

///|
#cfg(not(target="js"))
fn dom_clear_interval(_timer_id : TimerHandleId) -> Unit {
  ()
}

///|
#cfg(target="js")
#external
priv type KeydownHandleId

///|
#cfg(not(target="js"))
let next_keydown_id : Ref[Int] = Ref(0)

///|
#cfg(not(target="js"))
type KeydownHandleId = Int

///|
let next_keydown_debug_id : Ref[Int] = Ref(0)

///|
#cfg(target="js")
extern "js" fn dom_add_window_keydown_listener(
  key_name : String,
  callback : () -> Unit,
) -> KeydownHandleId =
  #| (keyName, callback) => {
  #|   const store = globalThis.__incrTeaKeydownListeners ??= new Map();
  #|   const next = (globalThis.__incrTeaKeydownListenerSeq ?? 0) + 1;
  #|   globalThis.__incrTeaKeydownListenerSeq = next;
  #|   const handler = event => {
  #|     if (event.key === keyName) callback();
  #|   };
  #|   store.set(next, handler);
  #|   if (typeof window !== "undefined" && window !== null) {
  #|     window.addEventListener("keydown", handler);
  #|   }
  #|   return next;
  #| }

///|
#cfg(not(target="js"))
fn dom_add_window_keydown_listener(
  _key_name : String,
  _callback : () -> Unit,
) -> KeydownHandleId {
  next_keydown_id.val = next_keydown_id.val + 1
  next_keydown_id.val
}

///|
#cfg(target="js")
extern "js" fn dom_remove_window_keydown_listener(
  handle : KeydownHandleId,
) -> Unit =
  #| (handle) => {
  #|   const store = globalThis.__incrTeaKeydownListeners;
  #|   const handler = store?.get(handle);
  #|   if (!handler) return;
  #|   if (typeof window !== "undefined" && window !== null) {
  #|     window.removeEventListener("keydown", handler);
  #|   }
  #|   store.delete(handle);
  #| }

///|
#cfg(not(target="js"))
fn dom_remove_window_keydown_listener(_handle : KeydownHandleId) -> Unit {
  ()
}

///|
#cfg(target="js")
#external
priv type RafHandleId

///|
#cfg(not(target="js"))
let next_raf_id : Ref[Int] = Ref(0)

///|
#cfg(not(target="js"))
type RafHandleId = Int

///|
let next_raf_debug_id : Ref[Int] = Ref(0)

///|
#cfg(target="js")
extern "js" fn dom_start_raf_loop(callback : () -> Unit) -> RafHandleId =
  #| (callback) => {
  #|   const store = globalThis.__incrTeaRafLoops ??= new Map();
  #|   const next = (globalThis.__incrTeaRafLoopSeq ?? 0) + 1;
  #|   globalThis.__incrTeaRafLoopSeq = next;
  #|   const loop = () => {
  #|     if (store.get(next) === null) return;
  #|     callback();
  #|     if (store.get(next) === null) return;
  #|     if (typeof window !== "undefined" && window !== null) {
  #|       store.set(next, window.requestAnimationFrame(loop));
  #|     }
  #|   };
  #|   if (typeof window !== "undefined" && window !== null) {
  #|     store.set(next, window.requestAnimationFrame(loop));
  #|   }
  #|   return next;
  #| }

///|
#cfg(not(target="js"))
fn dom_start_raf_loop(_callback : () -> Unit) -> RafHandleId {
  next_raf_id.val = next_raf_id.val + 1
  next_raf_id.val
}

///|
#cfg(target="js")
extern "js" fn dom_stop_raf_loop(handle : RafHandleId) -> Unit =
  #| (id) => {
  #|   const store = globalThis.__incrTeaRafLoops;
  #|   const handle = store?.get(id);
  #|   if (handle == null) return;
  #|   store.set(id, null);
  #|   if (typeof window !== "undefined" && window !== null) {
  #|     window.cancelAnimationFrame(handle);
  #|   }
  #| }

///|
#cfg(not(target="js"))
fn dom_stop_raf_loop(_handle : RafHandleId) -> Unit {
  ()
}

///|
priv struct TimerSub[Msg] {
  mut interval_ms : Int
  message : Ref[Msg]
  mut timer_id : TimerHandleId
  dispatch : (Msg) -> Unit
}

///|
priv struct AnimationFrameSub[Msg] {
  message : Ref[Msg]
  handle : RafHandleId
}

///|
fn[Msg] AnimationFrameSub::AnimationFrameSub(
  message : Msg,
  dispatch : (Msg) -> Unit,
) -> AnimationFrameSub[Msg] {
  let message_ref = Ref(message)
  let handle = dom_start_raf_loop(() => dispatch(message_ref.val))
  next_raf_debug_id.val = next_raf_debug_id.val + 1
  { message: message_ref, handle }
}

///|
fn[Msg] AnimationFrameSub::set_message(
  self : AnimationFrameSub[Msg],
  message : Msg,
) -> Unit {
  self.message.val = message
}

///|
fn[Msg] AnimationFrameSub::stop(self : AnimationFrameSub[Msg]) -> Unit {
  dom_stop_raf_loop(self.handle)
}

///|
priv enum ActiveSub[Msg] {
  Timer(TimerSub[Msg])
  Keydown(KeydownSub[Msg])
  AnimationFrame(AnimationFrameSub[Msg])
}

///|
priv struct SubscriptionsManager[Msg] {
  active : @hashmap.HashMap[SubKey, ActiveSub[Msg]]
}

///|
fn[Msg] SubscriptionsManager::SubscriptionsManager() -> SubscriptionsManager[
  Msg,
] {
  { active: @hashmap.HashMap([]) }
}

///|
fn[Msg] TimerSub::TimerSub(
  interval_ms : Int,
  message : Msg,
  dispatch : (Msg) -> Unit,
) -> TimerSub[Msg] {
  let message_ref = Ref(message)
  let timer_id = dom_set_interval(() => dispatch(message_ref.val), interval_ms)
  next_timer_debug_id.val = next_timer_debug_id.val + 1
  { interval_ms, message: message_ref, timer_id, dispatch }
}

///|
fn[Msg] TimerSub::set_message(self : TimerSub[Msg], message : Msg) -> Unit {
  self.message.val = message
}

///|
fn[Msg] TimerSub::set_interval(self : TimerSub[Msg], interval_ms : Int) -> Unit {
  guard interval_ms != self.interval_ms else { return }
  dom_clear_interval(self.timer_id)
  let message = self.message
  let dispatch = self.dispatch
  self.timer_id = dom_set_interval(() => dispatch(message.val), interval_ms)
  self.interval_ms = interval_ms
  next_timer_debug_id.val = next_timer_debug_id.val + 1
}

///|
fn[Msg] TimerSub::stop(self : TimerSub[Msg]) -> Unit {
  dom_clear_interval(self.timer_id)
}

///|
priv struct KeydownSub[Msg] {
  mut key_name : String
  message : Ref[Msg]
  mut listener_handle : KeydownHandleId
  dispatch : (Msg) -> Unit
}

///|
fn[Msg] KeydownSub::KeydownSub(
  key_name : String,
  message : Msg,
  dispatch : (Msg) -> Unit,
) -> KeydownSub[Msg] {
  let message_ref = Ref(message)
  let listener_handle = dom_add_window_keydown_listener(key_name, () => {
    dispatch(message_ref.val)
  })
  next_keydown_debug_id.val = next_keydown_debug_id.val + 1
  { key_name, message: message_ref, listener_handle, dispatch }
}

///|
fn[Msg] KeydownSub::set_message(self : KeydownSub[Msg], message : Msg) -> Unit {
  self.message.val = message
}

///|
fn[Msg] KeydownSub::set_key_name(
  self : KeydownSub[Msg],
  key_name : String,
) -> Unit {
  guard key_name != self.key_name else { return }
  dom_remove_window_keydown_listener(self.listener_handle)
  let message = self.message
  let dispatch = self.dispatch
  self.listener_handle = dom_add_window_keydown_listener(key_name, () => {
    dispatch(message.val)
  })
  self.key_name = key_name
  next_keydown_debug_id.val = next_keydown_debug_id.val + 1
}

///|
fn[Msg] KeydownSub::stop(self : KeydownSub[Msg]) -> Unit {
  dom_remove_window_keydown_listener(self.listener_handle)
}

///|
fn[Msg] ActiveSub::stop(self : ActiveSub[Msg]) -> Unit {
  match self {
    Timer(timer) => timer.stop()
    Keydown(sub) => sub.stop()
    AnimationFrame(raf) => raf.stop()
  }
}

///|
fn[Msg] SubscriptionsManager::start_timer(
  interval_ms : Int,
  on_tick : Msg,
  dispatch : (Msg) -> Unit,
) -> ActiveSub[Msg] {
  ActiveSub::Timer(TimerSub::TimerSub(interval_ms, on_tick, dispatch))
}

///|
fn[Msg] SubscriptionsManager::start_or_update_timer(
  self : SubscriptionsManager[Msg],
  key : SubKey,
  interval_ms : Int,
  on_tick : Msg,
  dispatch : (Msg) -> Unit,
) -> Unit {
  match self.active.get(key) {
    Some(Timer(timer)) => {
      timer.set_message(on_tick)
      timer.set_interval(interval_ms)
    }
    Some(existing) => {
      existing.stop()
      self.active.set(
        key,
        SubscriptionsManager::start_timer(interval_ms, on_tick, dispatch),
      )
    }
    None =>
      self.active.set(
        key,
        SubscriptionsManager::start_timer(interval_ms, on_tick, dispatch),
      )
  }
}

///|
fn[Msg] SubscriptionsManager::start_keydown(
  key_name : String,
  message : Msg,
  dispatch : (Msg) -> Unit,
) -> ActiveSub[Msg] {
  ActiveSub::Keydown(KeydownSub::KeydownSub(key_name, message, dispatch))
}

///|
fn[Msg] SubscriptionsManager::start_or_update_keydown(
  self : SubscriptionsManager[Msg],
  key : SubKey,
  key_name : String,
  message : Msg,
  dispatch : (Msg) -> Unit,
) -> Unit {
  match self.active.get(key) {
    Some(Keydown(sub)) => {
      sub.set_message(message)
      sub.set_key_name(key_name)
    }
    Some(existing) => {
      existing.stop()
      self.active.set(
        key,
        SubscriptionsManager::start_keydown(key_name, message, dispatch),
      )
    }
    None =>
      self.active.set(
        key,
        SubscriptionsManager::start_keydown(key_name, message, dispatch),
      )
  }
}

///|
fn[Msg] SubscriptionsManager::start_animation_frame(
  message : Msg,
  dispatch : (Msg) -> Unit,
) -> ActiveSub[Msg] {
  ActiveSub::AnimationFrame(
    AnimationFrameSub::AnimationFrameSub(message, dispatch),
  )
}

///|
fn[Msg] SubscriptionsManager::start_or_update_animation_frame(
  self : SubscriptionsManager[Msg],
  key : SubKey,
  message : Msg,
  dispatch : (Msg) -> Unit,
) -> Unit {
  match self.active.get(key) {
    Some(AnimationFrame(raf)) => raf.set_message(message)
    Some(existing) => {
      existing.stop()
      self.active.set(
        key,
        SubscriptionsManager::start_animation_frame(message, dispatch),
      )
    }
    None =>
      self.active.set(
        key,
        SubscriptionsManager::start_animation_frame(message, dispatch),
      )
  }
}

///|
fn[Msg] SubscriptionsManager::reconcile(
  self : SubscriptionsManager[Msg],
  desired : Subscriptions[Msg],
  dispatch : (Msg) -> Unit,
) -> Unit {
  for pair in desired.to_array() {
    match pair {
      (key, SubSpec::Timer(interval_ms, on_tick)) =>
        self.start_or_update_timer(key, interval_ms, on_tick, dispatch)
      (key, SubSpec::WindowKeydown(key_name, message)) =>
        self.start_or_update_keydown(key, key_name, message, dispatch)
      (key, SubSpec::AnimationFrame(message)) =>
        self.start_or_update_animation_frame(key, message, dispatch)
    }
  }
  for pair in self.active.to_array() {
    match pair {
      (key, _) =>
        match desired.get(key) {
          Some(_) => ()
          None =>
            match self.active.get(key) {
              Some(active) => {
                active.stop()
                self.active.remove(key)
              }
              None => ()
            }
        }
    }
  }
}

///|
fn[Msg] SubscriptionsManager::dispose(self : SubscriptionsManager[Msg]) -> Unit {
  for pair in self.active.to_array() {
    match pair {
      (_, active) => active.stop()
    }
  }
  self.active.clear()
}
