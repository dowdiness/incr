///|
/// Internal SoA entry for a push-mode effect cell.
///
/// Terminal node for side effects (DOM updates, logging, etc.).
/// Never read by other cells. Recomputed eagerly when upstream changes.
pub(all) struct PushEffectData {
  meta : CellMeta
  /// Side effect function to run on recompute.
  mut execute : () -> Unit
  /// Cells this effect reads (updated on recompute).
  mut sources : Array[CellId]
  /// Topological depth (max source level + 1).
  mut level : Int
  /// Set true by push propagation when an upstream cell changes.
  mut dirty : Bool
}

///|
pub impl HasCellMeta for PushEffectData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for push-effect cells — defaults via HasCellMeta,
/// with sentinel overrides for changed_at, set_changed_at, durability, and level.
pub impl CellOps for PushEffectData

///|
/// Effects have no changed_at semantics (they are terminal and never read).
/// Returns Revision::initial() as a sentinel.
pub impl CellOps for PushEffectData with changed_at(self) -> Revision {
  ignore(self)
  Revision::initial()
}

///|
pub impl CellOps for PushEffectData with set_changed_at(self, _rev : Revision) -> Unit {
  ignore(self)
}

///|
/// Push effects have no Durability. Returns `Low` as a sentinel.
pub impl CellOps for PushEffectData with durability(self) -> Durability {
  ignore(self)
  Low
}

///|
pub impl CellOps for PushEffectData with level(self) -> Int {
  self.level
}

///|
pub impl CellOps for PushEffectData with gc_role(_self) -> GcRole {
  Root
}

///|
pub impl CellOps for PushEffectData with gc_dependencies(self) -> Array[CellId] {
  self.sources
}

///|
/// Clears all mutable fields to release captured closures and graph edges.
/// Called by the CellLifecycle dispose impl after removing subscriber links.
pub fn PushEffectData::clear_slot(self : PushEffectData) -> Unit {
  self.execute = () => ()
  self.sources.clear()
  self.meta.subscribers.clear()
  self.meta.label = None
  self.level = 0
  self.dirty = false
}
