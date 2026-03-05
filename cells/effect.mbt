///|
/// Internal SoA entry for a push-mode effect cell.
///
/// Terminal node for side effects (DOM updates, logging, etc.).
/// Never read by other cells. Recomputed eagerly when upstream changes.
priv struct PushEffectData {
  cell_id : CellId
  label : String?
  /// Side effect function to run on recompute.
  execute : () -> Unit
  /// Cells this effect reads (updated on recompute).
  mut sources : Array[CellId]
  /// Topological depth (max source level + 1).
  mut level : Int
  /// Set true by push propagation when an upstream cell changes.
  mut dirty : Bool
  /// Always-empty subscriber set (effects are terminal nodes; kept for CellOps uniformity).
  subscribers : @hashset.HashSet[CellId]
}

///|
impl CellOps for PushEffectData with cell_id(self) -> CellId {
  self.cell_id
}

///|
/// Effects have no changed_at semantics (they are terminal and never read).
/// Returns Revision::initial() as a sentinel.
impl CellOps for PushEffectData with changed_at(self) -> Revision {
  ignore(self)
  Revision::initial()
}

///|
impl CellOps for PushEffectData with set_changed_at(
  self,
  _rev : Revision,
) -> Unit {
  ignore(self)
}

///|
/// Effects are terminal nodes — their subscriber set is always empty.
impl CellOps for PushEffectData with subscribers(
  self,
) -> @hashset.HashSet[CellId] {
  self.subscribers
}

///|
impl CellOps for PushEffectData with label(self) -> String? {
  self.label
}

///|
/// Push effects have no Durability. Returns `Low` as a sentinel.
impl CellOps for PushEffectData with durability(self) -> Durability {
  ignore(self)
  Low
}

///|
/// User-facing push-mode effect.
///
/// Runs the provided function immediately on creation to establish
/// dependencies, then re-runs whenever any dependency changes.
pub struct Effect {
  priv cell_id : CellId
  priv rt : Runtime
}
