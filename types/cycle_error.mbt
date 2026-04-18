///|
/// Maximum number of path entries rendered by `CycleError::format_path`, and
/// the number of labels snapshotted at error-construction time.
///
/// Cycles longer than this are truncated in the formatted output with "→ ...",
/// but `CycleError::path()` still returns the full untruncated sequence.
pub const MAX_CYCLE_DISPLAY_STEPS : Int = 20

///|
/// Error type for cycle detection during memo computation.
///
/// Returned by `get_result()` methods when a memo transitively depends on
/// itself. Use `cell()`, `path()`, and `format_path()` to inspect or render
/// the cycle. Labels are snapshotted at construction time so `format_path`
/// is pure-value — rendering needs no runtime handle and reflects the cell
/// labels at the moment the cycle was detected, even if those cells are
/// later renamed or disposed.
///
/// # Example
///
/// ```moonbit nocheck
/// match memo.get_result() {
///   Ok(value) => println("Got: " + value.to_string())
///   Err(err) => {
///     println("Cycle at cell " + err.cell().to_string())
///     println(err.format_path())
///   }
/// }
/// ```
pub suberror CycleError {
  CycleDetected(CellId, Array[CellId], Array[String?])
}

///|
/// Construct a `CycleError` from its parts. Exposed so packages that detect
/// cycles (and have access to a runtime for label lookup) can build the
/// error without depending on variant-constructor visibility.
///
/// Invariant: `labels.length() == min(path.length(), MAX_CYCLE_DISPLAY_STEPS)`.
/// The caller must uphold this — `format_path` assumes `path[i]` has a
/// matching `labels[i]` for every `i` it renders.
pub fn CycleError::new(
  cell : CellId,
  path : Array[CellId],
  labels : Array[String?],
) -> CycleError {
  CycleDetected(cell, path, labels)
}

///|
pub fn CycleError::cell(self : CycleError) -> CellId {
  match self {
    CycleDetected(cell_id, _, _) => cell_id
  }
}

///|
/// Full dependency path leading to the cycle, untruncated. The path may
/// include cells outside the cycle itself (e.g., entry points). Use the
/// repeated cell to identify the cycle boundary.
pub fn CycleError::path(self : CycleError) -> Array[CellId] {
  match self {
    CycleDetected(_, path, _) => path
  }
}

///|
/// Formats the cycle path as a human-readable string, using captured labels
/// when available and falling back to `Cell[N]` otherwise. Output longer
/// than `MAX_CYCLE_DISPLAY_STEPS` entries is truncated with "→ ...".
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
        result = result +
          (match labels[i] {
            Some(label) => label
            None => "Cell[" + path[i].id.to_string() + "]"
          })
      }
      if truncated {
        result = result + " → ..."
      }
      result
    }
  }
}
