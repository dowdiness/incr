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
  let rt = Runtime::new()
  let a = Signal::new(rt, 0)

  let b_ref : Ref[Memo[Int]?] = { val: None }
  let c_ref : Ref[Memo[Int]?] = { val: None }
  let captured_path : Ref[Array[CellId]?] = { val: None }

  let b = Memo::new(rt, () => {
    match c_ref.val {
      Some(c) =>
        match c.get_result() {
          Ok(v) => a.get() + v
          Err(err) => {
            captured_path.val = Some(err.path())
            -999
          }
        }
      None => 0
    }
  })

  let c = Memo::new(rt, () => {
    match b_ref.val {
      Some(b_val) =>
        match b_val.get_result() {
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
  let _ = b.get()

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
  let rt = Runtime::new()
  let self_ref : Ref[Memo[Int]?] = { val: None }
  let captured_formatted : Ref[String] = { val: "" }

  let m = Memo::new(rt, () => {
    match self_ref.val {
      Some(memo) =>
        match memo.get_result() {
          Ok(v) => v + 1
          Err(err) => {
            captured_formatted.val = err.format_path(rt)
            -999
          }
        }
      None => 0
    }
  })
  self_ref.val = Some(m)

  // Trigger the cycle
  let _ = m.get()

  // Verify format
  let formatted = captured_formatted.val
  inspect(formatted.contains("Cycle"), content="true")
  inspect(formatted.contains(" → "), content="true")
  inspect(formatted.contains("Cell["), content="true")
}

///|
test "cycle path: long cycle is truncated" {
  let rt = Runtime::new()
  let captured_path : Ref[Array[CellId]?] = { val: None }
  let captured_formatted : Ref[String] = { val: "" }

  // Create a cycle: memo[0]→memo[24]→...→memo[1]→memo[0]
  let memos : Array[Memo[Int]] = []
  let memos_ref : Ref[Array[Memo[Int]]?] = { val: None }

  for i = 0; i < 25; i = i + 1 {
    let idx = i
    let memo = if i == 0 {
      Memo::new(rt, () => {
        match memos_ref.val {
          Some(ms) =>
            match ms[24].get_result() {
              Ok(v) => v
              Err(err) => {
                captured_path.val = Some(err.path())
                captured_formatted.val = err.format_path(rt)
                -999
              }
            }
          None => 0
        }
      })
    } else {
      Memo::new(rt, () => {
        match memos_ref.val {
          Some(ms) =>
            match ms[idx - 1].get_result() {
              Ok(v) => v + 1
              Err(err) => {
                captured_path.val = Some(err.path())
                captured_formatted.val = err.format_path(rt)
                -999
              }
            }
          None => 0
        }
      })
    }
    memos.push(memo)
  }

  memos_ref.val = Some(memos)

  // Trigger the cycle from the first memo
  let _ = memos[0].get()

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
  let rt = Runtime::new()
  let memo_ref : Ref[Memo[Int]?] = { val: None }
  let captured_formatted : Ref[String] = { val: "" }

  let memo = Memo::new(
    rt,
    () => {
      match memo_ref.val {
        Some(m) =>
          match m.get_result() {
            Ok(v) => v + 1
            Err(err) => {
              captured_formatted.val = err.format_path(rt)
              -999
            }
          }
        None => 0
      }
    },
    label="self_ref",
  )
  memo_ref.val = Some(memo)

  // Trigger the cycle
  let _ = memo.get()
  let msg = captured_formatted.val
  inspect(msg.contains("self_ref"), content="true")
}
