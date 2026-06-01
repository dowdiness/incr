///|
/// Typed handle wrappers around `CellId`.
///
/// Each wrapper carries a phantom type parameter (except `RuleId`) so that
/// handles from different value types cannot be accidentally mixed. The
/// wrappers are nominal — they are distinct types, not aliases.
///
/// These live in `types/` alongside `CellId` so that both `cells/` (which
/// constructs them) and the root facade (which re-exports them) can depend
/// on a single definition.

///|
pub(all) struct SignalId[T] {
  id : CellId
}

///|
pub(all) struct MemoId[T] {
  id : CellId
}

///|
pub(all) struct ReactiveId[T] {
  id : CellId
}

///|
pub(all) struct RelationId[T] {
  id : CellId
}

///|
pub(all) struct FunctionalRelationId[K, V] {
  id : CellId
}

///|
pub(all) struct RuleId {
  id : CellId
}
