///|
/// Target-name field-level input cell — a thin wrapper around Input[T].
///
/// InputField provides the same functionality as Input but is intended for
/// use cases where you want a more structured, named input cell (e.g. fields
/// of a tracked struct). All operations delegate directly to the inner Input.
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime()
/// let field = InputField(rt, 0, label="counter")
/// field.set(5)
/// inspect(field.get(), content="5")
/// ```
pub(all) struct InputField[T] {
  priv input : Input[T]
} derive(Debug(ignore=[Input]))

///|
/// Creates a field-level input cell with the given initial value.
///
/// # Parameters
///
/// - `rt`: The runtime that will manage this cell
/// - `initial`: The initial value of the field
/// - `durability`: How often this field is expected to change (default: `Low`)
/// - `label`: An optional human-readable name for debugging and cycle error output
///
/// # Returns
///
/// A new InputField containing the initial value
///
/// # Example
///
/// ```moonbit nocheck
/// let field = InputField(rt, 42)
///
/// let config = InputField(rt, "prod", durability=High)
///
/// let named = InputField(rt, 0, label="counter")
/// ```
pub fn[T] InputField::InputField(
  rt : Runtime,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> InputField[T] {
  { input: Input(rt, initial, durability~, label?) }
}

///|
/// Returns the current value of the field.
///
/// If called inside a derived's compute function, this automatically records
/// a dependency from the derived to this cell. When the field changes,
/// the derived will know to reverify.
///
/// # Returns
///
/// The current value of the field
pub fn[T] InputField::get(self : InputField[T]) -> T {
  self.input.get()
}

///|
/// Returns the current value of the field without recording a dependency.
///
/// Delegates to `Input::peek()` on the inner input. Use from outside
/// the dependency graph when you don't want to trigger recomputation.
pub fn[T] InputField::peek(self : InputField[T]) -> T {
  self.input.peek()
}

///|
/// Returns the current value of the field as a Result.
///
/// Since InputFields cannot have cycles (they are direct-set cells with no
/// dependencies), this method always returns `Ok(value)`.
///
/// # Returns
///
/// `Ok(value)` with the current value of the field
pub fn[T] InputField::get_result(self : InputField[T]) -> Result[T, CycleError] {
  self.input.get_result()
}

///|
/// Sets the field to a new value.
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
/// - `new_value`: The new value to set
pub fn[T : Eq] InputField::set(self : InputField[T], new_value : T) -> Unit {
  self.input.set(new_value)
}

///|
/// Sets the field to a new value, always bumping the revision.
///
/// Unlike `set`, this does not check for equality. Use this when you want
/// to force downstream deriveds to reverify even if the value is the same,
/// or when your type doesn't implement `Eq`.
///
/// # Parameters
///
/// - `new_value`: The new value to set
pub fn[T] InputField::force_set(self : InputField[T], new_value : T) -> Unit {
  self.input.force_set(new_value)
}

///|
/// Returns the unique identifier for this field.
///
/// The CellId can be used with `Runtime::cell_info()` to retrieve
/// metadata, or to compare cell identities.
///
/// # Returns
///
/// The cell identifier for this field
pub fn[T] InputField::id(self : InputField[T]) -> CellId {
  self.input.id()
}

///|
/// Returns the durability level of this field.
///
/// Durability indicates how often this field is expected to change:
/// - `High`: Rarely changes (e.g., configuration)
/// - `Medium`: Moderately stable
/// - `Low`: Frequently changes (e.g., user input)
///
/// # Returns
///
/// The durability level set at construction time
pub fn[T] InputField::durability(self : InputField[T]) -> Durability {
  self.input.durability()
}

///|
/// Registers a callback that fires whenever this field's value changes.
///
/// The callback receives the new value. Only one callback can be registered
/// at a time; calling this again replaces the previous callback.
///
/// # Parameters
///
/// - `f`: Called with the new value whenever this field changes
pub fn[T] InputField::on_change(self : InputField[T], f : (T) -> Unit) -> Unit {
  self.input.on_change(f)
}

///|
/// Removes this field's `on_change` callback.
pub fn[T] InputField::clear_on_change(self : InputField[T]) -> Unit {
  self.input.clear_on_change()
}

///|
/// Returns true. Input fields are directly-set cells and are always fresh.
pub fn[T] InputField::is_fresh(self : InputField[T]) -> Bool {
  self.input.is_up_to_date()
}

///|
/// Disposes this field by disposing its inner input.
pub fn[T] InputField::dispose(self : InputField[T]) -> Unit {
  self.input.dispose()
}

///|
/// Returns true if this field has been disposed.
pub fn[T] InputField::is_disposed(self : InputField[T]) -> Bool {
  self.input.is_disposed()
}
