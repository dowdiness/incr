///|
using @incr_types {type CellId}

// =============================================================================
// Comprehensive Cycle Path Tests (Task 4)
// =============================================================================
//
// These tests verify various cycle scenarios including simple cycles,
// self-cycles, format_path output, and long cycle truncation.

///|
test "cycle path: simple two-cell cycle" {
  let rt = Runtime::Runtime()
  let a = Signal::Signal(rt, 0)

  let b_ref : Ref[Derived[Int]?] = { val: None }
  let c_ref : Ref[Derived[Int]?] = { val: None }
  let captured_path : Ref[Array[CellId]?] = { val: None }

  let b = Derived::Derived(rt, () => {
    match c_ref.val {
      Some(c) =>
        match c.read() {
          Ok(v) => a.get() + v
          Err(@incr_types.ReadError::Cycle(err)) => {
            captured_path.val = Some(err.path())
            -999
          }
          Err(_) => abort("unexpected error in cycle test")
        }
      None => 0
    }
  })

  let c = Derived::Derived(rt, () => {
    match b_ref.val {
      Some(b_val) =>
        match b_val.read() {
          Ok(v) => v * 2
          Err(err) => {
            captured_path.val = Some(err.path())
            -999
          }
        }
      None => 0
    }
  })

  b_ref.val = Some(b)
  c_ref.val = Some(c)

  // Trigger the cycle
  let _ = b.read_or_abort()

  match captured_path.val {
    Some(path) => {
      inspect(path.length(), content="3") // B, C, B closing the cycle
      inspect(path[0] == b.id(), content="true")
      inspect(path[1] == c.id(), content="true")
      inspect(path[2] == b.id(), content="true")
    }
    None => fail("Expected cycle path to be captured")
  }
}

///|
test "cycle path: format_path produces readable output" {
  let rt = Runtime::Runtime()
  let self_ref : Ref[Derived[Int]?] = { val: None }
  let captured_formatted : Ref[String] = { val: "" }

  let d = Derived::Derived(rt, () => {
    match self_ref.val {
      Some(d_cell) =>
        match d_cell.read() {
          Ok(v) => v + 1
          Err(@incr_types.ReadError::Cycle(err)) => {
            captured_formatted.val = err.format_path()
            -999
          }
          Err(_) => abort("unexpected error in cycle test")
        }
      None => 0
    }
  })
  self_ref.val = Some(d)

  // Trigger the cycle
  let _ = d.read_or_abort()

  // Verify format
  let formatted = captured_formatted.val
  inspect(formatted.contains("Cycle"), content="true")
  inspect(formatted.contains(" → "), content="true")
  inspect(formatted.contains("Cell["), content="true")
}

///|
test "cycle path: long cycle is truncated" {
  let rt = Runtime::Runtime()
  let captured_path : Ref[Array[CellId]?] = { val: None }
  let captured_formatted : Ref[String] = { val: "" }

  // Create a cycle: memo[0]→memo[24]→...→memo[1]→memo[0]
  let memos : Array[Derived[Int]] = []
  let memos_ref : Ref[Array[Derived[Int]]?] = { val: None }

  for i = 0; i < 25; i = i + 1 {
    let idx = i
    let memo = if i == 0 {
      Derived::Derived(rt, () => {
        match memos_ref.val {
          Some(ms) =>
            match ms[24].read() {
              Ok(v) => v
              Err(@incr_types.ReadError::Cycle(err)) => {
                captured_path.val = Some(err.path())
                captured_formatted.val = err.format_path()
                -999
              }
              Err(_) => abort("unexpected error in cycle test")
            }
          None => 0
        }
      })
    } else {
      Derived::Derived(rt, () => {
        match memos_ref.val {
          Some(ms) =>
            match ms[idx - 1].read() {
              Ok(v) => v + 1
              Err(@incr_types.ReadError::Cycle(err)) => {
                captured_path.val = Some(err.path())
                captured_formatted.val = err.format_path()
                -999
              }
              Err(_) => abort("unexpected error in cycle test")
            }
          None => 0
        }
      })
    }
    memos.push(memo)
  }

  memos_ref.val = Some(memos)

  // Trigger the cycle from the first memo
  let _ = memos[0].read_or_abort()

  // Should contain truncation message since path will be > 20 cells
  match captured_path.val {
    Some(path) => {
      inspect(path.length() > 20, content="true")
      let formatted = captured_formatted.val
      inspect(
        formatted.contains("...") || formatted.contains("more"),
        content="true",
      )
    }
    None => fail("Expected cycle path to be captured")
  }
}

///|
test "format_path uses label when available" {
  let rt = Runtime::Runtime()
  let d_ref : Ref[Derived[Int]?] = { val: None }
  let captured_formatted : Ref[String] = { val: "" }

  let d = Derived::Derived(
    rt,
    () => {
      match d_ref.val {
        Some(m) =>
          match m.read() {
            Ok(v) => v + 1
            Err(err) => {
              captured_formatted.val = err.format_path()
              -999
            }
          }
        None => 0
      }
    },
    label="self_ref",
  )
  d_ref.val = Some(d)

  // Trigger the cycle
  let _ = d.read_or_abort()
  let msg = captured_formatted.val
  inspect(msg.contains("self_ref"), content="true")
}
