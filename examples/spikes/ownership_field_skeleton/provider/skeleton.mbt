///|
pub type View[T] = () -> T

///|
pub(all) struct Store {
  priv core : StoreCore
}

///|
priv struct StoreCore {
  mut closed : Bool
  mut next_active_id : Int
  mounts : Array[MountRecord]
  deferred : Array[DeferredCommand]
  listeners : Array[ListenerRecord]
}

///|
priv enum CachedValue[T] {
  Empty
  Materialized(T)
}

///|
priv struct DependencyAnchor {
  keep_alive : () -> Bool
}

///|
priv struct DependencyCollection {
  entries : Array[DependencyAnchor]
}

///|
priv struct ViewState[T] {
  store : StoreCore
  compute : () -> T
  equal : (T, T) -> Bool
  mut cache : CachedValue[T]
  dependencies : DependencyCollection
}

///|
priv struct InputState[T] {
  store : StoreCore
  mut value : T
}

///|
pub(all) struct Write[T] {
  priv state : InputState[T]
  priv store : StoreCore
}

///|
priv struct MountRecord {
  id : Int
  effect : () -> Unit
}

///|
pub(all) struct Stop {
  priv store : StoreCore
  priv mount_id : Int
}

///|
priv struct DeferredCommand {
  run : () -> Unit
}

///|
priv struct ListenerRecord {
  id : Int
  callback : () -> Unit
}

///|
pub(all) struct ListenerToken {
  priv store : StoreCore
  priv listener_id : Int
}

///|
priv struct KeyedEntry[V] {
  view : View[V]
}

///|
priv struct KeyedOwner[K, V] {
  entries : Array[(K, KeyedEntry[V])]
}

///|
pub(all) struct LayoutProbeReport {
  dependency_anchors : Int
  input_value_after_write : Int
  active_mounts_before_close : Int
  deferred_before_flush : Int
  listeners_before_close : Int
  mounts_after_stop : Int
  listeners_after_token_removal : Int
  deferred_after_flush : Int
  active_records_after_close : Int
  keyed_entries_after_retirement : Int
  surviving_getter_value : Int
}

///|
pub fn Store::Store() -> Store {
  {
    core: {
      closed: false,
      next_active_id: 0,
      mounts: [],
      deferred: [],
      listeners: [],
    },
  }
}

///|
fn[T] DependencyAnchor::from_input(state : InputState[T]) -> DependencyAnchor {
  { keep_alive: () => state.store.closed }
}

///|
fn[T] DependencyAnchor::from_view(state : ViewState[T]) -> DependencyAnchor {
  { keep_alive: () => state.store.closed }
}

///|
fn[T] ViewState::read(self : ViewState[T]) -> T {
  ignore(self.store.closed)
  self.dependencies.entries.each(anchor => ignore((anchor.keep_alive)()))
  match self.cache {
    Materialized(value) => {
      ignore((self.equal)(value, value))
      value
    }
    Empty => {
      let value = (self.compute)()
      self.cache = Materialized(value)
      value
    }
  }
}

///|
fn[T : Eq] Store::derived_with_dependencies(
  self : Store,
  compute : () -> T,
  dependencies : Array[DependencyAnchor],
) -> View[T] {
  let state : ViewState[T] = {
    store: self.core,
    compute,
    equal: (left, right) => left == right,
    cache: Empty,
    dependencies: { entries: dependencies },
  }
  () => state.read()
}

///|
pub fn[T : Eq] Store::derived(self : Store, compute : () -> T) -> View[T] {
  self.derived_with_dependencies(compute, [])
}

///|
pub fn Store::probe_passive_fan_in(
  self : Store,
  retainers : Array[() -> Unit],
) -> View[Int] {
  let dependencies = retainers.map(retain => {
    let input : InputState[Int] = { store: self.core, value: 1 }
    DependencyAnchor::{
      keep_alive: () => {
        retain()
        input.store.closed
      },
    }
  })
  let value = dependencies.length()
  self.derived_with_dependencies(() => value, dependencies)
}

///|
pub fn Store::probe_passive_chain(
  self : Store,
  retainers : Array[() -> Unit],
) -> View[Int] {
  let last : ViewState[Int]? = retainers.fold(init=None, (previous, retain) => {
    let dependencies = match previous {
      None => []
      Some(upstream) => [DependencyAnchor::from_view(upstream)]
    }
    Some(ViewState::{
      store: self.core,
      compute: () => {
        retain()
        1
      },
      equal: (left, right) => left == right,
      cache: Empty,
      dependencies: { entries: dependencies },
    })
  })
  match last {
    Some(state) => () => state.read()
    None => self.derived(() => 0)
  }
}

///|
pub fn Store::probe_passive_diamond(
  self : Store,
  seed_retain : () -> Unit,
  left_retain : () -> Unit,
  right_retain : () -> Unit,
  root_retain : () -> Unit,
) -> View[Int] {
  let seed : InputState[() -> Unit] = { store: self.core, value: seed_retain }
  let seed_anchor : DependencyAnchor = {
    keep_alive: () => {
      (seed.value)()
      seed.store.closed
    },
  }
  let left : ViewState[Int] = {
    store: self.core,
    compute: () => {
      left_retain()
      2
    },
    equal: (a, b) => a == b,
    cache: Empty,
    dependencies: { entries: [seed_anchor] },
  }
  let right : ViewState[Int] = {
    store: self.core,
    compute: () => {
      right_retain()
      3
    },
    equal: (a, b) => a == b,
    cache: Empty,
    dependencies: { entries: [seed_anchor] },
  }
  let root : ViewState[Int] = {
    store: self.core,
    compute: () => {
      root_retain()
      5
    },
    equal: (a, b) => a == b,
    cache: Empty,
    dependencies: {
      entries: [
        DependencyAnchor::from_view(left),
        DependencyAnchor::from_view(right),
      ],
    },
  }
  () => root.read()
}

///|
pub fn[T] retire_keyed_for_probe(view : View[T]) -> View[T] {
  let entry : KeyedEntry[T] = { view, }
  let owner : KeyedOwner[String, T] = { entries: [("probe", entry)] }
  let surviving : View[T] = () => (entry.view)()
  owner.entries.clear()
  surviving
}

///|
pub fn[T] Store::input(self : Store, initial : T) -> (View[T], Write[T]) {
  let state : InputState[T] = { store: self.core, value: initial }
  let view : View[T] = () => {
    ignore(state.store.closed)
    state.value
  }
  let write : Write[T] = { state, store: self.core }
  (view, write)
}

///|
pub fn[T : Eq] Write::set(self : Write[T], value : T) -> Unit {
  ignore(self.store.closed)
  if self.state.value != value {
    self.state.value = value
  }
}

///|
pub fn Store::mount(self : Store, effect : () -> Unit) -> Stop {
  let mount_id = self.core.next_active_id
  self.core.next_active_id += 1
  self.core.mounts.push({ id: mount_id, effect })
  { store: self.core, mount_id }
}

///|
pub fn Stop::stop(self : Stop) -> Unit {
  self.store.mounts.retain(record => record.id != self.mount_id)
}

///|
pub fn Store::enqueue_deferred(self : Store, command : () -> Unit) -> Unit {
  self.core.deferred.push({ run: command })
}

///|
pub fn Store::flush(self : Store) -> Unit {
  self.core.deferred.each(command => (command.run)())
  self.core.deferred.clear()
}

///|
pub fn Store::listen(self : Store, callback : () -> Unit) -> ListenerToken {
  let listener_id = self.core.next_active_id
  self.core.next_active_id += 1
  self.core.listeners.push({ id: listener_id, callback })
  { store: self.core, listener_id }
}

///|
pub fn ListenerToken::remove(self : ListenerToken) -> Unit {
  self.store.listeners.retain(record => record.id != self.listener_id)
}

///|
pub fn Store::close(self : Store) -> Unit {
  self.core.closed = true
  self.core.mounts.clear()
  self.core.deferred.clear()
  self.core.listeners.clear()
}

///|
pub fn run_layout_probe() -> LayoutProbeReport {
  let store = Store()
  let input_state : InputState[Int] = { store: store.core, value: 5 }
  let input_anchor = DependencyAnchor::from_input(input_state)
  let upstream_state : ViewState[Int] = {
    store: store.core,
    compute: () => 7,
    equal: (left, right) => left == right,
    cache: Empty,
    dependencies: { entries: [] },
  }
  let upstream_anchor = DependencyAnchor::from_view(upstream_state)
  let dependency_anchors = [input_anchor, upstream_anchor]
  let downstream = store.derived_with_dependencies(() => 12, dependency_anchors)
  ignore(downstream())

  let (input_view, write) = store.input(10)
  write.set(11)
  let input_value_after_write = input_view()

  let stop = store.mount(() => ())
  let listener_token = store.listen(() => ())
  let deferred_called = Ref(false)
  store.enqueue_deferred(() => deferred_called.val = true)
  let active_mounts_before_close = store.core.mounts.length()
  let deferred_before_flush = store.core.deferred.length()
  let listeners_before_close = store.core.listeners.length()
  store.core.mounts.each(record => (record.effect)())
  store.core.listeners.each(record => (record.callback)())

  stop.stop()
  let mounts_after_stop = store.core.mounts.length()
  listener_token.remove()
  let listeners_after_token_removal = store.core.listeners.length()
  store.flush()
  let deferred_after_flush = store.core.deferred.length()

  let keyed_view = store.derived(() => 23)
  let keyed_entry : KeyedEntry[Int] = { view: keyed_view }
  let keyed_owner : KeyedOwner[String, Int] = {
    entries: [("answer", keyed_entry)],
  }
  let surviving_getter : View[Int] = () => (keyed_entry.view)()
  keyed_owner.entries.clear()
  let keyed_entries_after_retirement = keyed_owner.entries.length()
  let surviving_getter_value = surviving_getter()

  ignore(store.mount(() => ()))
  ignore(store.listen(() => ()))
  store.close()
  let active_records_after_close = store.core.mounts.length() +
    store.core.listeners.length()

  {
    dependency_anchors: dependency_anchors.length(),
    input_value_after_write,
    active_mounts_before_close,
    deferred_before_flush,
    listeners_before_close,
    mounts_after_stop,
    listeners_after_token_removal,
    deferred_after_flush,
    active_records_after_close,
    keyed_entries_after_retirement,
    surviving_getter_value,
  }
}
