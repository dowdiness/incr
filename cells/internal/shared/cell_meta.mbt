///|
/// Shared metadata fields carried by every cell kind.
///
/// Extracted from the per-type SoA data structs so that `CellOps` default
/// methods can delegate through `HasCellMeta::meta()` instead of requiring
/// identical one-liner impls on every cell type.
pub(all) struct CellMeta {
  cell_id : CellId
  mut label : String?
  mut changed_at : Revision
  mut durability : Durability
  subscribers : @hashset.HashSet[CellId]
  mut push_reachable_count : Int
}
