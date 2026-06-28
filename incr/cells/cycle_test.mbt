// =============================================================================
// Tests for get_result() returning CycleError
// =============================================================================

// Note: When a cycle occurs during computation (inside the compute function),
// the error can only be caught if the compute function uses get_result() and
// handles the error. If the compute function calls get() or re-throws the error,
// it will abort. To test error propagation through get_result(), we must either:
// 1. Handle the error in compute and return a sentinel (shows Ok with sentinel)
// 2. Use a panic test (shows abort behavior)
//
// The key use case for get_result() is detecting cycles during VERIFICATION
// (maybe_changed_after phase), not during initial computation.

///|
test "get_result with handled inner errors returns sentinel value" {
  // This demonstrates the primary use case: compute functions can handle
  // cycle errors gracefully by returning sentinel values
  let rt = Runtime::Runtime()
  let d_ref : Ref[Derived[Int]?] = { val: None }
  let d = Derived::Derived(rt, () => {
    match d_ref.val {
      Some(m) =>
        // Handle the error by returning a sentinel value
        match m.read() {
          Ok(v) => v + 1
          Err(@incr_types.ReadError::Cycle(_)) => -999 // Sentinel value for cycle
          Err(_) => abort("unexpected read error")
        }
      None => 0
    }
  })
  d_ref.val = Some(d)
  // Since the error is handled inside, outer call returns Ok with sentinel
  inspect(d.read_or_abort(), content="-999")
}

///|
test "get_result with handled errors in mutual recursion (2-way)" {
  let rt = Runtime::Runtime()
  let d_b_ref : Ref[Derived[Int]?] = { val: None }
  let d_a : Derived[Int] = Derived::Derived(rt, () => {
    match d_b_ref.val {
      Some(b) =>
        match b.read() {
          Ok(v) => v + 1
          Err(@incr_types.ReadError::Cycle(_)) => -1000 // Cycle sentinel for memo_a
          Err(_) => abort("unexpected read error")
        }
      None => 0
    }
  })
  let d_b = Derived::Derived(rt, () => {
    match d_a.read() {
      Ok(v) => v + 1
      Err(@incr_types.ReadError::Cycle(_)) => -2000 // Cycle sentinel for memo_b
      Err(_) => abort("unexpected read error")
    }
  })
  d_b_ref.val = Some(d_b)
  // memo_a calls memo_b which calls memo_a (cycle detected)
  // memo_a's inner get_result returns Err, so memo_a returns -2000
  // memo_b receives Ok(-2000), adds 1, returns -1999
  // memo_a receives Ok(-1999), adds 1, returns -1998... wait no
  //
  // Actually: memo_a computes -> calls b.get_result() -> memo_b computes
  // -> calls memo_a.get_result() -> Err(cycle) -> returns -2000
  // -> memo_b returns Ok(-2000) to memo_a -> memo_a does -2000 + 1 = -1999
  inspect(d_a.read_or_abort(), content="-1999")
}

///|
test "get_result with handled errors in mutual recursion (3-way)" {
  let rt = Runtime::Runtime()
  let d_b_ref : Ref[Derived[Int]?] = { val: None }
  let d_c_ref : Ref[Derived[Int]?] = { val: None }
  let d_a : Derived[Int] = Derived::Derived(rt, () => {
    match d_b_ref.val {
      Some(b) =>
        match b.read() {
          Ok(v) => v + 1
          Err(@incr_types.ReadError::Cycle(_)) => -1
          Err(_) => abort("unexpected read error")
        }
      None => 0
    }
  })
  let d_b : Derived[Int] = Derived::Derived(rt, () => {
    match d_c_ref.val {
      Some(c) =>
        match c.read() {
          Ok(v) => v + 1
          Err(@incr_types.ReadError::Cycle(_)) => -2
          Err(_) => abort("unexpected read error")
        }
      None => 0
    }
  })
  let d_c = Derived::Derived(rt, () => {
    match d_a.read() {
      Ok(v) => v + 1
      Err(@incr_types.ReadError::Cycle(_)) => -3 // This is hit when cycle detected
      Err(_) => abort("unexpected read error")
    }
  })
  d_b_ref.val = Some(d_b)
  d_c_ref.val = Some(d_c)
  // memo_a -> memo_b -> memo_c -> memo_a (cycle!)
  // memo_c gets Err, returns -3
  // memo_b gets Ok(-3), returns -3 + 1 = -2
  // memo_a gets Ok(-2), returns -2 + 1 = -1
  inspect(d_a.read_or_abort(), content="-1")
}

///|
test "get_result returns Ok for non-cyclic memos" {
  let rt = Runtime::Runtime()
  let a = Input::Input(rt, 10)
  let b = Input::Input(rt, 20)
  let sum = Derived::Derived(rt, () => a.get() + b.get())
  let double_sum = Derived::Derived(rt, () => sum.get_or_abort() * 2)
  // Non-cyclic memos should return Ok
  inspect(sum.read_or_abort(), content="30")
  inspect(double_sum.read_or_abort(), content="60")
}

///|
test "Input::get_result always returns Ok" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  match sig.get_result() {
    Ok(v) => inspect(v, content="42")
    Err(_) => fail("Input::get_result should never fail")
  }
  sig.set(100)
  match sig.get_result() {
    Ok(v) => inspect(v, content="100")
    Err(_) => fail("Input::get_result should never fail")
  }
}

///|
test "CycleError::cell_id returns correct cell ID (backward compatibility)" {
  // This test verifies backward compatibility - we can still access the cell ID
  // via the new cell() method which returns a CellId
  let rt = Runtime::Runtime()
  let d_ref : Ref[Derived[Int]?] = { val: None }
  let captured_id : Ref[Int] = { val: -1 }
  let d = Derived::Derived(rt, () => {
    match d_ref.val {
      Some(m) =>
        match m.read() {
          Ok(v) => v + 1
          Err(err) => {
            captured_id.val = err.cell().id
            -999
          }
        }
      None => 0
    }
  })
  d_ref.val = Some(d)
  let _ = d.read_or_abort()
  // The captured cell_id should be 0 (first memo created)
  inspect(captured_id.val, content="0")
}

// =============================================================================
// Enhanced Cycle Error Diagnostics Tests (Phase 2A)
// =============================================================================

///|
test "CycleError::cell() returns the cycle-causing cell ID" {
  let rt = Runtime::Runtime()
  let d_ref : Ref[Derived[Int]?] = { val: None }
  let captured_cell : Ref[CellId?] = { val: None }
  let d = Derived::Derived(rt, () => {
    match d_ref.val {
      Some(m) =>
        match m.read() {
          Ok(v) => v + 1
          Err(err) => {
            captured_cell.val = Some(err.cell())
            -999
          }
        }
      None => 0
    }
  })
  d_ref.val = Some(d)
  let _ = d.read_or_abort()
  // Verify captured cell matches memo's ID
  match captured_cell.val {
    Some(cell_id) => inspect(cell_id == d.id(), content="true")
    None => fail("Expected cycle error to be captured")
  }
}

///|
test "CycleError::path() returns the full dependency cycle" {
  let rt = Runtime::Runtime()
  let d_ref : Ref[Derived[Int]?] = { val: None }
  let captured_path : Ref[Array[CellId]?] = { val: None }
  let d = Derived::Derived(rt, () => {
    match d_ref.val {
      Some(m) =>
        match m.read() {
          Ok(v) => v + 1
          Err(err) => {
            captured_path.val = Some(err.path())
            -999
          }
        }
      None => 0
    }
  })
  d_ref.val = Some(d)
  let _ = d.read_or_abort()
  // Note: Path tracking is now implemented (Task 2)
  // Path is populated with the cycle information
  match captured_path.val {
    Some(path) =>
      // Path is populated by Task 2
      inspect(path.length() == 2, content="true")
    None => fail("Expected cycle path to be captured")
  }
}

///|
test "CycleError::format_path() produces readable output" {
  let rt = Runtime::Runtime()
  let d_ref : Ref[Derived[Int]?] = { val: None }
  let captured_message : Ref[String] = { val: "" }
  let d = Derived::Derived(rt, () => {
    match d_ref.val {
      Some(m) =>
        match m.read() {
          Ok(v) => v + 1
          Err(err) => {
            captured_message.val = err.format_path()
            -999
          }
        }
      None => 0
    }
  })
  d_ref.val = Some(d)
  let _ = d.read_or_abort()
  inspect(captured_message.val.contains("Cycle detected:"), content="true")
  inspect(captured_message.val.contains(" → "), content="true")
}

///|
test "CycleError::format_path() returns non-empty string for self-referencing memo" {
  let rt = Runtime::Runtime()
  let captured_message : Ref[String] = { val: "" }
  let d_ref : Ref[Derived[Int]?] = { val: None }
  let d = Derived::Derived(rt, () => {
    match d_ref.val {
      Some(m) =>
        match m.read() {
          Ok(v) => v + 1
          Err(err) => {
            captured_message.val = err.format_path()
            -999
          }
        }
      None => 0
    }
  })
  d_ref.val = Some(d)
  let _ = d.read_or_abort()
  inspect(captured_message.val.contains("Cycle detected:"), content="true")
  inspect(captured_message.val.contains(" → "), content="true")
}

///|
test "state is cleaned up after cycle error with handled errors" {
  let rt = Runtime::Runtime()
  let d_ref : Ref[Derived[Int]?] = { val: None }
  let d = Derived::Derived(rt, () => {
    match d_ref.val {
      Some(m) =>
        match m.read() {
          Ok(v) => v + 1
          Err(@incr_types.ReadError::Cycle(_)) => -999
          Err(_) => abort("unexpected read error")
        }
      None => 0
    }
  })
  d_ref.val = Some(d)
  // First call triggers cycle (but handles it with sentinel)
  inspect(d.read_or_abort(), content="-999")
  // Create a non-cyclic memo to verify runtime is still functional
  let sig = Input::Input(rt, 5)
  let good_d = Derived::Derived(rt, () => sig.get() * 2)
  inspect(good_d.read_or_abort(), content="10")
}

///|
test "cycle error during reverification returns error through get_result" {
  let rt = Runtime::Runtime()
  let trigger = Input::Input(rt, 0)
  let d_ref : Ref[Derived[Int]?] = { val: None }
  // This memo only creates a cycle when trigger > 0
  let d = Derived::Derived(rt, () => {
    if trigger.get() > 0 {
      match d_ref.val {
        Some(m) =>
          match m.read() {
            Ok(v) => v + 1
            Err(@incr_types.ReadError::Cycle(_)) => -888
            Err(_) => abort("unexpected error in cycle test")
          }
        None => 0
      }
    } else {
      42
    }
  })
  d_ref.val = Some(d)
  // First call succeeds (no cycle when trigger = 0)
  inspect(d.read_or_abort(), content="42")
  // Change trigger to create cycle on next access
  trigger.set(1)
  // Now reverification detects cycle but handles it with sentinel
  inspect(d.read_or_abort(), content="-888")
}

///|
test "failed get_result does not create spurious dependency edges" {
  // This test verifies that when get_result() fails with a cycle error,
  // no dependency is recorded. Without this fix, the self-referential memo
  // would have itself as a dependency, causing subsequent revision bumps
  // to falsely detect a cycle during verification.
  let rt = Runtime::Runtime()
  let external = Input::Input(rt, 100)
  let d_ref : Ref[Derived[Int]?] = { val: None }
  let cycle_count : Ref[Int] = { val: 0 }
  let d = Derived::Derived(rt, () => {
    // Include external dependency so we can trigger recomputation
    let base = external.get()
    match d_ref.val {
      Some(m) =>
        match m.read() {
          Ok(v) => v + 1
          Err(@incr_types.ReadError::Cycle(_)) => {
            cycle_count.val = cycle_count.val + 1
            base + cycle_count.val
          }
          Err(_) => abort("unexpected error in cycle test")
        }
      None => base
    }
  })
  d_ref.val = Some(d)

  // First access: cycle detected, handled with sentinel (100 + 1 = 101)
  inspect(d.read_or_abort(), content="101")

  // Bump external input to force reverification
  external.set(200)

  // Second access after revision bump: should recompute cleanly.
  // If the failed self-reference was recorded as a dependency, this would
  // fail with a spurious cycle error instead of recomputing.
  inspect(d.read_or_abort(), content="202") // 200 + 2 (second cycle detection)

  // Third access should use cached value (no new cycle detection)
  inspect(d.read_or_abort(), content="202") // Same cached value
  // Verify cycle count is still 2 (no new cycle detected on cached access)
  inspect(cycle_count.val, content="2")
}

// =============================================================================
// Backward compatibility: panic tests for get() method
// =============================================================================

///|
test "panic cycle on initial get: direct self-referencing memo aborts" {
  let rt = Runtime::Runtime()
  // Create a memo that references itself — this creates a cycle
  let d_ref : Ref[Derived[Int]?] = { val: None }
  let d = Derived::Derived(rt, () => {
    match d_ref.val {
      Some(m) => m.get_or_abort() + 1
      None => 0
    }
  })
  d_ref.val = Some(d)
  // First get() enters force_recompute(), then re-enters force_recompute() via m.get().
  // The second entry must abort with cycle detection rather than recurse indefinitely.
  let _ = d.read_or_abort()
}

///|
test "panic cycle on initial get: mutual recursion between two memos aborts" {
  let rt = Runtime::Runtime()
  let d_b_ref : Ref[Derived[Int]?] = { val: None }
  let d_a : Derived[Int] = Derived::Derived(rt, () => {
    match d_b_ref.val {
      Some(b) => b.get_or_abort() + 1
      None => 0
    }
  })
  let d_b = Derived::Derived(rt, () => d_a.get_or_abort() + 1)
  d_b_ref.val = Some(d_b)
  // First get() of memo_a reaches memo_b.get(), which re-enters memo_a.get().
  // This must abort immediately via the in-progress recompute guard.
  let _ = d_a.read_or_abort()
}
