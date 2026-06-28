///|
/// An incremental database providing access to its runtime.
///
/// This is the core trait that all incremental systems must implement.
/// It connects user-defined database types to the incr runtime,
/// enabling helpers like `create_input`, `batch`, `create_accumulator`,
/// `create_tracked_cell`, and `create_scope`.
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
/// A readable incremental node.
///
/// This trait provides a common interface for checking whether
/// a node's cached value is current with the latest revision.
/// Both Input and TrackedCell implement this trait.
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
/// Inputs are always up-to-date since they are input cells
/// with directly-set values.
pub impl[T] Readable for Input[T] with fn is_up_to_date(self) {
  Input::is_up_to_date(self)
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
/// Input fields are always up-to-date since they are directly-set cells.
pub impl[T] Readable for InputField[T] with fn is_up_to_date(self) {
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
/// Executes a batch of input updates using the database's runtime.
///
/// All input updates inside the closure are deferred until the batch ends,
/// resulting in a single revision bump. If the closure raises, pending writes
/// are rolled back and the error is re-raised.
///
/// # Parameters
///
/// - `db`: Any type implementing `Database`
/// - `f`: The closure containing the input updates
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
/// Convenience mirror of `create_input` / `create_derived`.
pub fn[Db : Database, T : Eq] create_accumulator(
  db : Db,
  label? : String,
) -> Accumulator[T] {
  Accumulator::new(rt=db.runtime(), label?)
}

// --- Tracked Struct Support ---

///|
/// Readable implementation for TrackedCell, matching the pattern of
/// the Input implementation above.
pub impl[T] Readable for TrackedCell[T] with fn is_up_to_date(self) {
  TrackedCell::is_up_to_date(self)
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
/// Follows the same pattern as `create_input` and `create_derived`.
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
