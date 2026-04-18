///|
/// Internal SoA entry for a push-mode reactive cell.
///
/// Recomputed eagerly when upstream cells change via push propagation.
/// Uses the same type-erased `compute : () -> Bool` pattern as `MemoData`.
pub(all) struct PushReactiveData {
  meta : CellMeta
  /// Type-erased compute closure. Returns true if the value changed (for backdating).
  mut compute : () -> Bool
  /// Cells this reactive reads (updated on recompute via begin/end_tracking).
  mut sources : Array[CellId]
  /// Topological depth (max source level + 1). Recalculated when sources change.
  mut level : Int
  /// Set true by push propagation when an upstream cell changes.
  mut dirty : Bool
}

///|
pub impl HasCellMeta for PushReactiveData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for push-reactive cells — defaults via HasCellMeta,
/// with sentinel durability and stored level overrides.
pub impl CellOps for PushReactiveData

///|
/// Push cells have no Durability (they always propagate immediately).
/// Returns `Low` as a sentinel value.
pub impl CellOps for PushReactiveData with durability(self) -> Durability {
  ignore(self)
  Low
}

///|
pub impl CellOps for PushReactiveData with level(self) -> Int {
  self.level
}

///|
pub impl CellOps for PushReactiveData with gc_role(_self) -> GcRole {
  Interior
}

///|
pub impl CellOps for PushReactiveData with gc_dependencies(self) -> Array[
  CellId,
] {
  self.sources
}

///|
/// Clears all mutable fields to release captured closures and graph edges.
/// Called by the CellLifecycle dispose impl after removing subscriber links.
pub fn PushReactiveData::clear_slot(self : PushReactiveData) -> Unit {
  self.compute = () => false
  self.sources.clear()
  self.meta.subscribers.clear()
  self.meta.label = None
  self.meta.changed_at = Revision::initial()
  self.level = 0
  self.dirty = false
}
