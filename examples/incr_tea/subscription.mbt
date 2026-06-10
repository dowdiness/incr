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
pub enum SubSpec[Msg] {
  Timer(Int, Msg)
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
priv struct TimerSub[Msg] {
  mut interval_ms : Int
  message : Ref[Msg]
  mut timer_id : TimerHandleId
  dispatch : (Msg) -> Unit
}

///|
priv enum ActiveSub[Msg] {
  Timer(TimerSub[Msg])
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
fn[Msg] ActiveSub::stop(self : ActiveSub[Msg]) -> Unit {
  match self {
    Timer(timer) => timer.stop()
  }
}

///|
fn[Msg] ActiveSub::as_timer(self : ActiveSub[Msg]) -> TimerSub[Msg] {
  match self {
    Timer(timer) => timer
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
    Some(existing) => {
      let timer = existing.as_timer()
      timer.set_message(on_tick)
      timer.set_interval(interval_ms)
      self.active.set(key, ActiveSub::Timer(timer))
    }
    None =>
      self.active.set(
        key,
        SubscriptionsManager::start_timer(interval_ms, on_tick, dispatch),
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
