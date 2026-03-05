///|
/// Internal SoA entry for a push-mode reactive cell.
///
/// Recomputed eagerly when upstream cells change via push propagation.
/// Uses the same type-erased `compute : () -> Bool` pattern as `PullMemoData`.
priv struct PushReactiveData {
  cell_id : CellId
  label : String?
  /// Type-erased compute closure. Returns true if the value changed (for backdating).
  compute : () -> Bool
  /// Cells this reactive reads (updated on recompute via begin/end_tracking).
  mut sources : Array[CellId]
  /// Cells that depend on this reactive (reverse edges for push propagation).
  subscribers : @hashset.HashSet[CellId]
  /// Last revision where value actually changed (for pull→push boundary).
  mut changed_at : Revision
  /// Topological depth (max source level + 1). Recalculated when sources change.
  mut level : Int
  /// Set true by push propagation when an upstream cell changes.
  mut dirty : Bool
}

///|
impl CellOps for PushReactiveData with cell_id(self) -> CellId {
  self.cell_id
}

///|
impl CellOps for PushReactiveData with changed_at(self) -> Revision {
  self.changed_at
}

///|
impl CellOps for PushReactiveData with set_changed_at(
  self,
  rev : Revision,
) -> Unit {
  self.changed_at = rev
}

///|
impl CellOps for PushReactiveData with subscribers(
  self,
) -> @hashset.HashSet[CellId] {
  self.subscribers
}

///|
impl CellOps for PushReactiveData with label(self) -> String? {
  self.label
}

///|
/// Push cells have no Durability (they always propagate immediately).
/// Returns `Low` as a sentinel value.
impl CellOps for PushReactiveData with durability(self) -> Durability {
  ignore(self)
  Low
}

///|
/// Typed handle for a push-mode reactive cell.
pub struct ReactiveId[T] {
  id : CellId
}

///|
/// User-facing push-mode reactive cell.
///
/// Recomputed eagerly when any upstream cell changes. Value is cached;
/// consecutive reads without upstream changes do not trigger recomputation.
pub struct Reactive[T] {
  priv cell_id : ReactiveId[T]
  priv value : Ref[T?]
  priv rt : Runtime
}
