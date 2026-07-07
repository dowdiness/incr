///|
/// InputFieldOwner implementation for input cells.
pub impl[T] InputFieldOwner for Input[T] with fn cell_ids(self) -> Array[CellId] {
  [self.id()]
}

///|
/// InputFieldOwner implementation for input field cells.
pub impl[T] InputFieldOwner for InputField[T] with fn cell_ids(self) -> Array[
  CellId,
] {
  [self.id()]
}

///|
/// InputFieldOwner implementation for derived cells (lazy recomputation).
pub impl[T] InputFieldOwner for Derived[T] with fn cell_ids(self) -> Array[
  CellId,
] {
  [self.id()]
}

///|
/// InputFieldOwner implementation for reachable derived cells (lazy with GC-alive).
pub impl[T] InputFieldOwner for ReachableDerived[T] with fn cell_ids(self) -> Array[
  CellId,
] {
  [self.id()]
}

///|
/// InputFieldOwner implementation for eager derived cells.
pub impl[T] InputFieldOwner for EagerDerived[T] with fn cell_ids(self) -> Array[
  CellId,
] {
  [self.id()]
}
