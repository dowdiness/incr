///|
/// A read-only view of an input cell.
///
/// Obtain an `InputView` with `input[:]` or `input.as_view()`. The view reads
/// the same cell as its source, but does not expose write, callback, or disposal
/// authority.
pub(all) struct InputView[T] {
  priv input : Input[T]
}

///|
/// Returns a read-only view of this input.
///
/// `input[:]` is equivalent to `input.as_view()`. The view records
/// dependencies through `InputView::get()` and cannot update or dispose the
/// underlying input.
///
/// # Example
///
/// ```moonbit nocheck
/// let input = Input(rt, 42)
/// let view = input[:]
/// let doubled = Derived(rt, () => view.get() * 2)
///
/// input.set(21)
/// inspect(doubled.read_or_abort(), content="42")
/// ```
#alias("_[_:_]")
pub fn[T] Input::as_view(
  self : Input[T],
  start? : Unit,
  end? : Unit,
) -> InputView[T] {
  ignore(start)
  ignore(end)
  { input: self }
}

///|
/// Returns a read-only view of this input field.
///
/// `field[:]` is equivalent to `field.as_view()` and returns a view of the
/// field's underlying input cell.
#alias("_[_:_]")
pub fn[T] InputField::as_view(
  self : InputField[T],
  start? : Unit,
  end? : Unit,
) -> InputView[T] {
  ignore(start)
  ignore(end)
  { input: self.input }
}

///|
/// Returns the current value and records a dependency in a reactive compute.
///
/// This follows the same strict lifecycle contract as `Input::get()`.
pub fn[T] InputView::get(self : InputView[T]) -> T {
  self.input.get()
}

///|
/// Returns the current value without recording a dependency.
///
/// This follows the same strict lifecycle contract as `Input::peek()`.
pub fn[T] InputView::peek(self : InputView[T]) -> T {
  self.input.peek()
}
