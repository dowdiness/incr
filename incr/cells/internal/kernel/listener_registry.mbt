///|
/// Ordered registry of runtime-global listeners with a reserved "singleton"
/// slot.
///
/// One generic mechanism backs both runtime hook surfaces — the on-change
/// listeners (kernel-side `fire_on_change`) and the derived-event listeners
/// (cells-side `EventBroadcastPhaseHook`). The singleton-style public APIs
/// (`set_on_change`, `on_derived_event`, …) map onto the reserved slot;
/// the additive APIs (`add_*_listener` / `remove_*_listener`) append and
/// remove by `ListenerId`.
///
/// `pub(all)` so `cells/*.mbt` can hold and construct it, but the package is
/// `internal/` so this is not part of the public API surface.

///|
/// A single listener entry: its allocation id plus the replaceable callback.
pub(all) struct ListenerEntry[F] {
  id : ListenerId
  mut callback : F
}

///|
pub(all) struct ListenerRegistry[F] {
  entries : Array[ListenerEntry[F]]
  mut singleton : ListenerId?
}

///|
/// Creates an empty registry.
pub fn[F] ListenerRegistry::new() -> ListenerRegistry[F] {
  { entries: [], singleton: None }
}

///|
/// True when no listener is registered (used to short-circuit firing/buffering).
pub fn[F] ListenerRegistry::is_empty(self : ListenerRegistry[F]) -> Bool {
  self.entries.is_empty()
}

///|
/// Appends a new additive listener.
pub fn[F] ListenerRegistry::add(
  self : ListenerRegistry[F],
  id : ListenerId,
  callback : F,
) -> Unit {
  self.entries.push({ id, callback })
}

///|
/// Removes the entry with `id`. Idempotent — removing an absent id is a no-op.
/// Clears the singleton marker when it names the removed entry. Returns whether
/// an entry was actually removed.
pub fn[F] ListenerRegistry::remove(
  self : ListenerRegistry[F],
  id : ListenerId,
) -> Bool {
  match self.entries.search_by(e => e.id == id) {
    Some(idx) => {
      self.entries.remove(idx) |> ignore
      if self.singleton is Some(sid) && sid == id {
        self.singleton = None
      }
      true
    }
    None => false
  }
}

///|
/// Sets the singleton slot. If a singleton entry is live, replaces its callback
/// in place (registration position preserved); otherwise allocates an id via
/// `alloc_id` and appends a fresh entry recorded as the singleton. The
/// `alloc_id` thunk is only invoked when a new entry is created, so repeated
/// `set_singleton` calls do not burn ids.
pub fn[F] ListenerRegistry::set_singleton(
  self : ListenerRegistry[F],
  alloc_id : () -> ListenerId,
  callback : F,
) -> Unit {
  // Locate the live singleton entry (if any). The invariant guarantees a
  // `Some(sid)` marker names an existing entry, so a `None` index here means
  // there is no singleton to replace and we append a fresh one.
  let existing = match self.singleton {
    Some(sid) => self.entries.search_by(e => e.id == sid)
    None => None
  }
  match existing {
    Some(idx) => self.entries[idx].callback = callback
    None => {
      let id = alloc_id()
      self.entries.push({ id, callback })
      self.singleton = Some(id)
    }
  }
}

///|
/// Clears the singleton slot if present. Idempotent.
pub fn[F] ListenerRegistry::clear_singleton(self : ListenerRegistry[F]) -> Unit {
  if self.singleton is Some(sid) {
    self.remove(sid) |> ignore
  }
}

///|
/// Returns a fresh array of the callbacks in registration order. The copy is
/// safe to iterate while the registry is mutated, which is what lets a listener
/// add/remove listeners during a fire without affecting the in-flight dispatch
/// (snapshot-before-fire).
pub fn[F] ListenerRegistry::snapshot(self : ListenerRegistry[F]) -> Array[F] {
  self.entries.map(fn(e) { e.callback })
}
