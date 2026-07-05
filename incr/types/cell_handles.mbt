///|
/// Typed handle wrappers around `CellId`.
///
/// Each wrapper carries a phantom type parameter (except `RuleId`) so that
/// handles from different value types cannot be accidentally mixed. The
/// wrappers are nominal — they are distinct types, not aliases.
///
/// These live in `types/` alongside `CellId` so that `cells/` (which
/// constructs them) can depend on a single definition. `RuleId` is also
/// re-exported by the root facade; `ReactiveId` is internal to the
/// `Reactive[T]` compatibility handle.

///|
pub(all) struct ReactiveId[T] {
  id : CellId
}

///|
pub(all) struct RuleId {
  id : CellId
}
