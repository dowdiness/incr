# Enhanced Cycle Error Diagnostics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enhance CycleError to include the full dependency path, enabling human-readable error messages that show how cycles form.

**Architecture:** Modify CycleError enum to store cycle path array, add helper methods for path access and formatting, update verification algorithm to track path during traversal, update all existing code to use new pattern.

**Tech Stack:** MoonBit, existing incr library codebase

---

## Task 1: Update CycleError Structure and Add Helper Methods

**Files:**
- Modify: `cycle.mbt:26-39`

**Step 1: Write failing tests for new CycleError API**

Create: `cycle_test.mbt`

```moonbit
///|
test "cycle error: cell() returns the detected cell ID" {
  let rt = Runtime::new()
  let cell_id = CellId::{ runtime_id: 0, id: 5 }
  let path = [cell_id]
  let err = CycleDetected(cell_id, path)

  inspect(err.cell() == cell_id, content="true")
}

///|
test "cycle error: path() returns the full cycle path" {
  let rt = Runtime::new()
  let id1 = CellId::{ runtime_id: 0, id: 1 }
  let id2 = CellId::{ runtime_id: 0, id: 2 }
  let path = [id1, id2, id1]
  let err = CycleDetected(id1, path)

  inspect(err.path().length(), content="3")
  inspect(err.path()[0] == id1, content="true")
  inspect(err.path()[1] == id2, content="true")
  inspect(err.path()[2] == id1, content="true")
}

///|
test "cycle error: format_path() produces readable output" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 100)
  let path = [sig.id()]
  let err = CycleDetected(sig.id(), path)

  let formatted = err.format_path(rt)
  inspect(formatted.contains("Cycle"), content="true")
  inspect(formatted.contains("→") || formatted.contains("->"), content="true")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr -f cycle_test.mbt`
Expected: FAIL - CycleDetected constructor and methods don't exist with new signature

**Step 3: Update CycleError enum and add methods**

Modify `cycle.mbt`:

```moonbit
///|
/// Error type for cycle detection during memo computation.
///
/// A cycle occurs when a memo transitively depends on itself, creating
/// an infinite loop. This error is returned by `get_result()` methods
/// when a cycle is detected, allowing callers to handle it gracefully.
///
/// The cycle path shows the full dependency chain that led to the cycle,
/// enabling detailed debugging.
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
///   Err(CycleDetected(cell, path)) => {
///     println("Cycle at " + cell.to_string())
///     println("Path: " + err.format_path(rt))
///   }
/// }
/// ```
pub suberror CycleError {
  CycleDetected(CellId, Array[CellId])
  //             ^cell   ^cycle path from root to cycle point
}

///|
/// Returns the CellId where the cycle was detected.
///
/// This is the cell that was already being computed when
/// a recursive access was attempted.
pub fn CycleError::cell(self : CycleError) -> CellId {
  match self {
    CycleDetected(cell, _) => cell
  }
}

///|
/// Returns the full dependency path leading to the cycle.
///
/// The path shows the sequence of cells traversed from the root
/// to the point where the cycle was detected.
pub fn CycleError::path(self : CycleError) -> Array[CellId] {
  match self {
    CycleDetected(_, path) => path
  }
}

///|
/// Formats the cycle path as a human-readable string.
///
/// Uses Runtime::cell_info() to get cell metadata for better output.
/// Shows arrows between cells to indicate dependency flow.
///
/// # Example Output
///
/// ```
/// "Cycle detected: Signal[0] → Memo[1] → Memo[2] → Memo[1]"
/// ```
pub fn CycleError::format_path(self : CycleError, rt : Runtime) -> String {
  match self {
    CycleDetected(_, path) => {
      if path.length() == 0 {
        return "Cycle detected (empty path)"
      }

      // For long cycles, truncate the middle
      let should_truncate = path.length() > 20
      let parts : Array[String] = []

      if should_truncate {
        // Show first 5, truncation message, last 5
        for i = 0; i < 5; i = i + 1 {
          parts.push(format_cell(rt, path[i]))
        }
        let omitted = path.length() - 10
        parts.push("... (" + omitted.to_string() + " more)")
        for i = path.length() - 5; i < path.length(); i = i + 1 {
          parts.push(format_cell(rt, path[i]))
        }
      } else {
        for i = 0; i < path.length(); i = i + 1 {
          parts.push(format_cell(rt, path[i]))
        }
      }

      "Cycle detected: " + parts.join(" → ")
    }
  }
}

///|
/// Helper function to format a single cell for display.
///
/// Returns "Cell[id]" or "Cell[?]" if cell_info returns None.
fn format_cell(rt : Runtime, cell_id : CellId) -> String {
  match rt.cell_info(cell_id) {
    Some(_info) => {
      // Simple format: Cell[id]
      // Future: could add metadata like "Signal[0](High)" or "Memo[1]"
      "Cell[" + cell_id.id.to_string() + "]"
    }
    None => "Cell[?]"
  }
}
```

Note: Remove the old `cell_id()` method that returned Int.

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr -f cycle_test.mbt`
Expected: PASS (3 tests)

**Step 5: Commit**

```bash
git add cycle.mbt cycle_test.mbt
git commit -m "feat: add cycle path to CycleError

BREAKING CHANGE: CycleError now uses CycleDetected(CellId, Array[CellId])
instead of CycleDetected(Int). Add cell(), path(), and format_path() methods.
"
```

---

## Task 2: Update Verification Algorithm to Track Path

**Files:**
- Modify: `verify.mbt:143-250` (maybe_changed_after function)
- Modify: `memo.mbt:167-210` (force_recompute function)

**Step 1: Write failing test for path tracking**

Create: `verify_path_test.mbt`

```moonbit
///|
test "verify: cycle path includes all traversed cells" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 0)

  // Create B depends on C
  let c_ref : Ref[Memo[Int]?] = { val: None }
  let b = Memo::new(rt, () => {
    match c_ref.val {
      Some(c) => a.get() + c.get()
      None => 0
    }
  })

  // Create C depends on B (cycle: B → C → B)
  let c = Memo::new(rt, () => b.get() * 2)
  c_ref.val = Some(c)

  // Trigger computation
  match b.get_result() {
    Err(CycleDetected(cell, path)) => {
      // Path should contain both B and C
      inspect(path.length() >= 2, content="true")
      inspect(path.contains(b.id()), content="true")
      inspect(path.contains(c.id()), content="true")
    }
    Ok(_) => abort("Expected cycle error")
  }
}

///|
test "verify: self-cycle path shows cell twice" {
  let rt = Runtime::new()
  let self_ref : Ref[Memo[Int]?] = { val: None }
  let m = Memo::new(rt, () => {
    match self_ref.val {
      Some(memo) => memo.get() + 1
      None => 0
    }
  })
  self_ref.val = Some(m)

  match m.get_result() {
    Err(CycleDetected(cell, path)) => {
      inspect(cell == m.id(), content="true")
      inspect(path.length(), content="2")  // [m, m]
      inspect(path[0] == m.id(), content="true")
      inspect(path[1] == m.id(), content="true")
    }
    Ok(_) => abort("Expected cycle error")
  }
}
```

**Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr -f verify_path_test.mbt`
Expected: FAIL - Path is empty or only contains one cell

**Step 3: Update maybe_changed_after to track path**

Modify `verify.mbt` around line 143-250:

```moonbit
fn maybe_changed_after(
  rt : Runtime,
  cell_id : CellId,
  after : Revision,
) -> Result[Bool, CycleError] {
  let cell = rt.get_cell(cell_id)

  // Fast path: if this cell hasn't changed since 'after', nothing to do
  if cell.changed_at <= after {
    return Ok(false)
  }

  // Input cells can't be reverified - their changed_at is authoritative
  if cell.kind == Input {
    return Ok(true)
  }

  // Durability shortcut
  if rt.durability_last_changed[cell.durability.index()] <= after {
    cell.verified_at = rt.current_revision
    return Ok(false)
  }

  // Check if already verified at current revision
  if cell.verified_at == rt.current_revision {
    return Ok(cell.changed_at > after)
  }

  // Iterative verification with path tracking
  let path : Array[CellId] = []  // NEW: Track cycle path
  let stack : Array[VerifyFrame] = [VerifyFrame::new(cell_id)]

  while stack.length() > 0 {
    let frame = stack[stack.length() - 1]
    let current_cell = rt.get_cell(frame.cell_id)

    if frame.just_pushed {
      frame.just_pushed = false

      // Cycle detection - NEW: return path
      if current_cell.in_progress {
        path.push(frame.cell_id)  // Add the cell that closes the cycle
        return Err(CycleDetected(frame.cell_id, path.copy()))
      }

      current_cell.in_progress = true
      path.push(frame.cell_id)  // NEW: Add to path when starting verification

      // Scan dependencies
      for i = 0; i < current_cell.dependencies.length(); i = i + 1 {
        let dep_id = current_cell.dependencies[i]
        let dep_cell = rt.get_cell(dep_id)

        // Already verified? Skip
        if dep_cell.verified_at == rt.current_revision {
          if dep_cell.changed_at > after {
            frame.any_changed = true
          }
          continue
        }

        // Durability shortcut for this dependency
        if rt.durability_last_changed[dep_cell.durability.index()] <= after {
          dep_cell.verified_at = rt.current_revision
          continue
        }

        // Input changed?
        if dep_cell.kind == Input {
          if dep_cell.changed_at > after {
            frame.any_changed = true
          }
          dep_cell.verified_at = rt.current_revision
          continue
        }

        // Derived cell - need to verify recursively
        stack.push(VerifyFrame::new(dep_id))
      }

      // No more dependencies to verify
      if frame.dependencies_index >= current_cell.dependencies.length() {
        frame.finished = true
      }
    }

    if frame.finished {
      stack.pop()
      path.pop()  // NEW: Remove from path when done verifying

      let needs_recompute = frame.any_changed

      current_cell.in_progress = false

      if needs_recompute {
        match current_cell.recompute_and_check {
          Some(recompute_fn) => {
            match recompute_fn() {
              Ok(value_changed) => {
                if value_changed {
                  current_cell.changed_at = rt.current_revision
                }
                current_cell.verified_at = rt.current_revision

                // Update durability
                current_cell.durability = compute_durability(
                  rt,
                  current_cell.dependencies,
                )

                // Propagate "changed" status to parent frame
                if stack.length() > 0 {
                  let parent_frame = stack[stack.length() - 1]
                  if value_changed {
                    parent_frame.any_changed = true
                  }
                }

                if frame.cell_id == cell_id {
                  return Ok(value_changed)
                }
              }
              Err(err) => {
                current_cell.in_progress = false
                return Err(err)
              }
            }
          }
          None => abort("Derived cell missing recompute function")
        }
      } else {
        // Green path - no dependencies changed
        current_cell.verified_at = rt.current_revision

        if frame.cell_id == cell_id {
          return Ok(false)
        }
      }
    }
  }

  Ok(false)
}
```

**Step 4: Update force_recompute to use new CycleError format**

Modify `memo.mbt` around line 167-210:

```moonbit
fn[T : Eq] Memo::force_recompute(self : Memo[T]) -> Result[Unit, CycleError] {
  let cell = self.rt.get_cell(self.cell_id)
  if cell.in_progress {
    // Build the full cycle path from the tracking stack
    // This preserves the complete dependency chain context, enabling
    // proper diagnostics for both direct self-cycles and nested cycles
    // (e.g., A → B → C → B shows full path, not just [B, B])
    let path : Array[CellId] = []
    // Collect cell IDs from all frames in the tracking stack
    for i = 0; i < self.rt.tracking_stack.length(); i = i + 1 {
      path.push(self.rt.tracking_stack[i].cell_id)
    }
    // Append current cell to show the cycle closes
    path.push(cell.id)
    return Err(CycleDetected(cell.id, path))
  }
  cell.in_progress = true
  // ... rest of function unchanged
}
```

**Step 5: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr -f verify_path_test.mbt`
Expected: PASS (2 tests)

**Step 6: Run all tests to check for regressions**

Run: `moon test`
Expected: FAIL - existing code still uses old CycleDetected(Int) pattern

**Step 7: Commit**

```bash
git add verify.mbt memo.mbt verify_path_test.mbt
git commit -m "feat: track cycle path during verification

Update maybe_changed_after() to maintain path array during traversal.
When cycle detected, return full path instead of just cell ID.
"
```

---

## Task 3: Update Existing Code to Use New CycleError Pattern

**Files:**
- Modify: `memo.mbt:95-98` (Memo::get)
- Modify: `memo.mbt:118` (Memo::get_result doc comment)
- Modify: `cycle.mbt:23` (CycleError doc comment)
- Modify: `docs/api-design-guidelines.md:22,93,220,231,328`
- Modify: `docs/concepts.md:213`
- Modify: `docs/api-reference.md:151,187`
- Modify: `docs/cookbook.md:339`

**Step 1: Update memo.mbt to use new pattern**

```moonbit
// Around line 95:
pub fn[T : Eq] Memo::get(self : Memo[T]) -> T {
  match self.get_result() {
    Ok(value) => value
    Err(CycleDetected(cell, path)) =>
      abort(
        "Cycle detected at cell " + cell.to_string() +
        ", path length: " + path.length().to_string(),
      )
  }
}

// Update doc comment around line 118:
/// ```moonbit nocheck
/// match memo.get_result() {
///   Ok(value) => println("Got: " + value.to_string())
///   Err(CycleDetected(cell, path)) => {
///     println("Cycle at " + cell.to_string())
///     println("Path: " + err.format_path(rt))
///   }
/// }
/// ```
```

**Step 2: Update cycle.mbt doc comment**

```moonbit
// Around line 23:
/// match memo.get_result() {
///   Ok(value) => println("Got: " + value.to_string())
///   Err(CycleDetected(cell, path)) => {
///     println("Cycle at cell " + cell.to_string())
///     println("Path length: " + path.length().to_string())
///   }
/// }
```

**Step 3: Update documentation files**

Modify `docs/api-design-guidelines.md`:
- Line 22: `Err(CycleDetected(_, _)) => 0`
- Line 93: `Err(CycleDetected(cell, path)) => fallback()`
- Line 220-234: Already has correct format in future section
- Line 328: `Err(CycleDetected(_, _)) => 0  // Base case`

Modify `docs/concepts.md` line 213:
```moonbit
Err(CycleDetected(_, _)) => -1  // Fallback value
```

Modify `docs/api-reference.md`:
- Line 151: `Err(CycleDetected(cell, path)) => println("Cycle: " + cell.to_string())`
- Line 187: `CycleDetected(CellId, Array[CellId])`

Modify `docs/cookbook.md` line 339:
```moonbit
Err(CycleDetected(_, _)) => 0  // Base case on cycle
```

**Step 4: Run all tests**

Run: `moon test`
Expected: PASS - all 102+ tests should pass

**Step 5: Commit**

```bash
git add memo.mbt cycle.mbt docs/
git commit -m "fix: update all code to use new CycleError pattern

Update pattern matching from CycleDetected(id) to CycleDetected(cell, path).
Update documentation examples to show cycle path usage.
"
```

---

## Task 4: Add Comprehensive Cycle Path Tests

**Files:**
- Create: `cycle_path_test.mbt`

**Step 1: Write tests for various cycle scenarios**

```moonbit
///|
test "cycle path: simple two-cell cycle" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 0)

  let b_ref : Ref[Memo[Int]?] = { val: None }
  let c_ref : Ref[Memo[Int]?] = { val: None }

  let b = Memo::new(rt, () => {
    match c_ref.val {
      Some(c) => a.get() + c.get()
      None => 0
    }
  })

  let c = Memo::new(rt, () => {
    match b_ref.val {
      Some(b_val) => b_val.get() * 2
      None => 0
    }
  })

  b_ref.val = Some(b)
  c_ref.val = Some(c)

  match b.get_result() {
    Err(CycleDetected(cell, path)) => {
      inspect(path.length() >= 2, content="true")
      inspect(path.contains(b.id()), content="true")
      inspect(path.contains(c.id()), content="true")
    }
    Ok(_) => abort("Expected cycle")
  }
}

///|
test "cycle path: format_path produces readable output" {
  let rt = Runtime::new()
  let self_ref : Ref[Memo[Int]?] = { val: None }
  let m = Memo::new(rt, () => {
    match self_ref.val {
      Some(memo) => memo.get() + 1
      None => 0
    }
  })
  self_ref.val = Some(m)

  match m.get_result() {
    Err(err) => {
      let formatted = err.format_path(rt)
      inspect(formatted.contains("Cycle"), content="true")
      inspect(formatted.contains("→") || formatted.contains("->"), content="true")
      inspect(formatted.contains("Cell["), content="true")
    }
    Ok(_) => abort("Expected cycle")
  }
}

///|
test "cycle path: long cycle is truncated" {
  let rt = Runtime::new()

  // Create a chain of 25 memos with a cycle at the end
  let memos : Array[Memo[Int]] = []

  for i = 0; i < 25; i = i + 1 {
    let idx = i
    let memo = if i == 0 {
      Memo::new(rt, () => memos[24].get())  // Cycle back to last
    } else {
      Memo::new(rt, () => memos[idx - 1].get() + 1)
    }
    memos.push(memo)
  }

  match memos[0].get_result() {
    Err(err) => {
      let formatted = err.format_path(rt)
      // Should contain truncation message
      inspect(formatted.contains("...") || formatted.contains("more"), content="true")
    }
    Ok(_) => abort("Expected cycle")
  }
}
```

**Step 2: Run tests**

Run: `moon test -p dowdiness/incr -f cycle_path_test.mbt`
Expected: PASS (3 tests)

**Step 3: Commit**

```bash
git add cycle_path_test.mbt
git commit -m "test: add comprehensive cycle path tests

Test various cycle scenarios including simple cycles, self-cycles,
format_path output, and long cycle truncation.
"
```

---

## Task 5: Update Documentation with Examples

**Files:**
- Modify: `docs/api-reference.md` (add cycle path section)
- Modify: `docs/cookbook.md` (add debugging cycles recipe)

**Step 1: Add cycle path documentation to API reference**

Add to `docs/api-reference.md` after the CycleError section (around line 190):

```markdown
### Cycle Path Debugging

When a cycle is detected, `CycleError` now includes the full dependency path:

```moonbit
match memo.get_result() {
  Err(CycleDetected(cell, path)) => {
    println("Cycle detected at: " + cell.to_string())
    println("Dependency path:")
    for i = 0; i < path.length(); i = i + 1 {
      println("  " + path[i].to_string())
    }

    // Or use the formatted version
    println(err.format_path(rt))
  }
  Ok(value) => use_value(value)
}
```

The `format_path()` method produces human-readable output:

```
Cycle detected: Cell[5] → Cell[7] → Cell[5]
```

For long cycles (>20 cells), the output is truncated:

```
Cycle detected: Cell[0] → Cell[1] → ... (18 more) → Cell[23] → Cell[0]
```
```

**Step 2: Add debugging recipe to cookbook**

Add to `docs/cookbook.md` in the Debugging section:

```markdown
### Debugging Cycles

When you encounter a cycle error, use the path information to understand the dependency chain:

```moonbit
match computation.get_result() {
  Err(err) => {
    let path = err.path()
    let formatted = err.format_path(rt)

    println("Cycle detected!")
    println(formatted)

    // Analyze the cycle
    println("\nDetailed path:")
    for i = 0; i < path.length(); i = i + 1 {
      match rt.cell_info(path[i]) {
        Some(info) => {
          println("  Step " + i.to_string() + ": Cell " + path[i].to_string())
          println("    Changed at: " + info.changed_at.value.to_string())
          println("    Dependencies: " + info.dependencies.length().to_string())
        }
        None => println("  Step " + i.to_string() + ": Unknown cell")
      }
    }
  }
  Ok(result) => use_result(result)
}
```

This helps identify:
- Which cells form the cycle
- The order of dependencies that created the loop
- Metadata about each cell in the cycle path
```

**Step 3: Commit**

```bash
git add docs/api-reference.md docs/cookbook.md
git commit -m "docs: add cycle path debugging examples

Add documentation showing how to use cycle path information
for debugging. Include examples of format_path() usage and
manual path inspection.
"
```

---

## Task 6: Update TODO and Mark Tasks Complete

**Files:**
- Modify: `docs/todo.md:39-42`

**Step 1: Mark cycle error tasks as complete**

```markdown
### Error Diagnostics (Phase 2A - High Priority)

- [x] Change `CycleError` to include cycle path: `CycleDetected(CellId, Array[CellId])`
- [x] Add `CycleError::path(self) -> Array[CellId]`
- [x] Add `CycleError::format_path(self, Runtime) -> String` for human-readable output
- [x] Update cycle detection in `verify.mbt` to track path during traversal
```

**Step 2: Commit**

```bash
git add docs/todo.md
git commit -m "docs: mark enhanced cycle errors as complete

Phase 2A cycle error diagnostics fully implemented with
path tracking and formatting.
"
```

---

## Summary

**Total Tasks:** 6
**Estimated Time:** 2-3 hours
**Test Coverage:** 8+ new tests, all existing tests updated

**Key Changes:**
- CycleError now stores full cycle path
- Verification algorithm tracks path during traversal
- Helper methods for path access and formatting
- All existing code updated to new pattern
- Comprehensive test coverage
- Documentation with debugging examples

**Breaking Changes:**
- `CycleDetected(Int)` → `CycleDetected(CellId, Array[CellId])`
- `CycleError::cell_id()` removed, use `CycleError::cell()` instead
- All pattern matches need updating to `CycleDetected(cell, path)` or `CycleDetected(_, _)`