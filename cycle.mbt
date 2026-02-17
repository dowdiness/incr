///|
/// Error type for cycle detection during memo computation.
///
/// A cycle occurs when a memo transitively depends on itself, creating
/// an infinite loop. This error is returned by `get_result()` methods
/// when a cycle is detected, allowing callers to handle it gracefully.
///
/// The error contains both the cell that caused the cycle and the full
/// dependency path leading to the cycle, enabling detailed diagnostics.
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime::new()
/// let memo_ref : Ref[Memo[Int]?] = { val: None }
/// let memo = Memo::new(rt, fn() {
///   match memo_ref.val {
///     Some(m) => m.get_result().unwrap() + 1
///     None => 0
///   }
/// })
/// memo_ref.val = Some(memo)
///
/// match memo.get_result() {
///   Ok(value) => println("Got: " + value.to_string())
///   Err(CycleDetected(cell, path)) => {
///     println("Cycle at cell " + cell.to_string())
///     println("Path length: " + path.length().to_string())
///   }
/// }
/// ```
pub suberror CycleError {
  CycleDetected(CellId, Array[CellId])
}

///|
/// Returns the cell that caused the cycle.
///
/// This is the cell that was already being computed when
/// a recursive access was attempted.
pub fn CycleError::cell(self : CycleError) -> CellId {
  match self {
    CycleDetected(cell_id, _) => cell_id
  }
}

///|
/// Returns the dependency path leading to the cycle.
///
/// The path shows the sequence of cells traversed from the computation
/// entry point to where the cycle was detected. The last cell in the
/// path is the same as the first cell where the cycle is detected,
/// closing the loop.
///
/// Note: The path may include cells outside the cycle itself. For example,
/// if cell A triggers computation of B→C→B, the path will be `[A, B, C, B]`
/// rather than just `[B, C, B]`, preserving the full computation context.
/// Use the repeated cell to identify the cycle boundary.
pub fn CycleError::path(self : CycleError) -> Array[CellId] {
  match self {
    CycleDetected(_, path) => path
  }
}

///|
/// Formats the cycle path as a human-readable string.
///
/// The output format is: "Cycle detected: Cell[N] → Cell[M] → ..."
/// where N, M, etc. are cell IDs. If the path exceeds 20 cells, it is
/// truncated with "..." to keep the output manageable.
///
/// # Parameters
///
/// - `rt`: The runtime that owns these cells (needed for cell info lookup)
///
/// # Example Output
///
/// ```
/// Cycle detected: Cell[0] → Cell[1] → Cell[0]
/// ```
pub fn CycleError::format_path(self : CycleError, rt : Runtime) -> String {
  match self {
    CycleDetected(_, path) => {
      let mut result = "Cycle detected: "
      let max_cells = 20
      let truncated = path.length() > max_cells
      let limit = if truncated { max_cells } else { path.length() }

      for i = 0; i < limit; i = i + 1 {
        if i > 0 {
          result = result + " → "
        }
        result = result + format_cell(rt, path[i])
      }

      if truncated {
        result = result + " → ..."
      }

      result
    }
  }
}

///|
/// Helper function to format a single cell ID.
///
/// Returns "Cell[N]" where N is the cell's ID number.
///
/// The `rt` parameter is currently unused (hence the underscore prefix),
/// but is threaded through for future use — e.g., calling `rt.cell_info()`
/// to display richer metadata like cell type or durability level.
fn format_cell(_rt : Runtime, cell_id : CellId) -> String {
  "Cell[" + cell_id.id.to_string() + "]"
}
