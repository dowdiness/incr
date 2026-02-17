# Enhanced Cycle Error Diagnostics

**Date:** 2026-02-17
**Status:** Approved
**Phase:** 2A - Introspection & Debugging

## Overview

Enhance `CycleError` to include the full dependency path that led to the cycle, enabling human-readable error messages that help users understand how cycles form in their computation graphs.

### Current State

When a cycle is detected, users get a `CycleError` with a single `CellId` - the cell where the cycle was detected. This tells them *that* a cycle exists, but not *how* the cycle formed.

### Goal

Provide the full cycle path so users can see the dependency chain:
```
Cycle detected: Signal[0] → Memo[1] → Memo[2] → Memo[1]
```

## API Changes

### CycleError Structure

**Current:**
```moonbit
pub enum CycleError {
  CycleDetected(CellId)
}
```

**New:**
```moonbit
pub enum CycleError {
  CycleDetected(CellId, Array[CellId])
  //             ^cell   ^cycle path from root to cycle point
}
```

**Breaking Change:** Existing code matching on `CycleDetected(id)` will need to update to `CycleDetected(id, _)` or `CycleDetected(id, path)`.

### New Methods

```moonbit
/// Returns the CellId where the cycle was detected
pub fn CycleError::cell(self : CycleError) -> CellId

/// Returns the full dependency path leading to the cycle
pub fn CycleError::path(self : CycleError) -> Array[CellId]

/// Formats the cycle path as a human-readable string
/// Uses Runtime::cell_info() to get cell metadata for better output
pub fn CycleError::format_path(self : CycleError, rt : Runtime) -> String
```

## Implementation Strategy

### Path Tracking During Verification

The cycle detection happens in `verify.mbt` in the `maybe_changed_after()` function. Currently, it uses an iterative algorithm with a `VerifyFrame` stack and sets `in_progress = true` on cells being verified.

#### Modified Algorithm

Maintain a parallel `path : Array[CellId]` alongside the verification stack:

```moonbit
fn maybe_changed_after(rt, cell_id, rev) -> Result[Bool, CycleError] {
  let path : Array[CellId] = []
  let stack : Array[VerifyFrame] = [VerifyFrame::new(cell_id)]

  while stack.length() > 0 {
    let frame = stack[stack.length() - 1]

    if frame.just_pushed {
      // Check for cycle
      if meta.in_progress {
        return Err(CycleDetected(cell_id, path.copy()))
      }
      meta.in_progress = true
      path.push(cell_id)

      // ... rest of verification logic
    }

    if frame.finished {
      stack.pop()
      path.pop()  // Remove cell from path when done
      meta.in_progress = false
    }
  }
}
```

**How it works:**
- As we push a `VerifyFrame` for a cell, append its `CellId` to the path
- When we pop the frame (cell verification complete), remove it from the path
- When we detect `in_progress = true`, the current `path` array contains the cycle
- The path from the first occurrence of the repeated cell to the end forms the cycle

**Memory Overhead:** O(depth) during verification. For typical graphs (depth < 100), this is negligible.

## Error Handling & Edge Cases

### Edge Cases

**1. Self-Cycles (A → A)**
- Path will be `[A, A]`
- Format: `"Cycle detected: Cell[0] → Cell[0]"`

**2. Multi-Cell Cycles (A → B → C → B)**
- Path captures full traversal including entry into cycle
- Format from first occurrence of repeated cell: `"Cycle detected: Cell[1] → Cell[2] → Cell[1]"`

**3. Invalid CellId in Path**
- If `cell_info()` returns `None` for a CellId in the path (shouldn't happen)
- Show `"Cell[?]"` instead of crashing
- Defensive coding for robustness

**4. Very Long Cycles**
- If cycle has more than 20 cells, truncate after the 20th cell
- Format: `"Cycle detected: Cell[0] → Cell[1] → ... → Cell[19] → ..."`

### Format Examples

```moonbit
// Simple 2-cell cycle
"Cycle detected: Cell[5] → Cell[7] → Cell[5]"

// Self-cycle
"Cycle detected: Cell[3] → Cell[3]"

// Note: cell type and durability metadata are not currently shown.
// All cells are formatted as "Cell[N]" regardless of whether they are
// signals or memos. Richer formatting (e.g., "Signal[0]", "Memo[1]")
// may be added in a future enhancement using rt.cell_info().
```

### Performance Impact

- Path tracking adds one array append/pop per verification frame
- Path array allocated once per `maybe_changed_after()` call
- Minimal overhead: typical verification with 10 dependencies adds ~10 array operations
- No impact on the happy path (no cycles)

## Testing Strategy

### Test Coverage

1. **Basic Cycle Detection with Path**
   - Create A → B → C → B cycle
   - Verify path contains B and C
   - Verify path length >= 2

2. **Self-Cycle**
   - Memo that reads itself
   - Verify path is `[cell, cell]`
   - Verify formatted output shows self-reference

3. **Format Path Output**
   - Verify `format_path()` produces readable string
   - Check for arrow notation (→)
   - Verify cell IDs are present

4. **Long Cycle Truncation**
   - Create cycle with >20 cells
   - Verify truncation message appears
   - Verify first and last cells are shown

5. **Invalid CellId Handling**
   - Test defensive handling when `cell_info()` returns `None`
   - Verify graceful degradation to `"Cell[?]"`

### Backwards Compatibility

Existing tests matching on `CycleDetected(id)` need updates to `CycleDetected(id, _)`:
- Update all cycle tests in one commit
- Maintain test suite health throughout

## Implementation Tasks

1. Modify `CycleError` enum in `cycle.mbt`
2. Add `cell()`, `path()`, and `format_path()` methods
3. Update `maybe_changed_after()` in `verify.mbt` to track path
4. Update all existing cycle tests for new pattern
5. Add new tests for path tracking and formatting
6. Update error handling in `Signal::get_result()` and `Memo::get_result()`
7. Update documentation in API reference and cookbook

## Success Criteria

- All existing tests pass with updated pattern matching
- New tests verify path tracking accuracy
- `format_path()` produces human-readable output
- No performance regression in verification (< 1% overhead)
- Users can debug cycles by seeing the full dependency chain
