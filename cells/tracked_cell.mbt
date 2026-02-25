///|
/// A named, tracked input cell — a thin wrapper around Signal[T].
///
/// TrackedCell provides the same functionality as Signal but is intended for
/// use cases where you want a more structured, named input cell. All operations
/// delegate directly to the inner Signal.
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
  priv signal : Signal[T]

  fn[T] new(
    rt : Runtime,
    initial : T,
    durability? : Durability,
    label? : String,
  ) -> TrackedCell[T]
} derive(Debug(ignore=[Signal]))

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
  { signal: Signal::new(rt, initial, durability~, label?) }
}

///|
/// Returns the current value of the cell.
///
/// If called inside a memo's compute function, this automatically records
/// a dependency from the memo to this cell. When the cell changes,
/// the memo will know to reverify.
///
/// # Returns
///
/// The current value of the cell
pub fn[T] TrackedCell::get(self : TrackedCell[T]) -> T {
  self.signal.get()
}

///|
/// Returns the current value of the cell as a Result.
///
/// This method exists for API consistency with `Memo::get_result()`.
/// Since TrackedCells cannot have cycles (they are input cells with no
/// dependencies), this method always returns `Ok(value)`.
///
/// # Returns
///
/// `Ok(value)` with the current value of the cell
pub fn[T] TrackedCell::get_result(
  self : TrackedCell[T],
) -> Result[T, CycleError] {
  self.signal.get_result()
}

///|
/// Sets the cell to a new value.
///
/// If the new value equals the current value (via `Eq`), this is a no-op:
/// no revision bump occurs, and downstream memos won't reverify.
///
/// During a batch (`Runtime::batch`), the write is deferred. At batch end,
/// only cells whose final value differs from the pre-batch value trigger
/// a revision bump.
///
/// # Parameters
///
/// - `value`: The new value to set
pub fn[T : Eq] TrackedCell::set(self : TrackedCell[T], value : T) -> Unit {
  self.signal.set(value)
}

///|
/// Sets the cell to a new value, always bumping the revision.
///
/// Unlike `set`, this does not check for equality. Use this when you want
/// to force downstream memos to reverify even if the value is the same,
/// or when your type doesn't implement `Eq`.
///
/// # Parameters
///
/// - `value`: The new value to set
pub fn[T] TrackedCell::set_unconditional(
  self : TrackedCell[T],
  value : T,
) -> Unit {
  self.signal.set_unconditional(value)
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
  self.signal.id()
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
  self.signal.durability()
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
  self.signal.on_change(f)
}

///|
/// Removes the `on_change` callback for this cell.
pub fn[T] TrackedCell::clear_on_change(self : TrackedCell[T]) -> Unit {
  self.signal.clear_on_change()
}

///|
/// Returns true. TrackedCells are always up-to-date since they are input
/// cells with directly-set values.
pub fn[T] TrackedCell::is_up_to_date(self : TrackedCell[T]) -> Bool {
  self.signal.is_up_to_date()
}

///|
/// Returns the inner Signal for interop with APIs that expect a Signal[T].
///
/// # Returns
///
/// The underlying Signal[T] wrapped by this TrackedCell
pub fn[T] TrackedCell::as_signal(self : TrackedCell[T]) -> Signal[T] {
  self.signal
}
