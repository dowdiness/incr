///|
/// Error type for cycle detection during memo computation.
///
/// A cycle occurs when a memo transitively depends on itself, creating
/// an infinite loop. This error is returned by `get_result()` methods
/// when a cycle is detected, allowing callers to handle it gracefully.
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
///   Err(CycleDetected(id)) => println("Cycle at cell " + id.to_string())
/// }
/// ```
pub suberror CycleError {
  CycleDetected(Int)
}

///|
/// Returns the cell ID that caused the cycle.
///
/// This is the ID of the cell that was already being computed when
/// a recursive access was attempted.
pub fn CycleError::cell_id(self : CycleError) -> Int {
  match self {
    CycleDetected(id) => id
  }
}
