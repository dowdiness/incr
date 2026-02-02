///|
/// An externally-set input value. The T: Eq constraint enables
/// same-value optimization (skip revision bump if value unchanged).
pub struct Signal[T] {
  rt : Runtime
  cell_id : CellId
  mut value : T
  durability : Durability
}

///|
/// Create a new Signal with Low durability.
pub fn[T] Signal::new(rt : Runtime, initial : T) -> Signal[T] {
  Signal::new_with_durability(rt, initial, Low)
}

///|
/// Create a new Signal with the specified durability.
pub fn[T] Signal::new_with_durability(
  rt : Runtime,
  initial : T,
  durability : Durability,
) -> Signal[T] {
  let cell_id = rt.alloc_cell_id()
  let meta = CellMeta::new_input(cell_id, durability)
  rt.register_cell(meta)
  { rt, cell_id, value: initial, durability }
}

///|
/// Read the signal value and record a dependency in the current tracking context.
pub fn[T] Signal::get(self : Signal[T]) -> T {
  self.rt.record_dependency(self.cell_id)
  self.value
}

///|
/// Set the signal value. If the new value equals the old value (via Eq),
/// this is a no-op — no revision bump occurs.
pub fn[T : Eq] Signal::set(self : Signal[T], new_value : T) -> Unit {
  if self.value == new_value {
    return
  }
  self.set_unconditional(new_value)
}

///|
/// Set the signal value unconditionally, always bumping the revision.
pub fn[T] Signal::set_unconditional(
  self : Signal[T],
  new_value : T,
) -> Unit {
  self.value = new_value
  self.rt.bump_revision(self.durability)
  let meta = self.rt.get_cell(self.cell_id)
  meta.changed_at = self.rt.current_revision
  meta.verified_at = self.rt.current_revision
}
