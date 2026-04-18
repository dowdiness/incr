///|
/// Maximum number of path entries rendered by `CycleError::format_path`, and
/// the maximum number of labels snapshotted at error-construction time.
///
/// Cycles longer than this are truncated in the formatted output with "→ ..."
/// but the full cycle path is still preserved in `CycleError::path()` for
/// programmatic inspection.
pub const MAX_CYCLE_DISPLAY_STEPS : Int = 20

///|
/// Error type for cycle detection during memo computation.
///
/// A cycle occurs when a memo transitively depends on itself, creating an
/// infinite loop. This error is returned by `get_result()` methods when a
/// cycle is detected, allowing callers to handle it gracefully.
///
/// The variant carries:
///
/// - the cell that closes the cycle (the cell whose recursive access was
///   detected as already in progress),
/// - the full dependency path leading to the cycle (untruncated, suitable
///   for programmatic inspection), and
/// - a parallel labels snapshot for human-readable rendering. Labels are
///   captured at error-construction time so `format_path` is pure-value
///   and does not need a runtime handle. The labels array length equals
///   `min(path.length(), MAX_CYCLE_DISPLAY_STEPS)` — only the portion of
///   the path that will actually be rendered carries a label.
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime::new()
/// let memo_ref : Ref[Memo[Int]?] = { val: None }
/// let memo = Memo::new(rt, () => {
///   match memo_ref.val {
///     Some(m) => m.get_result().unwrap() + 1
///     None => 0
///   }
/// })
/// memo_ref.val = Some(memo)
///
/// match memo.get_result() {
///   Ok(value) => println("Got: " + value.to_string())
///   Err(err) => {
///     println("Cycle at cell " + err.cell().to_string())
///     println(err.format_path())
///   }
/// }
/// ```
pub(all) suberror CycleError {
  CycleDetected(CellId, Array[CellId], Array[String?])
}

///|
/// Returns the cell that caused the cycle.
///
/// This is the cell that was already being computed when a recursive access
/// was attempted.
pub fn CycleError::cell(self : CycleError) -> CellId {
  match self {
    CycleDetected(cell_id, _, _) => cell_id
  }
}

///|
/// Returns the full dependency path leading to the cycle.
///
/// The path shows the sequence of cells traversed from the computation entry
/// point to where the cycle was detected. The last cell in the path is the
/// same as the first cell where the cycle is detected, closing the loop.
///
/// The returned array is untruncated — callers that want to inspect long
/// cycles programmatically get the full sequence. Display rendering via
/// `format_path` truncates at `MAX_CYCLE_DISPLAY_STEPS`.
///
/// Note: The path may include cells outside the cycle itself. For example,
/// if cell A triggers computation of B→C→B, the path will be `[A, B, C, B]`
/// rather than just `[B, C, B]`, preserving the full computation context.
/// Use the repeated cell to identify the cycle boundary.
pub fn CycleError::path(self : CycleError) -> Array[CellId] {
  match self {
    CycleDetected(_, path, _) => path
  }
}

///|
/// Formats the cycle path as a human-readable string.
///
/// The output format is: "Cycle detected: Cell[N] → Cell[M] → ..." where
/// N, M, etc. are cell IDs. If a label was captured for a path entry at
/// error-construction time, the label is rendered instead of `Cell[N]`.
/// If the path exceeds `MAX_CYCLE_DISPLAY_STEPS`, output is truncated with
/// "→ ..." to keep diagnostics manageable.
///
/// Labels are snapshotted at the moment the error is constructed, so output
/// reflects the cells' labels at the time the cycle was detected — even if
/// those cells are later renamed or disposed.
///
/// # Example Output
///
/// ```
/// Cycle detected: self_ref → dep → self_ref
/// ```
pub fn CycleError::format_path(self : CycleError) -> String {
  match self {
    CycleDetected(_, path, labels) => {
      let mut result = "Cycle detected: "
      let truncated = path.length() > MAX_CYCLE_DISPLAY_STEPS
      let limit = if truncated {
        MAX_CYCLE_DISPLAY_STEPS
      } else {
        path.length()
      }
      for i in 0..<limit {
        if i > 0 {
          result = result + " → "
        }
        result = result + format_cycle_cell(path[i], labels.get(i))
      }
      if truncated {
        result = result + " → ..."
      }
      result
    }
  }
}

///|
/// Renders a single cycle-path entry using the captured label if any, else
/// falling back to `Cell[N]`. The `labels` array is parallel to the
/// displayable prefix of the path; `label_slot` is `Some(label_opt)` when the
/// entry has a snapshot slot and `None` when the entry is past the snapshot
/// cap (in which case we also fall back to `Cell[N]`).
fn format_cycle_cell(cell_id : CellId, label_slot : String??) -> String {
  match label_slot {
    Some(Some(label)) => label
    _ => "Cell[" + cell_id.id.to_string() + "]"
  }
}
