///|
/// An incremental database providing access to its runtime.
///
/// This is the core trait that all incremental systems must implement.
/// It connects user-defined database types to the incr runtime,
/// enabling generic helper functions like `create_signal` and `create_memo`.
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
  @internal.Signal::is_up_to_date(self)
}

///|
/// A memo is up-to-date when its verified_at matches the
/// runtime's current revision.
pub impl[T] Readable for Memo[T] with is_up_to_date(self) {
  @internal.Memo::is_up_to_date(self)
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
  Signal::new(db.runtime(), value, durability~, label?)
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
  Memo::new(db.runtime(), f, label?)
}

///|
/// Executes a batch of signal updates using the database's runtime.
///
/// All signal updates inside the closure are deferred until the batch ends,
/// resulting in a single revision bump.
///
/// # Parameters
///
/// - `db`: Any type implementing `IncrDb`
/// - `f`: The closure containing signal updates
pub fn[Db : IncrDb] batch(db : Db, f : () -> Unit) -> Unit {
  db.runtime().batch(f)
}
