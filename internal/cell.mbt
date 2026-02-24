///|
using @incr_types {type Revision, type Durability, type CellId}

///|
/// Distinguishes input cells (Signals) from derived cells (Memos).
///
/// This affects how verification works:
/// - `Input`: Changed directly by user; verification simply checks `changed_at`
/// - `Derived`: Computed from dependencies; verification walks the dependency graph
priv enum CellKind {
  Input
  Derived
}

///|
/// Type-erased cell metadata stored in the runtime.
///
/// This struct contains all revision tracking and dependency information
/// for a cell, independent of the cell's value type. The actual typed values
/// live in the `Signal[T]` and `Memo[T]` structs held by user code.
///
/// This separation allows the verification algorithm to operate on all cells
/// uniformly without knowing their value types.
priv struct CellMeta {
  id : CellId
  kind : CellKind
  mut changed_at : Revision
  mut verified_at : Revision
  mut dependencies : Array[CellId]
  mut durability : Durability
  /// For derived cells: recomputes and returns true if value changed.
  /// Returns Err(CycleError) if a cycle is detected during recomputation.
  /// None for input cells.
  mut recompute_and_check : (() -> Result[Bool, CycleError])?
  /// For input cells during batch: commits pending value and returns true
  /// if the committed value differs from the current value.
  /// None for derived cells or inputs outside a batch.
  mut commit_pending : (() -> Bool)?
  /// Called when the cell's value changes.
  /// Invoked after a signal is set or a memo recomputes to a new value.
  /// None if no callback is registered.
  mut on_change : (() -> Unit)?
  /// Cycle detection flag.
  mut in_progress : Bool
  /// Reverse dependency links: cells that depend on this cell.
  /// Maintained during Memo::force_recompute dep diffing.
  subscribers : @hashset.HashSet[CellId]
  /// Optional human-readable label for debugging and introspection.
  // `mut` is intentionally absent: `label` is set once at construction
  // (CellMeta::new_input / CellMeta::new_derived) and never reassigned
  // anywhere in the codebase — including whitebox tests. This is the
  // permanent design; no future task plans to add post-construction writes.
  label : String?
}

///|
/// Creates metadata for a new input cell (Signal).
///
/// # Parameters
///
/// - `id`: The unique identifier for this cell
/// - `durability`: How often this input is expected to change
/// - `label`: Optional human-readable name for debugging and introspection
///
/// # Returns
///
/// Initialized cell metadata with `kind = Input`
fn CellMeta::new_input(
  id : CellId,
  durability : Durability,
  label : String?,
) -> CellMeta {
  {
    id,
    kind: Input,
    changed_at: Revision::initial(),
    verified_at: Revision::initial(),
    dependencies: [],
    durability,
    recompute_and_check: None,
    commit_pending: None,
    on_change: None,
    in_progress: false,
    subscribers: @hashset.new(),
    label,
  }
}

///|
/// Creates metadata for a new derived cell (Memo).
///
/// # Parameters
///
/// - `id`: The unique identifier for this cell
/// - `recompute_and_check`: A closure that recomputes the memo's value and
///   returns `Ok(true)` if the value changed, `Ok(false)` if it stayed the same
///   (enabling backdating), or `Err(CycleError)` if a cycle is detected
/// - `label`: Optional human-readable name for debugging and introspection
///
/// # Returns
///
/// Initialized cell metadata with `kind = Derived` and `durability = Low`
/// (durability is updated after first computation based on dependencies)
fn CellMeta::new_derived(
  id : CellId,
  recompute_and_check : () -> Result[Bool, CycleError],
  label : String?,
) -> CellMeta {
  {
    id,
    kind: Derived,
    changed_at: Revision::initial(),
    verified_at: Revision::initial(),
    dependencies: [],
    durability: Low,
    recompute_and_check: Some(recompute_and_check),
    commit_pending: None,
    on_change: None,
    in_progress: false,
    subscribers: @hashset.new(),
    label,
  }
}
