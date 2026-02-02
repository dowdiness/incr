///|
/// Unique identifier for a cell in the Runtime.
pub(all) struct CellId {
  id : Int
} derive(Show, Eq)

///|
impl Hash for CellId with hash(self) {
  self.id.hash()
}

///|
impl Hash for CellId with hash_combine(self, hasher) {
  self.id.hash_combine(hasher)
}

///|
/// Distinguishes input cells from derived cells.
pub enum CellKind {
  Input
  Derived
} derive(Show, Eq)

///|
/// Type-erased cell metadata stored in the Runtime.
/// Actual typed values live in Signal[T] and Memo[T].
pub(all) struct CellMeta {
  id : CellId
  kind : CellKind
  mut changed_at : Revision
  mut verified_at : Revision
  mut dependencies : Array[CellId]
  mut durability : Durability
  /// For derived cells: recomputes and returns true if value changed.
  /// None for input cells.
  recompute_and_check : (() -> Bool)?
  /// Cycle detection flag.
  mut in_progress : Bool
}

///|
pub fn CellMeta::new_input(id : CellId, durability : Durability) -> CellMeta {
  {
    id,
    kind: Input,
    changed_at: Revision::initial(),
    verified_at: Revision::initial(),
    dependencies: [],
    durability,
    recompute_and_check: None,
    in_progress: false,
  }
}

///|
pub fn CellMeta::new_derived(
  id : CellId,
  recompute_and_check : () -> Bool,
) -> CellMeta {
  {
    id,
    kind: Derived,
    changed_at: Revision::initial(),
    verified_at: Revision::initial(),
    dependencies: [],
    durability: Low,
    recompute_and_check: Some(recompute_and_check),
    in_progress: false,
  }
}
