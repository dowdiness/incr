///|
/// A handle identifying a single runtime-global listener registration.
///
/// Returned by the additive listener APIs (`Runtime::add_on_change_listener`,
/// `Runtime::add_derived_event_listener`) and passed back to their `remove_*`
/// counterparts to detach a specific listener.
///
/// An id pairs the originating `RuntimeId` with an allocation number drawn from
/// a single per-runtime monotonic counter shared across *both* listener
/// registries. The counter makes ids unique across the two registries of one
/// runtime; the `RuntimeId` makes them unique *across* runtimes (the bare
/// counter alone would collide — the first listener of two runtimes would both
/// be number 0). Together they guarantee that passing an id to the wrong
/// registry, or to a different runtime, is a no-op rather than an accidental
/// removal of an unrelated hook.
///
/// Like `RuntimeId`, a `ListenerId` is an introspection/debug identity — compare
/// it for equality or use it as a map key; it is not a stable application key
/// across program runs and carries no ordering or arithmetic meaning.
pub(all) struct ListenerId {
  runtime_id : RuntimeId
  id : Int
} derive(Eq, Hash, Debug)

///|
/// Pairs a `RuntimeId` with a raw listener-allocation number as a `ListenerId`.
pub fn ListenerId::ListenerId(runtime_id : RuntimeId, id : Int) -> ListenerId {
  { runtime_id, id }
}

///|
/// Shows the owning runtime and the allocation number (e.g. `0#3`), keeping
/// listener ids readable in introspection and debug output.
pub impl Show for ListenerId with fn output(self, logger) {
  logger.write_string("\{self.runtime_id}#\{self.id}")
}
