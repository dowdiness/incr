///|
/// A handle identifying a single runtime-global listener registration.
///
/// Returned by the additive listener APIs (`Runtime::add_on_change_listener`,
/// `Runtime::add_derived_event_listener`) and passed back to their `remove_*`
/// counterparts to detach a specific listener. Ids are allocated from a single
/// per-runtime monotonic counter shared across *both* listener registries, so
/// every listener on a runtime has a runtime-unique id. Passing an id to the
/// wrong registry's `remove` (or to a different runtime) is therefore a
/// guaranteed no-op rather than an accidental removal.
///
/// Like `RuntimeId`, a `ListenerId` is an introspection/debug identity — compare
/// it for equality or use it as a map key; it is not a stable application key
/// across program runs and carries no ordering or arithmetic meaning.
pub(all) struct ListenerId {
  id : Int
} derive(Eq, Hash, Debug)

///|
/// Wraps a raw listener-allocation number as a `ListenerId`.
pub fn ListenerId::ListenerId(id : Int) -> ListenerId {
  { id, }
}

///|
/// Shows the underlying allocation number, keeping listener ids readable in
/// introspection and debug output.
pub impl Show for ListenerId with fn output(self, logger) {
  logger.write_string(self.id.to_string())
}
