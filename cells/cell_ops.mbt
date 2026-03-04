///|
/// Uniform interface for all cell kinds in the dependency graph.
///
/// Every cell kind (PullSignal, PullMemo, and future Phase 3+ kinds) implements
/// this trait so Runtime helpers can dispatch without a CellRef match.
///
/// # Object Safety
///
/// All methods take `Self` as the sole receiver (first param, once only).
/// The trait can therefore be used as `&CellOps` in Arrays and function params.
///
/// # Usage
///
/// `Runtime.cell_ops : Array[&CellOps]` is indexed by `CellId.id` — the same
/// index used by `cell_index : Array[CellRef]`. Prefer `cell_ops` for helpers
/// that need only these shared fields; use `cell_index` + direct SoA access in
/// hot paths like `pull_verify`.
trait CellOps {
  cell_id(Self) -> CellId
  changed_at(Self) -> Revision
  set_changed_at(Self, Revision) -> Unit
  subscribers(Self) -> @hashset.HashSet[CellId]
  label(Self) -> String?
  durability(Self) -> Durability
}
