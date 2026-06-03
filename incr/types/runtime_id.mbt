///|
/// A unique identifier for a `Runtime`.
///
/// Runtime ids are monotonically allocated when a `Runtime` is created and
/// scope every `CellId` / `AccumulatorId` to its originating runtime.
///
/// A `RuntimeId` is an *introspection / debug identity*: compare it for
/// equality ("are these two runtimes the same?"), use it as a map key, or
/// display it. It is **not** a stable application key across program runs, and
/// carries no ordering or arithmetic meaning — that is why it is a nominal
/// wrapper rather than a bare `Int`.
pub(all) struct RuntimeId {
  id : Int
} derive(Eq, Hash, Debug)

///|
/// Wraps a raw runtime-allocation number as a `RuntimeId`.
pub fn RuntimeId::RuntimeId(id : Int) -> RuntimeId {
  { id, }
}

///|
/// Shows the underlying allocation number (e.g. `0`), keeping runtime ids
/// readable in error messages and graph-visualization output.
pub impl Show for RuntimeId with fn output(self, logger) {
  logger.write_string(self.id.to_string())
}
