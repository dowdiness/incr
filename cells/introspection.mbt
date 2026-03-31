///|
/// Structured metadata about a cell in the dependency graph.
///
/// This structure provides a uniform view of both Signal and Memo cells.
/// For signals, the `dependencies` array will be empty.
///
/// # Fields
///
/// - `label`: Optional human-readable name for debugging and introspection
/// - `id`: The unique identifier for this cell
/// - `changed_at`: When this cell's value last actually changed
/// - `verified_at`: When this cell was last confirmed up-to-date
/// - `durability`: How often this cell is expected to change
/// - `dependencies`: Cell IDs this cell depends on (empty for signals)
pub(all) struct CellInfo {
  label : String?
  id : CellId
  changed_at : Revision
  verified_at : Revision
  durability : Durability
  dependencies : Array[CellId]
  subscribers : Array[CellId]
}

///|
/// Snapshot a HashSet[CellId] into an Array[CellId].
fn snapshot_subscribers(
  subscribers : @hashset.HashSet[CellId],
) -> Array[CellId] {
  let result : Array[CellId] = []
  for sub in subscribers {
    result.push(sub)
  }
  result
}

///|
/// Returns structured metadata for any cell (signal or memo).
///
/// This method provides uniform introspection access to cell metadata regardless of
/// whether the cell is a Signal or Memo. It returns CellInfo containing the cell's
/// ID, type, revision information, durability, and dependency list.
///
/// # Parameters
///
/// - `id`: The CellId to query (obtained via Signal::id() or Memo::id())
///
/// # Returns
///
/// - `Some(CellInfo)`: If the cell ID is valid and points to an active cell
/// - `None`: If the cell ID is out of bounds or points to an unused slot
///
/// # Usage
///
/// ```moonbit nocheck
/// let rt = Runtime()
/// let sig = Signal(rt, 42)
/// let memo = Memo(rt, () => sig.get() * 2)
/// let _ = memo.get()  // Force computation
///
/// // Query signal metadata
/// match rt.cell_info(sig.id()) {
///   Some(info) => {
///     println("Signal changed at: \{info.changed_at}")
///     println("Dependencies: \{info.dependencies.length()}")
///   }
///   None => println("Cell not found")
/// }
///
/// // Query memo metadata
/// match rt.cell_info(memo.id()) {
///   Some(info) => {
///     println("Memo durability: \{info.durability}")
///     println("Depends on \{info.dependencies.length()} cells")
///   }
///   None => println("Cell not found")
/// }
/// ```
///
/// # Notes
///
/// - The dependency array is a copy; modifying it does not affect the runtime
/// - For signals, the dependencies array is always empty
/// - For memos, dependencies are populated after the first computation
/// - The method performs bounds checking and returns None for invalid IDs
pub fn Runtime::cell_info(self : Runtime, id : CellId) -> CellInfo? {
  if !self.validate_cell_soft(id) {
    return None
  }
  let ops = self.core.cell_ops[id.id]
  match self.core.cell_index[id.id] {
    PullSignal(_) => {
      let ca = ops.changed_at()
      Some(CellInfo::{
        label: ops.label(),
        id,
        changed_at: ca,
        // Signals are always up-to-date after a set; verified_at == changed_at
        verified_at: ca,
        durability: ops.durability(),
        dependencies: [],
        subscribers: snapshot_subscribers(ops.subscribers()),
      })
    }
    PullMemo(idx) | HybridMemo(idx) => {
      let memo = self.pull.memos[idx]
      Some(CellInfo::{
        label: ops.label(),
        id,
        changed_at: ops.changed_at(),
        verified_at: memo.verified_at,
        durability: ops.durability(),
        dependencies: memo.dependencies.copy(),
        subscribers: snapshot_subscribers(ops.subscribers()),
      })
    }
    _ => None
  }
}

///|
/// Returns the cell IDs that depend on the given cell (reverse edges).
///
/// This enables introspection of the dependency graph in both directions.
/// The returned array is a snapshot; modifying it does not affect the runtime.
///
/// Returns an empty array if the cell ID is invalid, out of bounds, or
/// belongs to a different runtime — matching `cell_info` semantics.
///
/// # Parameters
///
/// - `id`: The cell to query
///
/// # Returns
///
/// Array of CellIds that have `id` in their dependency list, or empty
/// array if the cell ID is not valid for this runtime
pub fn Runtime::dependents(self : Runtime, id : CellId) -> Array[CellId] {
  if !self.validate_cell_soft(id) {
    return []
  }
  snapshot_subscribers(self.core.cell_ops[id.id].subscribers())
}

///|
/// Collects all pull memos currently marked in_progress.
///
/// Called when a cycle is detected during `pull_verify`. The in_progress
/// flags on `MemoData` entries identify the exact cycle participants.
///
/// # Returns
///
/// Array of CellIds for all pull memos with `in_progress = true`
fn Runtime::collect_in_progress_path(self : Runtime) -> Array[CellId] {
  let path : Array[CellId] = []
  for memo in self.pull.memos {
    if memo.in_progress {
      path.push(memo.meta.cell_id)
    }
  }
  path
}
