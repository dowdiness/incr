# Phase 1 Introspection API Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable programmatic access to dependency graph metadata for debugging and analysis.

**Architecture:** Add accessor methods to Signal and Memo that expose CellId, dependencies, and revision timestamps. Add Runtime::cell_info() for uniform metadata access. Make CellId and Revision public types.

**Tech Stack:** MoonBit, existing incr library architecture

---

## Task 1: Make CellId and Revision Public

**Files:**
- Modify: `cell.mbt:6-8`
- Modify: `revision.mbt:12-14`

**Step 1: Make CellId public**

In `cell.mbt`, change line 6 from:
```moonbit
priv struct CellId {
```

to:
```moonbit
pub(all) struct CellId {
```

**Step 2: Make Revision public**

In `revision.mbt`, change line 12 from:
```moonbit
priv struct Revision {
```

to:
```moonbit
pub(all) struct Revision {
```

**Step 3: Verify compilation**

Run: `moon check`
Expected: No errors (these are pure visibility changes)

**Step 4: Commit**

```bash
git add cell.mbt revision.mbt
git commit -m "feat: make CellId and Revision public for introspection API

These types are now part of the public API to support
introspection methods that return cell identifiers and
revision timestamps.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Add CellInfo Struct

**Files:**
- Modify: `runtime.mbt` (add after Runtime::new() definition, around line 53)

**Step 1: Add CellInfo struct definition**

Add this after the `Runtime::new()` function in `runtime.mbt`:

```moonbit
///|
/// Structured metadata about a cell in the dependency graph.
///
/// This structure provides a uniform view of both Signal and Memo cells.
/// For signals, the `dependencies` array will be empty.
///
/// # Fields
///
/// - `id`: The unique identifier for this cell
/// - `changed_at`: When this cell's value last actually changed
/// - `verified_at`: When this cell was last confirmed up-to-date
/// - `durability`: How often this cell is expected to change
/// - `dependencies`: Cell IDs this cell depends on (empty for signals)
pub(all) struct CellInfo {
  pub id : CellId
  pub changed_at : Revision
  pub verified_at : Revision
  pub durability : Durability
  pub dependencies : Array[CellId]
}
```

**Step 2: Verify compilation**

Run: `moon check`
Expected: No errors

**Step 3: Commit**

```bash
git add runtime.mbt
git commit -m "feat: add CellInfo struct for introspection

Provides structured access to cell metadata for debugging
and analysis tools.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Add Signal Introspection Methods

**Files:**
- Modify: `signal.mbt` (add after Signal::get_result(), around line 102)
- Create: `signal_introspection_test.mbt`

**Step 1: Write the failing test**

Create `signal_introspection_test.mbt`:

```moonbit
///|
test "signal: id() returns valid CellId" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let id = sig.id()
  inspect(id.id >= 0, content="true")
}

///|
test "signal: durability() returns construction durability" {
  let rt = Runtime::new()
  let low_sig = Signal::new(rt, 1)
  let high_sig = Signal::new_with_durability(rt, 2, High)

  inspect(low_sig.durability(), content="Low")
  inspect(high_sig.durability(), content="High")
}

///|
test "signal: multiple signals have distinct IDs" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 10)
  let b = Signal::new(rt, 20)

  inspect(a.id() != b.id(), content="true")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr -f signal_introspection_test.mbt`
Expected: Compilation error - methods not found

**Step 3: Implement Signal::id() and Signal::durability()**

Add to `signal.mbt` after `Signal::get_result()`:

```moonbit
///|
/// Returns the unique identifier for this signal.
///
/// The CellId can be used with `Runtime::cell_info()` to retrieve
/// metadata, or to compare cell identities.
///
/// # Returns
///
/// The cell identifier for this signal
///
/// # Example
///
/// ```moonbit nocheck
/// let sig = Signal::new(rt, 42)
/// let id = sig.id()
/// match rt.cell_info(id) {
///   Some(info) => println("Signal changed at: " + info.changed_at.to_string())
///   None => ()
/// }
/// ```
pub fn[T] Signal::id(self : Signal[T]) -> CellId {
  self.cell_id
}

///|
/// Returns the durability level of this signal.
///
/// Durability indicates how often this signal is expected to change:
/// - `High`: Rarely changes (e.g., configuration)
/// - `Medium`: Moderately stable
/// - `Low`: Frequently changes (e.g., user input)
///
/// # Returns
///
/// The durability level set at construction time
pub fn[T] Signal::durability(self : Signal[T]) -> Durability {
  self.durability
}
```

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr -f signal_introspection_test.mbt`
Expected: All 3 tests pass

**Step 5: Commit**

```bash
git add signal.mbt signal_introspection_test.mbt
git commit -m "feat: add Signal introspection methods (id, durability)

Signal::id() returns the unique CellId for this signal.
Signal::durability() returns the durability level.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Add Memo Introspection Methods

**Files:**
- Modify: `memo.mbt` (add after Memo::is_up_to_date(), around line 180)
- Create: `memo_introspection_test.mbt`

**Step 1: Write the failing test**

Create `memo_introspection_test.mbt`:

```moonbit
///|
test "memo: id() returns valid CellId" {
  let rt = Runtime::new()
  let m = Memo::new(rt, () => 42)
  let id = m.id()
  inspect(id.id >= 0, content="true")
}

///|
test "memo: dependencies() returns empty before computation" {
  let rt = Runtime::new()
  let m = Memo::new(rt, () => 10)
  inspect(m.dependencies(), content="[]")
}

///|
test "memo: dependencies() includes all inputs after computation" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 1)
  let y = Signal::new(rt, 2)
  let sum = Memo::new(rt, () => x.get() + y.get())

  sum.get() |> ignore
  let deps = sum.dependencies()
  inspect(deps.length(), content="2")
  inspect(deps.contains(x.id()), content="true")
  inspect(deps.contains(y.id()), content="true")
}

///|
test "memo: changed_at and verified_at track revisions" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 10)
  let doubled = Memo::new(rt, () => x.get() * 2)

  doubled.get() |> ignore
  let initial_changed = doubled.changed_at()
  let initial_verified = doubled.verified_at()

  inspect(initial_changed.value > 0, content="true")
  inspect(initial_verified.value > 0, content="true")

  // Change input
  x.set(20)
  doubled.get() |> ignore

  inspect(doubled.changed_at().value > initial_changed.value, content="true")
  inspect(doubled.verified_at().value > initial_verified.value, content="true")
}

///|
test "memo: dependencies update on recomputation" {
  let rt = Runtime::new()
  let cond = Signal::new(rt, true)
  let a = Signal::new(rt, 1)
  let b = Signal::new(rt, 2)

  let dynamic = Memo::new(rt, () => {
    if cond.get() { a.get() } else { b.get() }
  })

  dynamic.get() |> ignore
  let deps1 = dynamic.dependencies()
  inspect(deps1.contains(a.id()), content="true")
  inspect(deps1.contains(b.id()), content="false")

  cond.set(false)
  dynamic.get() |> ignore
  let deps2 = dynamic.dependencies()
  inspect(deps2.contains(a.id()), content="false")
  inspect(deps2.contains(b.id()), content="true")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr -f memo_introspection_test.mbt`
Expected: Compilation error - methods not found

**Step 3: Implement Memo introspection methods**

Add to `memo.mbt` after `Memo::is_up_to_date()`:

```moonbit
///|
/// Returns the unique identifier for this memo.
///
/// The CellId can be used with `Runtime::cell_info()` to retrieve
/// metadata, or to compare cell identities.
///
/// # Returns
///
/// The cell identifier for this memo
pub fn[T] Memo::id(self : Memo[T]) -> CellId {
  self.cell_id
}

///|
/// Returns the list of cell IDs this memo currently depends on.
///
/// The dependency list is empty before the first computation and
/// updates each time the memo recomputes (for dynamic dependencies).
///
/// # Returns
///
/// A copy of the current dependency list. Returns empty array if
/// the memo has never been computed.
///
/// # Example
///
/// ```moonbit nocheck
/// let x = Signal::new(rt, 1)
/// let m = Memo::new(rt, () => x.get() * 2)
/// m.get() |> ignore
/// inspect(m.dependencies().contains(x.id()), content="true")
/// ```
pub fn[T] Memo::dependencies(self : Memo[T]) -> Array[CellId] {
  let meta = self.rt.cells[self.cell_id.id]
  match meta {
    Some(m) => m.dependencies.copy()
    None => []
  }
}

///|
/// Returns the revision when this memo's value last changed.
///
/// This reflects backdating: if a recomputation produces the same
/// value, `changed_at` is preserved from the previous computation.
///
/// # Returns
///
/// The revision timestamp of the last actual value change
pub fn[T] Memo::changed_at(self : Memo[T]) -> Revision {
  let meta = self.rt.cells[self.cell_id.id]
  match meta {
    Some(m) => m.changed_at
    None => Revision::initial()
  }
}

///|
/// Returns the revision when this memo was last verified up-to-date.
///
/// A memo is stale when `verified_at < current_revision`. Use this
/// to understand when a memo was last checked.
///
/// # Returns
///
/// The revision timestamp of the last verification
pub fn[T] Memo::verified_at(self : Memo[T]) -> Revision {
  let meta = self.rt.cells[self.cell_id.id]
  match meta {
    Some(m) => m.verified_at
    None => Revision::initial()
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr -f memo_introspection_test.mbt`
Expected: All 5 tests pass

**Step 5: Commit**

```bash
git add memo.mbt memo_introspection_test.mbt
git commit -m "feat: add Memo introspection methods

Memo::id() returns the unique CellId.
Memo::dependencies() returns the current dependency list.
Memo::changed_at() returns when value last changed (backdating-aware).
Memo::verified_at() returns when last verified up-to-date.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Add Runtime::cell_info()

**Files:**
- Modify: `runtime.mbt` (add after Runtime::fire_on_change(), around line 300)
- Create: `runtime_introspection_test.mbt`

**Step 1: Write the failing test**

Create `runtime_introspection_test.mbt`:

```moonbit
///|
test "runtime: cell_info() returns metadata for signal" {
  let rt = Runtime::new()
  let sig = Signal::new_with_durability(rt, 42, High)

  match rt.cell_info(sig.id()) {
    Some(info) => {
      inspect(info.id == sig.id(), content="true")
      inspect(info.durability, content="High")
      inspect(info.dependencies, content="[]")
    }
    None => abort("Expected Some(info)")
  }
}

///|
test "runtime: cell_info() returns metadata for memo" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 10)
  let doubled = Memo::new(rt, () => x.get() * 2)

  doubled.get() |> ignore

  match rt.cell_info(doubled.id()) {
    Some(info) => {
      inspect(info.id == doubled.id(), content="true")
      inspect(info.dependencies.contains(x.id()), content="true")
      inspect(info.changed_at.value > 0, content="true")
      inspect(info.verified_at.value > 0, content="true")
    }
    None => abort("Expected Some(info)")
  }
}

///|
test "runtime: cell_info() returns None for out-of-bounds CellId" {
  let rt = Runtime::new()
  let invalid_id : CellId = { id: 999 }

  match rt.cell_info(invalid_id) {
    Some(_) => abort("Expected None for invalid ID")
    None => ()
  }
}

///|
test "runtime: cell_info() returns None for unused slot" {
  let rt = Runtime::new()
  // Create and verify we have at least one cell
  let _sig = Signal::new(rt, 1)

  // Try to access a slot beyond what's been allocated
  let beyond_id : CellId = { id: rt.cells.length() + 10 }

  match rt.cell_info(beyond_id) {
    Some(_) => abort("Expected None for unused slot")
    None => ()
  }
}
```

**Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr -f runtime_introspection_test.mbt`
Expected: Compilation error - Runtime::cell_info() not found

**Step 3: Implement Runtime::cell_info()**

Add to `runtime.mbt` after `Runtime::fire_on_change()`:

```moonbit
///|
/// Retrieves structured metadata for a cell by its identifier.
///
/// This provides uniform access to metadata for both signals and memos.
/// Returns `None` if the CellId is invalid (out of bounds or unused slot).
///
/// # Parameters
///
/// - `id`: The cell identifier to query
///
/// # Returns
///
/// `Some(CellInfo)` with the cell's metadata, or `None` if the cell
/// doesn't exist
///
/// # Example
///
/// ```moonbit nocheck
/// let sig = Signal::new(rt, 42)
/// match rt.cell_info(sig.id()) {
///   Some(info) => println("Durability: " + info.durability.to_string())
///   None => println("Cell not found")
/// }
/// ```
pub fn Runtime::cell_info(self : Runtime, id : CellId) -> CellInfo? {
  // Check bounds (both negative and out of range)
  if id.id < 0 || id.id >= self.cells.length() {
    return None
  }

  // Retrieve metadata
  match self.cells[id.id] {
    Some(meta) => Some({
      id,
      changed_at: meta.changed_at,
      verified_at: meta.verified_at,
      durability: meta.durability,
      dependencies: meta.dependencies.copy()
    })
    None => None
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr -f runtime_introspection_test.mbt`
Expected: All 4 tests pass

**Step 5: Commit**

```bash
git add runtime.mbt runtime_introspection_test.mbt
git commit -m "feat: add Runtime::cell_info() for uniform introspection

Returns structured CellInfo with metadata for any cell.
Returns None for invalid or unused CellIds.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Add Integration Tests

**Files:**
- Create: `introspection_integration_test.mbt`

**Step 1: Write integration test for debugging recomputation**

Create `introspection_integration_test.mbt`:

```moonbit
///|
test "integration: debug why memo recomputed" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 10)
  let y = Signal::new(rt, 20)
  let sum = Memo::new(rt, () => x.get() + y.get())

  sum.get() |> ignore
  let initial_verified = sum.verified_at()

  // Same value - backdating means no effective change
  x.set(10)
  sum.get() |> ignore
  inspect(sum.verified_at() == initial_verified, content="true")

  // Different value - should trigger recomputation
  y.set(30)
  sum.get() |> ignore
  inspect(sum.verified_at().value > initial_verified.value, content="true")

  // Identify which dependency caused recomputation
  let mut found_culprit = false
  for dep_id in sum.dependencies() {
    match rt.cell_info(dep_id) {
      Some(info) => {
        if info.changed_at.value > initial_verified.value {
          // Found it: y's changed_at is after initial verification
          inspect(dep_id == y.id(), content="true")
          found_culprit = true
        }
      }
      None => ()
    }
  }
  inspect(found_culprit, content="true")
}

///|
test "integration: analyze dependency chain" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 5)
  let step1 = Memo::new(rt, () => input.get() * 2)
  let step2 = Memo::new(rt, () => step1.get() + 10)
  let step3 = Memo::new(rt, () => step2.get() * 3)

  step3.get() |> ignore

  // Verify dependency chain
  inspect(step3.dependencies().contains(step2.id()), content="true")
  inspect(step2.dependencies().contains(step1.id()), content="true")
  inspect(step1.dependencies().contains(input.id()), content="true")

  // Verify no cross-dependencies
  inspect(step3.dependencies().contains(input.id()), content="false")
  inspect(step3.dependencies().contains(step1.id()), content="false")
}

///|
test "integration: diamond dependency has no duplicates" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 10)
  let left = Memo::new(rt, () => input.get() + 1)
  let right = Memo::new(rt, () => input.get() + 2)
  let merge = Memo::new(rt, () => left.get() + right.get())

  merge.get() |> ignore

  // Merge depends on left and right
  let merge_deps = merge.dependencies()
  inspect(merge_deps.contains(left.id()), content="true")
  inspect(merge_deps.contains(right.id()), content="true")

  // But input appears only once in left's and right's dependencies
  let left_deps = left.dependencies()
  let right_deps = right.dependencies()

  let mut input_count_left = 0
  for dep in left_deps {
    if dep == input.id() {
      input_count_left = input_count_left + 1
    }
  }
  inspect(input_count_left, content="1")

  let mut input_count_right = 0
  for dep in right_deps {
    if dep == input.id() {
      input_count_right = input_count_right + 1
    }
  }
  inspect(input_count_right, content="1")
}

///|
test "integration: understanding backdating with introspection" {
  let rt = Runtime::new()
  let config = Signal::new(rt, "prod")
  let expensive = Memo::new(rt, () => {
    // Simulate expensive computation
    config.get() + "_processed"
  })

  expensive.get() |> ignore
  let old_changed_at = expensive.changed_at()

  // Set to same value
  config.set("prod")
  expensive.get() |> ignore

  // Backdating: changed_at didn't advance even though we recomputed
  inspect(expensive.changed_at() == old_changed_at, content="true")

  // But verified_at did advance (we did verify it's up to date)
  inspect(expensive.verified_at().value > old_changed_at.value, content="true")
}
```

**Step 2: Run integration tests**

Run: `moon test -p dowdiness/incr -f introspection_integration_test.mbt`
Expected: All 4 integration tests pass

**Step 3: Commit**

```bash
git add introspection_integration_test.mbt
git commit -m "test: add integration tests for introspection API

Demonstrates real-world debugging scenarios:
- Identifying which dependency caused recomputation
- Analyzing dependency chains
- Verifying no duplicate dependencies in diamond patterns
- Understanding backdating behavior

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Run Full Test Suite

**Step 1: Run all tests to verify no regressions**

Run: `moon test`
Expected: All 44+ tests pass (original 44 + new introspection tests)

**Step 2: If any test fails, debug and fix**

If failures occur:
1. Read the failure message
2. Identify the failing test
3. Run that specific test: `moon test -p dowdiness/incr -f <filename>.mbt -i <index>`
4. Fix the issue
5. Re-run full test suite
6. Commit the fix

**Step 3: Verify type checking**

Run: `moon check`
Expected: No type errors

---

## Task 8: Update Documentation

**Files:**
- Modify: `docs/api-reference.md` (add introspection section)
- Modify: `docs/cookbook.md` (add debugging recipes)
- Modify: `docs/design.md` (note introspection API availability)

**Step 1: Add introspection section to API reference**

Add to `docs/api-reference.md` after the Memo section:

```markdown
## Introspection and Debugging

### Signal Introspection

#### `Signal::id(self) -> CellId`

Returns the unique identifier for this signal.

**Example:**
```moonbit
let sig = Signal::new(rt, 42)
let id = sig.id()
```

#### `Signal::durability(self) -> Durability`

Returns the durability level of this signal (`Low`, `Medium`, or `High`).

**Example:**
```moonbit
let config = Signal::new_with_durability(rt, "prod", High)
inspect(config.durability(), content="High")
```

### Memo Introspection

#### `Memo::id(self) -> CellId`

Returns the unique identifier for this memo.

#### `Memo::dependencies(self) -> Array[CellId]`

Returns the list of cells this memo currently depends on. Empty if the memo has never been computed.

**Example:**
```moonbit
let x = Signal::new(rt, 1)
let doubled = Memo::new(rt, () => x.get() * 2)
doubled.get() |> ignore
inspect(doubled.dependencies().contains(x.id()), content="true")
```

#### `Memo::changed_at(self) -> Revision`

Returns when this memo's value last changed. Reflects backdating: if recomputation produces the same value, this timestamp is preserved.

#### `Memo::verified_at(self) -> Revision`

Returns when this memo was last verified up-to-date.

### Runtime Introspection

#### `Runtime::cell_info(self, id : CellId) -> CellInfo?`

Retrieves structured metadata for any cell. Returns `None` if the CellId is invalid.

**Example:**
```moonbit
match rt.cell_info(memo.id()) {
  Some(info) => {
    println("Changed at: " + info.changed_at.to_string())
    println("Dependencies: " + info.dependencies.length().to_string())
  }
  None => println("Cell not found")
}
```

### CellInfo Structure

```moonbit
pub struct CellInfo {
  pub id : CellId
  pub changed_at : Revision
  pub verified_at : Revision
  pub durability : Durability
  pub dependencies : Array[CellId]
}
```

For signals, `dependencies` is empty.
```

**Step 2: Add debugging recipes to cookbook**

Add to `docs/cookbook.md`:

```markdown
## Debugging

### Why Did This Memo Recompute?

Use introspection to identify which dependency triggered recomputation:

```moonbit
let rt = Runtime::new()
let x = Signal::new(rt, 10)
let y = Signal::new(rt, 20)
let sum = Memo::new(rt, () => x.get() + y.get())

sum.get() |> ignore
let baseline = sum.verified_at()

// Make some changes
x.set(15)
sum.get() |> ignore

// Find the culprit
for dep_id in sum.dependencies() {
  match rt.cell_info(dep_id) {
    Some(info) => {
      if info.changed_at.value > baseline.value {
        println("Dependency " + dep_id.id.to_string() + " changed")
      }
    }
    None => ()
  }
}
```

### Analyzing Dependency Chains

Trace the full dependency path:

```moonbit
fn print_dependencies(rt : Runtime, memo : Memo[Int], depth : Int) -> Unit {
  let indent = "  ".repeat(depth)
  println(indent + "Memo " + memo.id().id.to_string())

  for dep_id in memo.dependencies() {
    match rt.cell_info(dep_id) {
      Some(info) => {
        println(indent + "  -> Cell " + dep_id.id.to_string() +
                " (changed_at=" + info.changed_at.value.to_string() + ")")
      }
      None => ()
    }
  }
}
```

### Testing Dependency Tracking

Verify that memos only depend on what they actually read:

```moonbit
test "memo only depends on x, not y" {
  let x = Signal::new(rt, 1)
  let y = Signal::new(rt, 2)
  let uses_x_only = Memo::new(rt, () => x.get() * 2)

  uses_x_only.get() |> ignore

  let deps = uses_x_only.dependencies()
  inspect(deps.contains(x.id()), content="true")
  inspect(deps.contains(y.id()), content="false")
}
```

### Understanding Backdating

Check if a memo's value actually changed:

```moonbit
let memo = Memo::new(rt, () => config.get().length())
memo.get() |> ignore
let old_changed = memo.changed_at()

config.set("same_length")  // Different string, same length
memo.get() |> ignore

// Backdating: value didn't change, so changed_at is preserved
inspect(memo.changed_at() == old_changed, content="true")
```
```

**Step 3: Update design.md**

Add a note in `docs/design.md` after the introduction:

```markdown
> **Note:** The introspection API (Phase 2A) is now available. See the
> [Phase 1 Introspection Design](plans/2026-02-16-introspection-api-phase1-design.md)
> for details on the accessor methods and `CellInfo` structure.
```

**Step 4: Commit documentation updates**

```bash
git add docs/api-reference.md docs/cookbook.md docs/design.md
git commit -m "docs: add introspection API documentation

- API reference for Signal/Memo/Runtime introspection methods
- Cookbook recipes for debugging scenarios
- Cross-reference to design document

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 9: Final Verification

**Step 1: Run complete test suite**

Run: `moon test`
Expected: All tests pass (44 original + 13 new introspection tests = 57 total)

**Step 2: Build the library**

Run: `moon build`
Expected: Clean build with no errors or warnings

**Step 3: Review git log**

Run: `git log --oneline -10`
Expected: See all commits for this feature in logical order

**Step 4: Tag completion in TODO**

Edit `docs/todo.md` and check off completed items in the "Introspection API (Phase 2A - High Priority)" section:

```markdown
- [x] Add `Signal::id(self) -> CellId`
- [x] Add `Signal::durability(self) -> Durability`
- [x] Add `Memo::dependencies(self) -> Array[CellId]`
- [x] Add `Memo::changed_at(self) -> Revision`
- [x] Add `Memo::verified_at(self) -> Revision`
- [x] Add `Runtime::cell_info(self, CellId) -> CellInfo` struct
- [x] Define `CellInfo` struct with all cell metadata
```

**Step 5: Commit TODO updates**

```bash
git add docs/todo.md
git commit -m "docs: mark Phase 2A introspection tasks as complete

All core introspection methods are now implemented and tested.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Success Criteria

✅ All new methods compile and type-check
✅ 13 new tests added and passing
✅ All 44 existing tests still pass (no regressions)
✅ Documentation updated with examples
✅ CellId and Revision are now public types
✅ Developers can programmatically answer "why did this recompute?"

## Next Steps (Out of Scope)

After this plan is complete, consider:

- **Phase 2:** Debug formatting (`Signal::debug()`, `Memo::debug()`)
- **Phase 3:** Graph visualization (DOT format output)
- **Phase 2A (continued):** Enhanced error diagnostics (cycle path in `CycleError`)
- **Phase 2B:** Per-cell change callbacks

See `docs/roadmap.md` for the full roadmap.
