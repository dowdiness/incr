///|
/// Interface for signal cells that have pending values during a batch.
///
/// Implemented by `PullSignalData`. Stored as `&Committable` in
/// `Runtime.batch_pending` so `commit_batch` can iterate and dispatch
/// without a per-entry `CellId → PullSignalData` lookup.
///
/// `cell_id` and `durability` allow `commit_batch` and
/// `recompute_batch_max_durability` to read signal metadata directly from
/// the trait object rather than going back to the SoA array.
trait Committable {
  do_commit(Self) -> Bool
  cell_id(Self) -> CellId
  durability(Self) -> Durability
  fire_on_change_if_set(Self) -> Unit
}

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
///
/// # Internal use only
///
/// Callers dispatching through `&CellOps` are always Runtime internals that
/// have already validated cell ownership. The guards in `get_subscribers`,
/// `get_changed_at`, etc. exist for external entry points; they are not
/// repeated here.
trait CellOps {
  cell_id(Self) -> CellId
  changed_at(Self) -> Revision
  /// Stamps `changed_at` to `rev`. Used by Phase 3 cell kinds that need a
  /// generic write path; current pull-cell internals write the field directly
  /// (see `mark_input_changed`, `force_recompute`).
  set_changed_at(Self, Revision) -> Unit
  /// Returns the **live** subscriber set. Because `HashSet[CellId]` is a
  /// heap-allocated reference, the returned value is a pointer to the SoA
  /// entry's set — `.add` / `.remove` / `.iter` are all visible to the
  /// runtime. Callers must not use this across runtime boundaries.
  subscribers(Self) -> @hashset.HashSet[CellId]
  label(Self) -> String?
  durability(Self) -> Durability
}
