///|
/// An incremental database providing access to its runtime.
///
/// This is the core trait that all incremental systems must implement.
/// It connects user-defined database types to the incr runtime,
/// enabling generic helper functions like `create_signal`, `create_memo`,
/// and `create_memo_map`.
///
/// This trait corresponds to Salsa's `#[salsa::db]` trait, but without
/// macro magic — users implement it explicitly.
///
/// # Example
///
/// ```moonbit nocheck
/// struct MyDb {
///   rt : @incr.Runtime
/// }
///
/// impl @incr.IncrDb for MyDb with runtime(self) {
///   self.rt
/// }
/// ```
pub(open) trait IncrDb {
  runtime(Self) -> Runtime
}

///|
/// A readable incremental node (Signal or Memo).
///
/// This trait provides a common interface for checking whether
/// a node's cached value is current with the latest revision.
/// Both Signal and Memo implement this trait.
///
/// Use the trait bound in generic functions to write code that
/// works with any readable node:
///
/// ```moonbit nocheck
/// fn[R : Readable] check(node : R) -> Bool {
///   node.is_up_to_date()
/// }
/// ```
pub(open) trait Readable {
  /// Returns true if the node's value is verified at the current revision.
  is_up_to_date(Self) -> Bool
}

///|
/// Signals are always up-to-date since they are input cells
/// with directly-set values.
pub impl[T] Readable for Signal[T] with is_up_to_date(self) {
  Signal::is_up_to_date(self)
}

///|
/// A memo is up-to-date when its verified_at matches the
/// runtime's current revision.
pub impl[T] Readable for Memo[T] with is_up_to_date(self) {
  Memo::is_up_to_date(self)
}

///|
/// Creates a new signal using the database's runtime.
///
/// # Parameters
///
/// - `db`: Any type implementing `IncrDb`
/// - `value`: The initial value of the signal
/// - `durability`: How often this signal is expected to change (default: `Low`)
/// - `label`: An optional human-readable name for debugging
///
/// # Returns
///
/// A new signal associated with the database's runtime
pub fn[Db : IncrDb, T] create_signal(
  db : Db,
  value : T,
  durability? : Durability = Low,
  label? : String,
) -> Signal[T] {
  Signal(db.runtime(), value, durability~, label?)
}

///|
/// Creates a new memo using the database's runtime.
///
/// # Parameters
///
/// - `db`: Any type implementing `IncrDb`
/// - `f`: The compute function for the memo
/// - `label`: An optional human-readable name for debugging
///
/// # Returns
///
/// A new memo associated with the database's runtime
pub fn[Db : IncrDb, T : Eq] create_memo(
  db : Db,
  f : () -> T,
  label? : String,
) -> Memo[T] {
  Memo(db.runtime(), f, label?)
}

///|
/// Creates a new keyed memoization map using the database's runtime.
///
/// Each key gets its own lazily-created memo. Repeated reads of the same
/// key reuse that key's cached memoized value.
///
/// # Parameters
///
/// - `db`: Any type implementing `IncrDb`
/// - `f`: The compute function for each key
/// - `label`: An optional label applied to each per-key memo
///
/// # Returns
///
/// A new memo map associated with the database's runtime
pub fn[Db : IncrDb, K, V] create_memo_map(
  db : Db,
  f : (K) -> V,
  label? : String,
) -> MemoMap[K, V] {
  MemoMap(db.runtime(), f, label?)
}

///|
/// Executes a batch of signal updates using the database's runtime.
///
/// All signal updates inside the closure are deferred until the batch ends,
/// resulting in a single revision bump. If the closure raises, pending writes
/// are rolled back and the error is re-raised.
///
/// # Parameters
///
/// - `db`: Any type implementing `IncrDb`
/// - `f`: The closure containing signal updates
pub fn[Db : IncrDb] batch(db : Db, f : () -> Unit raise?) -> Unit raise? {
  db.runtime().batch(f)
}

///|
/// Runs a batch and returns raised errors as `Result`.
pub fn[Db : IncrDb] batch_result(
  db : Db,
  f : () -> Unit raise?,
) -> Result[Unit, Error] {
  db.runtime().batch_result(f)
}

// --- Tracked Struct Support ---

///|
/// Readable implementation for TrackedCell, matching the pattern of
/// Signal and Memo implementations above.
pub impl[T] Readable for TrackedCell[T] with is_up_to_date(self) {
  TrackedCell::is_up_to_date(self)
}

///|
/// Contract for types that contain TrackedCell fields.
///
/// Implementing this trait declares that a type manages field-level
/// incremental state. The trait requires a single method that returns
/// all CellIds owned by the struct, enabling the runtime to perform
/// operations like GC root scanning and bulk introspection.
///
/// A future MoonBit macro system could auto-derive this trait.
///
/// The ordering of CellIds returned by cell_ids() must be stable across
/// calls (i.e., always return fields in the same order).
pub(open) trait Trackable {
  cell_ids(Self) -> Array[CellId]
}

///|
/// Creates a new TrackedCell using the database's runtime.
///
/// Follows the same pattern as `create_signal` and `create_memo`.
///
/// # Parameters
///
/// - `db`: Any type implementing `IncrDb`
/// - `value`: The initial value of the TrackedCell
/// - `durability`: How often this cell is expected to change (default: `Low`)
/// - `label`: An optional human-readable name for debugging
///
/// # Returns
///
/// A new TrackedCell associated with the database's runtime
pub fn[Db : IncrDb, T] create_tracked_cell(
  db : Db,
  value : T,
  durability? : Durability = Low,
  label? : String,
) -> TrackedCell[T] {
  TrackedCell(db.runtime(), value, durability~, label?)
}

///|
/// Marks all cells of a Trackable struct as GC roots (no-op until Phase 4).
///
/// Call this when a tracked struct is "alive" — referenced by the
/// current computation. This function is a no-op until GC infrastructure
/// is added to Runtime (Phase 4 of the roadmap). It is provided now so
/// that user code includes the correct call sites, enabling a zero-change
/// migration when GC lands.
pub fn[T : Trackable] gc_tracked(rt : Runtime, tracked : T) -> Unit {
  // Phase 4 implementation will mark these CellIds as reachable
  // in the Runtime's GC root set.
  let _ids = tracked.cell_ids()
  ignore(rt)
  // Future: rt.mark_gc_roots(ids)
}
