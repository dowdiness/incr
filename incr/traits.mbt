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
/// impl @incr.Database for MyDb with fn runtime(self) {
///   self.rt
/// }
/// ```
pub(open) trait Database {
  fn runtime(Self) -> Runtime
}

///|
/// A lightweight provider for target-facade constructors.
///
/// `RuntimeContext` intentionally mirrors `Database::runtime` without changing
/// the existing `Database` trait or its compatibility helper surface.
pub(open) trait RuntimeContext {
  fn runtime(Self) -> Runtime
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
  fn is_up_to_date(Self) -> Bool
}

///|
/// Target-name freshness trait for readable incremental nodes.
///
/// `Freshness` mirrors `Readable` during the compatibility window while using
/// target API vocabulary. Use it for new generic code that only needs to ask
/// whether a handle is current with its runtime's latest revision.
pub(open) trait Freshness {
  /// Returns true if the node is fresh at the current revision.
  fn is_fresh(Self) -> Bool
}

///|
/// Signals are always up-to-date since they are input cells
/// with directly-set values.
pub impl[T] Readable for Signal[T] with fn is_up_to_date(self) {
  Signal::is_up_to_date(self)
}


///|
/// Target inputs are always fresh because they are directly-set cells.
pub impl[T] Freshness for Input[T] with fn is_fresh(self) {
  Input::is_fresh(self)
}

///|
/// Target input fields are always fresh because they are directly-set cells.
pub impl[T] Freshness for InputField[T] with fn is_fresh(self) {
  InputField::is_fresh(self)
}

///|
/// A target derived value is fresh when its cached value is verified.
pub impl[T] Freshness for Derived[T] with fn is_fresh(self) {
  Derived::is_fresh(self)
}

///|
/// A reachable target derived value is fresh when its cached value is verified.
pub impl[T] Freshness for ReachableDerived[T] with fn is_fresh(self) {
  ReachableDerived::is_fresh(self)
}

///|
/// Creates a new signal using the database's runtime.
///
/// # Parameters
///
/// - `db`: Any type implementing `Database`
/// - `value`: The initial value of the signal
/// - `durability`: How often this signal is expected to change (default: `Low`)
/// - `label`: An optional human-readable name for debugging
///
/// # Returns
///
/// A new signal associated with the database's runtime
pub fn[Db : Database, T] create_signal(
  db : Db,
  value : T,
  durability? : Durability = Low,
  label? : String,
) -> Signal[T] {
  Signal(db.runtime(), value, durability~, label?)
}


///|
/// Creates a target-name input facade using the context runtime.
pub fn[Ctx : RuntimeContext, T] create_input(
  ctx : Ctx,
  value : T,
  durability? : Durability = Low,
  label? : String,
) -> Input[T] {
  Input(ctx.runtime(), value, durability~, label?)
}

///|
/// Creates a target-name input-field facade using the context runtime.
pub fn[Ctx : RuntimeContext, T] create_input_field(
  ctx : Ctx,
  value : T,
  durability? : Durability = Low,
  label? : String,
) -> InputField[T] {
  InputField(ctx.runtime(), value, durability~, label?)
}

///|
/// Creates a target-name lazy derived facade using the context runtime.
pub fn[Ctx : RuntimeContext, T : Eq] create_derived(
  ctx : Ctx,
  f : () -> T raise Failure,
  label? : String,
) -> Derived[T] {
  Derived(ctx.runtime(), f, label?)
}

///|
/// Creates a target-name reachable lazy derived facade using the context runtime.
pub fn[Ctx : RuntimeContext, T : Eq] create_reachable_derived(
  ctx : Ctx,
  f : () -> T raise Failure,
  label? : String,
) -> ReachableDerived[T] {
  ReachableDerived(ctx.runtime(), f, label?)
}

///|
/// Creates a target-name eager derived facade using the context runtime.
pub fn[Ctx : RuntimeContext, T : Eq] create_eager_derived(
  ctx : Ctx,
  compute : () -> T,
) -> EagerDerived[T] {
  EagerDerived(ctx.runtime(), compute)
}

///|
/// Creates a target-name keyed derived facade using the context runtime.
pub fn[Ctx : RuntimeContext, K : Hash + Eq, V] create_derived_map(
  ctx : Ctx,
  f : (K) -> V raise Failure,
  label? : String,
) -> DerivedMap[K, V] {
  DerivedMap(ctx.runtime(), f, label?)
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
/// - `db`: Any type implementing `Database`
/// - `f`: The closure containing signal updates
pub fn[Db : Database] batch(db : Db, f : () -> Unit raise?) -> Unit raise? {
  db.runtime().batch(f)
}

///|
/// Runs a batch and returns raised errors as `Result`.
pub fn[Db : Database] batch_result(
  db : Db,
  f : () -> Unit raise,
) -> Result[Unit, Error] {
  db.runtime().batch_result(f)
}

///|
/// Creates an accumulator bound to the database's underlying runtime.
/// Convenience mirror of `create_signal` / `create_memo`.
pub fn[Db : Database, T : Eq] create_accumulator(
  db : Db,
  label? : String,
) -> Accumulator[T] {
  Accumulator::new(rt=db.runtime(), label?)
}

// --- Tracked Struct Support ---

///|
/// Readable implementation for TrackedCell, matching the pattern of
/// Signal and Memo implementations above.
pub impl[T] Readable for TrackedCell[T] with fn is_up_to_date(self) {
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
  fn cell_ids(Self) -> Array[CellId]
}

///|
/// Target-name contract for types that own `InputField` fields.
///
/// The returned cell IDs must be stable across calls and belong to the runtime
/// of any scope they are registered with.
pub(open) trait InputFieldOwner {
  fn cell_ids(Self) -> Array[CellId]
}

///|
/// Creates a new TrackedCell using the database's runtime.
///
/// Follows the same pattern as `create_signal` and `create_memo`.
///
/// # Parameters
///
/// - `db`: Any type implementing `Database`
/// - `value`: The initial value of the TrackedCell
/// - `durability`: How often this cell is expected to change (default: `Low`)
/// - `label`: An optional human-readable name for debugging
///
/// # Returns
///
/// A new TrackedCell associated with the database's runtime
pub fn[Db : Database, T] create_tracked_cell(
  db : Db,
  value : T,
  durability? : Durability = Low,
  label? : String,
) -> TrackedCell[T] {
  TrackedCell(db.runtime(), value, durability~, label?)
}

///|
/// Registers all cells from a Trackable struct with a scope for bulk disposal.
///
/// When the scope is disposed, all registered cells are disposed.
/// This is the recommended way to manage TrackedCell lifetimes.
///
/// # Example
///
/// ```moonbit nocheck
/// let scope = Scope::new(rt)
/// let tracked = MyTracked::new(rt)
/// add_tracked(scope, tracked)
/// scope.dispose()  // disposes all tracked cells
/// ```
pub fn[T : Trackable] add_tracked(scope : Scope, tracked : T) -> Unit {
  scope.add_cell_ids(tracked.cell_ids())
}

///|
/// Registers all cells from an `InputFieldOwner` with a scope for bulk disposal.
pub fn[T : InputFieldOwner] add_input_fields(scope : Scope, owner : T) -> Unit {
  scope.add_cell_ids(owner.cell_ids())
}

///|
/// Creates a new root scope using the database's runtime.
///
/// Cells created via the scope's constructors are automatically disposed
/// when the scope is disposed. Use `scope.child()` for nested scopes.
///
/// # Parameters
///
/// - `db`: Any type implementing `Database`
///
/// # Returns
///
/// A new root scope associated with the database's runtime
pub fn[Db : Database] create_scope(db : Db) -> Scope {
  Scope::new(db.runtime())
}
