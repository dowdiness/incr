///|
/// A provider of the runtime that owns a piece of incremental state.
///
/// This is the core trait that user-defined database/context types implement
/// to connect to the incr runtime. It enables helpers like `create_input`,
/// `create_derived`, `batch`, `create_accumulator`, and `create_scope`.
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
/// impl @incr.RuntimeContext for MyDb with fn runtime(self) {
///   self.rt
/// }
/// ```
pub(open) trait RuntimeContext {
  fn runtime(Self) -> Runtime
}

///|
/// Freshness trait for readable incremental nodes.
///
/// Use it for generic code that only needs to ask whether a handle is
/// current with its runtime's latest revision.
pub(open) trait Freshness {
  /// Returns true if the node is fresh at the current revision.
  fn is_fresh(Self) -> Bool
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
/// Executes a batch of input updates using the context runtime.
///
/// All input updates inside the closure are deferred until the batch ends,
/// resulting in a single revision bump. If the closure raises, pending writes
/// are rolled back and the error is re-raised.
///
/// # Parameters
///
/// - `ctx`: Any type implementing `RuntimeContext`
/// - `f`: The closure containing the input updates
pub fn[Ctx : RuntimeContext] batch(
  ctx : Ctx,
  f : () -> Unit raise?,
) -> Unit raise? {
  ctx.runtime().batch(f)
}

///|
/// Runs a batch and returns raised errors as `Result`.
pub fn[Ctx : RuntimeContext] batch_result(
  ctx : Ctx,
  f : () -> Unit raise,
) -> Result[Unit, Error] {
  ctx.runtime().batch_result(f)
}

///|
/// Convenience mirror of `create_input` / `create_derived`.
pub fn[Ctx : RuntimeContext, T : Eq] create_accumulator(
  ctx : Ctx,
  label? : String,
) -> Accumulator[T] {
  Accumulator(ctx.runtime(), label?)
}

// --- Input-field owner support ---

///|
/// Registers all cells from an `InputFieldOwner` with a scope for bulk disposal.
///
/// When the scope is disposed, all registered cells are disposed.
/// This is the recommended way to manage the lifetimes of cells owned by a
/// struct.
///
/// # Example
///
/// ```moonbit nocheck
/// let scope = Scope::new(rt)
/// let owner = MyTracked::new(rt)
/// add_input_fields(scope, owner)
/// scope.dispose()  // disposes all owned cells
/// ```
pub fn[T : InputFieldOwner] add_input_fields(scope : Scope, owner : T) -> Unit {
  scope.add_cell_ids(owner.cell_ids())
}

///|
/// Creates a new root scope using the context runtime.
///
/// Cells created via the scope's constructors are automatically disposed
/// when the scope is disposed. Use `scope.child()` for nested scopes.
///
/// # Parameters
///
/// - `ctx`: Any type implementing `RuntimeContext`
///
/// # Returns
///
/// A new root scope associated with the context runtime
pub fn[Ctx : RuntimeContext] create_scope(ctx : Ctx) -> Scope {
  Scope::new(ctx.runtime())
}
