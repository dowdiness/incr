///|
using @incr_types {type CellId, type Revision, type Durability, type GcRole}

///|
/// Interface for signal cells that have pending values during a batch.
///
/// Implemented by `PullSignalData`. Stored as `&Committable` in
/// `Runtime.core.batch.pending` so `commit_batch` can iterate and dispatch
/// without a per-entry `CellId → PullSignalData` lookup.
///
/// `cell_id` and `durability` allow `commit_batch` and
/// `recompute_batch_max_durability` to read signal metadata directly from
/// the trait object rather than going back to the SoA array.
pub(open) trait Committable {
  do_commit(Self) -> Bool
  cell_id(Self) -> CellId
  durability(Self) -> Durability
}

///|
/// Returns a cell's shared metadata. Implemented by every SoA data struct.
pub(open) trait HasCellMeta {
  meta(Self) -> CellMeta
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
pub(open) trait CellOps: HasCellMeta {
  cell_id(Self) -> CellId = _
  changed_at(Self) -> Revision = _
  /// Stamps `changed_at` to `rev`. Used by `propagate_changes` to stamp all
  /// changed cells generically, and by cell kinds that need a direct write path
  /// (see `force_recompute`).
  set_changed_at(Self, Revision) -> Unit = _
  /// Returns the **live** subscriber set. Because `HashSet[CellId]` is a
  /// heap-allocated reference, the returned value is a pointer to the SoA
  /// entry's set — `.add` / `.remove` / `.iter` are all visible to the
  /// runtime. Callers must not use this across runtime boundaries.
  subscribers(Self) -> @hashset.HashSet[CellId] = _
  label(Self) -> String? = _
  durability(Self) -> Durability = _

  /// Returns the topological level of this cell for push propagation.
  /// Pull cells and leaf cells return 0. Push reactives return their stored level.
  level(Self) -> Int = _

  /// Determines whether this cell's dependency has changed since `verified_at`.
  ///
  /// Returns `Some(true)` if changed, `Some(false)` if fresh, `None` if deep
  /// verification is required (memo-like cells).
  dep_changed_since(Self, Revision) -> Bool? = _

  /// Number of subscriber-path routes from this cell to a live push cell.
  /// > 0 iff at least one live push cell (Reactive/Effect) is downstream.
  push_reachable_count(Self) -> Int = _

  /// GC role of this cell. Default: Source (input cells).
  gc_role(Self) -> GcRole = _

  /// Upstream dependencies for GC marking. Default: empty.
  gc_dependencies(Self) -> Array[CellId] = _
}

///|
/// Default: cell_id from shared metadata.
impl CellOps with cell_id(self) -> CellId {
  HasCellMeta::meta(self).cell_id
}

///|
/// Default: changed_at from shared metadata.
impl CellOps with changed_at(self) -> Revision {
  HasCellMeta::meta(self).changed_at
}

///|
/// Default: set_changed_at on shared metadata.
impl CellOps with set_changed_at(self, rev) -> Unit {
  HasCellMeta::meta(self).changed_at = rev
}

///|
/// Default: subscribers from shared metadata.
impl CellOps with subscribers(self) -> @hashset.HashSet[CellId] {
  HasCellMeta::meta(self).subscribers
}

///|
/// Default: label from shared metadata.
impl CellOps with label(self) -> String? {
  HasCellMeta::meta(self).label
}

///|
/// Default: durability from shared metadata.
impl CellOps with durability(self) -> Durability {
  HasCellMeta::meta(self).durability
}

///|
/// Default: level 0 (leaf/pull cells). Override for push cells that store a level.
impl CellOps with level(_self) -> Int {
  0
}

///|
/// Default: leaf-cell freshness check via `changed_at`.
/// Override to return `None` for memo-like cells that need deep verification.
impl CellOps with dep_changed_since(self, verified_at) -> Bool? {
  Some(self.changed_at() > verified_at)
}

///|
/// Default: push_reachable_count from shared metadata.
impl CellOps with push_reachable_count(self) -> Int {
  HasCellMeta::meta(self).push_reachable_count
}

///|
/// Default: Source role (input cells — never collected).
impl CellOps with gc_role(_self) -> GcRole {
  Source
}

///|
/// Default: no dependencies (leaf cells).
impl CellOps with gc_dependencies(_self) -> Array[CellId] {
  []
}
