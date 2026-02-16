// =============================================================================
// Tests for verification path tracking (Task 2)
// =============================================================================
//
// These tests verify that the verification algorithm (maybe_changed_after)
// properly tracks the dependency path during traversal, so that CycleError
// includes the full chain of cells that led to the cycle.

///|
test "verify: cycle path includes all traversed cells" {
  // Spec requirement: verify that cycle path includes all traversed cells
  // in a multi-cell cycle (not just the repeating cell).
  //
  // Setup: B→C→B cycle (B depends on C, C depends on B)
  // When b.get_result() is called, verification walks B→C→B,
  // and the path should contain both B and C cell IDs.
  let rt = Runtime::new()
  let b_ref : Ref[Memo[Int]?] = { val: None }
  let c_ref : Ref[Memo[Int]?] = { val: None }
  let captured_path : Ref[Array[CellId]?] = { val: None }

  // Create memo B that depends on C
  let b = Memo::new(rt, fn() {
    match c_ref.val {
      Some(c) =>
        match c.get_result() {
          Ok(v) => v + 1
          Err(err) => {
            captured_path.val = Some(err.path())
            -999
          }
        }
      None => 0
    }
  })
  b_ref.val = Some(b)

  // Create memo C that depends on B (creating the cycle)
  let c = Memo::new(rt, fn() {
    match b_ref.val {
      Some(b_cell) =>
        match b_cell.get_result() {
          Ok(v) => v + 2
          Err(err) => {
            captured_path.val = Some(err.path())
            -999
          }
        }
      None => 0
    }
  })
  c_ref.val = Some(c)

  // Trigger the cycle by accessing b
  let _ = b.get()

  match captured_path.val {
    Some(path) => {
      // For B→C→B cycle: path should be [B, C, B]
      // Length is 3 (includes the closing cell)
      inspect(path.length(), content="3")
      let b_id = b.id()
      let c_id = c.id()
      // Verify exact path: B, C, B
      inspect(path[0] == b_id, content="true")
      inspect(path[1] == c_id, content="true")
      inspect(path[2] == b_id, content="true")
    }
    None => fail("Expected cycle path to be captured")
  }
}

///|
test "verify: self-cycle path shows cell twice" {
  // Setup: M→M self-cycle
  // When verifying M, it checks itself (cycle!)
  // Expected path: [M, M] showing the self-reference
  let rt = Runtime::new()
  let trigger = Signal::new(rt, 0)

  let memo_ref : Ref[Memo[Int]?] = { val: None }

  // M depends on itself (when trigger > 0)
  let memo = Memo::new(rt, fn() {
    if trigger.get() > 0 {
      match memo_ref.val {
        Some(m) =>
          match m.get_result() {
            Ok(v) => v + 1
            Err(_) => -999
          }
        None => 0
      }
    } else {
      42
    }
  })

  memo_ref.val = Some(memo)

  // First access: no cycle (trigger = 0)
  let _ = memo.get()

  // Change trigger to create self-cycle
  trigger.set(1)

  // Now accessing M will trigger verification:
  // Verify M -> Check M -> CYCLE!
  // Expected path: [M, M]
  let captured_path : Ref[Array[CellId]?] = { val: None }
  let memo_instrumented = Memo::new(rt, fn() {
    if trigger.get() > 0 {
      match memo_ref.val {
        Some(m) =>
          match m.get_result() {
            Ok(v) => v + 1
            Err(err) => {
              captured_path.val = Some(err.path())
              -999
            }
          }
        None => 0
      }
    } else {
      42
    }
  })
  memo_ref.val = Some(memo_instrumented)

  let _ = memo_instrumented.get()

  match captured_path.val {
    Some(path) => {
      // Path should be: [M_instrumented, M_instrumented]
      inspect(path.length(), content="2")
      inspect(path[0] == memo_instrumented.id(), content="true")
      inspect(path[1] == memo_instrumented.id(), content="true")
    }
    None => fail("Expected cycle path to be captured")
  }
}
