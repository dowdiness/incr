///|
/// A named, tracked input cell — a thin wrapper around Input[T].
///
/// TrackedCell provides the same functionality as Input but is intended for
/// use cases where you want a more structured, named input cell. All operations
/// delegate directly to the inner Input.
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime()
/// let cell = TrackedCell(rt, 0, label="counter")
/// cell.set(5)
/// inspect(cell.get(), content="5")
/// ```
pub(all) struct TrackedCell[T] {
  priv input : Input[T]
} derive(Debug(ignore=[Input]))

///|
/// Constructor-syntax alias of `TrackedCell::new`. Enables
/// `TrackedCell(rt, value)` / `TrackedCell(rt, value, label="...")` call sites.
pub fn[T] TrackedCell::TrackedCell(
  rt : Runtime,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> TrackedCell[T] {
  TrackedCell::new(rt, initial, durability~, label?)
}

///|
/// Creates a new TrackedCell with the given initial value.
///
/// # Parameters
///
/// - `rt`: The runtime that will manage this cell
/// - `initial`: The initial value of the cell
/// - `durability`: How often this cell is expected to change (default: `Low`)
/// - `label`: An optional human-readable name for debugging and cycle error output
///
/// # Returns
///
/// A new TrackedCell containing the initial value
///
/// # Example
///
/// ```moonbit nocheck
/// let cell = TrackedCell(rt, 42)
///
/// let config = TrackedCell(rt, "prod", durability=High)
///
/// let named = TrackedCell(rt, 0, label="counter")
/// ```
pub fn[T] TrackedCell::new(
  rt : Runtime,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> TrackedCell[T] {
  { input: Input::new(rt, initial, durability~, label?) }
}

///|
/// Returns the current value of the cell.
///
/// If called inside a derived's compute function, this automatically records
/// a dependency from the derived to this cell. When the cell changes,
/// the derived will know to reverify.
///
/// # Returns
///
/// The current value of the cell
pub fn[T] TrackedCell::get(self : TrackedCell[T]) -> T {
  self.input.get()
}

///|
/// Returns the current value of the cell without recording a dependency.
///
/// Delegates to `Input::peek()` on the inner input. Use from outside
/// the dependency graph when you don't want to trigger recomputation.
pub fn[T] TrackedCell::peek(self : TrackedCell[T]) -> T {
  self.input.peek()
}

///|
/// Returns the current value of the cell as a Result.
///
/// Since TrackedCells cannot have cycles (they are input cells with no
/// dependencies), this method always returns `Ok(value)`.
///
/// # Returns
///
/// `Ok(value)` with the current value of the cell
pub fn[T] TrackedCell::get_result(
  self : TrackedCell[T],
) -> Result[T, CycleError] {
  self.input.get_result()
}

///|
/// Sets the cell to a new value.
///
/// If the new value equals the current value (via `Eq`), this is a no-op:
/// no revision bump occurs, and downstream deriveds won't reverify.
///
/// During a batch (`Runtime::batch`), the write is deferred. At batch end,
/// only cells whose final value differs from the pre-batch value trigger
/// a revision bump.
///
/// # Parameters
///
/// - `value`: The new value to set
pub fn[T : Eq] TrackedCell::set(self : TrackedCell[T], value : T) -> Unit {
  self.input.set(value)
}

///|
/// Sets the cell to a new value, always bumping the revision.
///
/// Unlike `set`, this does not check for equality. Use this when you want
/// to force downstream deriveds to reverify even if the value is the same,
/// or when your type doesn't implement `Eq`.
///
/// # Parameters
///
/// - `value`: The new value to set
pub fn[T] TrackedCell::force_set(self : TrackedCell[T], value : T) -> Unit {
  self.input.force_set(value)
}

///|
/// Returns the unique identifier for this cell.
///
/// The CellId can be used with `Runtime::cell_info()` to retrieve
/// metadata, or to compare cell identities.
///
/// # Returns
///
/// The cell identifier for this cell
pub fn[T] TrackedCell::id(self : TrackedCell[T]) -> CellId {
  self.input.id()
}

///|
/// Returns the durability level of this cell.
///
/// Durability indicates how often this cell is expected to change:
/// - `High`: Rarely changes (e.g., configuration)
/// - `Medium`: Moderately stable
/// - `Low`: Frequently changes (e.g., user input)
///
/// # Returns
///
/// The durability level set at construction time
pub fn[T] TrackedCell::durability(self : TrackedCell[T]) -> Durability {
  self.input.durability()
}

///|
/// Registers a callback that fires whenever this cell's value changes.
///
/// The callback receives the new value. Only one callback can be registered
/// at a time; calling this again replaces the previous callback.
///
/// # Parameters
///
/// - `f`: Called with the new value whenever this cell changes
pub fn[T] TrackedCell::on_change(
  self : TrackedCell[T],
  f : (T) -> Unit,
) -> Unit {
  self.input.on_change(f)
}

///|
/// Removes the `on_change` callback for this cell.
pub fn[T] TrackedCell::clear_on_change(self : TrackedCell[T]) -> Unit {
  self.input.clear_on_change()
}

///|
/// Returns true. TrackedCells are always up-to-date since they are input
/// cells with directly-set values.
pub fn[T] TrackedCell::is_up_to_date(self : TrackedCell[T]) -> Bool {
  self.input.is_up_to_date()
}

///|
/// Disposes this tracked cell by disposing its inner input.
pub fn[T] TrackedCell::dispose(self : TrackedCell[T]) -> Unit {
  self.input.dispose()
}

///|
/// Returns true if this tracked cell has been disposed.
pub fn[T] TrackedCell::is_disposed(self : TrackedCell[T]) -> Bool {
  self.input.is_disposed()
}

///|
/// Returns the inner Input for interop with APIs that expect an Input[T].
///
/// # Returns
///
/// The underlying Input[T] wrapped by this TrackedCell
pub fn[T] TrackedCell::as_input(self : TrackedCell[T]) -> Input[T] {
  self.input
}
