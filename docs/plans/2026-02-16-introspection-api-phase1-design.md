# Introspection API - Phase 1 Design

**Date:** 2026-02-16
**Status:** Approved
**Phase:** 2A - Introspection & Debugging (High Priority)

## Overview

This design covers Phase 1 of the introspection API: providing programmatic access to the dependency graph metadata. This enables developers to debug "why did this memo recompute?" questions and build analysis tools.

## Goals

1. Expose cell identifiers and metadata through public APIs
2. Enable querying of dependency relationships
3. Provide revision tracking information (changed_at, verified_at)
4. Maintain zero runtime cost when introspection is not used
5. Keep API simple and type-safe

## Non-Goals (Deferred to Later Phases)

- Debug formatting methods (`Signal::debug()`, `Memo::debug()`) - Phase 2
- Graph visualization (DOT format, textual dumps) - Phase 3
- Reverse dependency tracking (dependents) - Requires Phase 4 subscriber links
- Cell labels/names - Deferred to builder pattern (Phase 2C)

## API Design

### Per-Cell Methods

**Signal[T]:**
```moonbit
pub fn[T] Signal::id(self : Signal[T]) -> CellId
pub fn[T] Signal::durability(self : Signal[T]) -> Durability
```

Rationale:
- Signals don't need `changed_at()`/`verified_at()` as user-controlled inputs
- Signals don't have dependencies (they're leaf nodes)
- Users can get full metadata via `Runtime::cell_info(signal.id())` if needed

**Memo[T]:**
```moonbit
pub fn[T] Memo::id(self : Memo[T]) -> CellId
pub fn[T] Memo::dependencies(self : Memo[T]) -> Array[CellId]
pub fn[T] Memo::changed_at(self : Memo[T]) -> Revision
pub fn[T] Memo::verified_at(self : Memo[T]) -> Revision
```

Rationale:
- Most common debugging need: "what does this memo depend on?"
- Revision tracking helps understand backdating behavior
- Ergonomic for the common case (direct method on Memo)

### Runtime Method

```moonbit
pub fn Runtime::cell_info(self : Runtime, id : CellId) -> CellInfo?
```

Returns `None` if:
- CellId is out of bounds
- CellId refers to an unused slot
- CellId belongs to a different Runtime instance

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

This structure is generic (works for both Signal and Memo):
- For signals, `dependencies` will be empty `[]`
- All fields are public for direct access
- Structure is cheap to construct (all fields are Copy or small)

## Implementation Strategy

### Accessing Cell Metadata

All introspection methods read from `Runtime.cells : Array[CellMeta?]`. Since Signal and Memo already contain a `CellId`, implementation is straightforward.

**Per-cell methods pattern:**
```moonbit
pub fn[T] Memo::dependencies(self : Memo[T]) -> Array[CellId] {
  let meta = self.id.runtime.cells[self.id.id]
  match meta {
    Some(m) => m.dependencies.copy()
    None => []  // Defensive: should never happen for valid cells
  }
}
```

**Runtime::cell_info() pattern:**
```moonbit
pub fn Runtime::cell_info(self : Runtime, id : CellId) -> CellInfo? {
  // Optional: validate CellId belongs to this Runtime
  // (May require pointer comparison if MoonBit supports it)

  if id.id >= self.cells.length() {
    return None  // Out of bounds
  }

  match self.cells[id.id] {
    Some(meta) => Some({
      id,
      changed_at: meta.changed_at,
      verified_at: meta.verified_at,
      durability: meta.durability,
      dependencies: meta.dependencies.copy()
    })
    None => None  // Unused slot
  }
}
```

### Key Design Decisions

1. **Return copies of dependency arrays** - Prevents callers from mutating internal state
2. **Defensive programming** - Handle invalid CellIds gracefully with `Option` return type
3. **No new fields on CellMeta** - All data already exists; this is purely an access layer
4. **Zero runtime cost when not used** - Simple accessor methods with no overhead
5. **CellId already contains Runtime reference** - Per-cell methods automatically use correct Runtime

### Files to Modify

- `signal.mbt` - Add `Signal::id()` and `Signal::durability()`
- `memo.mbt` - Add `Memo::id()`, `Memo::dependencies()`, `Memo::changed_at()`, `Memo::verified_at()`
- `runtime.mbt` - Add `Runtime::cell_info()` and `CellInfo` struct definition
- `cell.mbt` - Possibly export CellId/CellMeta types as needed (if not already public)

## Type Safety & Edge Cases

### CellId Validation

`CellId` structure contains a Runtime reference:
```moonbit
struct CellId {
  runtime : Runtime
  id : Int
}
```

This means:
- Per-cell methods automatically use the correct Runtime
- `Runtime::cell_info(id)` could validate `id.runtime` matches `self` (if MoonBit supports reference equality)
- Cross-runtime confusion is unlikely but could return `None` if detected

### Handling Uncomputed Memos

For a Memo that has never been computed:
- `verified_at` will be `Revision(0)`
- `dependencies` will be `[]`
- `changed_at` will be `Revision(0)`

This is correct behavior - introspection exposes actual state. Documentation will clarify this.

### Concurrency

MoonBit doesn't support threads, so no locks or atomics needed. All introspection is read-only during stable states (between signal updates).

## Testing Strategy

### Unit Tests

**signal_test.mbt:**
- `Signal::id()` returns a valid CellId
- `Signal::durability()` matches construction-time durability
- Multiple signals have distinct IDs

**memo_test.mbt:**
- `Memo::id()` returns a valid CellId
- `Memo::dependencies()` returns correct dependency list after computation
- `Memo::dependencies()` returns `[]` before first computation
- `Memo::changed_at()` and `Memo::verified_at()` track revisions
- Dependencies update when memo recomputes with different inputs

**runtime_test.mbt:**
- `Runtime::cell_info()` returns correct metadata for signals
- `Runtime::cell_info()` returns correct metadata for memos
- `Runtime::cell_info()` returns `None` for out-of-bounds CellId
- `Runtime::cell_info()` returns `None` for unused slots

### Integration Tests

**Debugging scenario - "Why did this recompute?":**
```moonbit
test "debug why memo recomputed" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 10)
  let y = Signal::new(rt, 20)
  let sum = Memo::new(rt, () => x.get() + y.get())

  sum.get() |> ignore
  let initial_verified = sum.verified_at()

  x.set(10)  // Same value - shouldn't change due to backdating
  sum.get() |> ignore
  inspect(sum.verified_at() == initial_verified, content="true")

  y.set(30)  // Different value - should trigger recomputation
  sum.get() |> ignore
  inspect(sum.verified_at() > initial_verified, content="true")

  // Identify which dependency caused recomputation
  for dep in sum.dependencies() {
    match rt.cell_info(dep) {
      Some(info) => {
        if info.changed_at > initial_verified {
          // Found it: y's CellId changed after initial_verified
          inspect(dep == y.id(), content="true")
        }
      }
      None => ()
    }
  }
}
```

**Dynamic dependency tracking:**
```moonbit
test "dependencies update on recomputation" {
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

**Edge cases:**
- Empty dependency list for uncomputed memos
- Deep dependency chains (verify all intermediate memos appear)
- Diamond dependencies (same signal through multiple paths, no duplicates)

## Usage Examples

### Example 1: Understanding Backdating

```moonbit
let config = Signal::new(rt, "prod")
let expensive = Memo::new(rt, () => {
  heavy_computation(config.get())
})

expensive.get() |> ignore
let old_changed_at = expensive.changed_at()

config.set("prod")  // Same value
expensive.get() |> ignore

// Backdating: changed_at didn't advance
inspect(expensive.changed_at() == old_changed_at, content="true")
```

### Example 2: Dependency Analysis

```moonbit
fn analyze_memo_dependencies(rt : Runtime, memo : Memo[Int]) -> Unit {
  println("Memo \{memo.id().id} analysis:")
  println("  Changed at: \{memo.changed_at()}")
  println("  Verified at: \{memo.verified_at()}")
  println("  Dependencies:")

  for dep_id in memo.dependencies() {
    match rt.cell_info(dep_id) {
      Some(info) => {
        println("    - Cell \{info.id.id}: durability=\{info.durability}, changed_at=\{info.changed_at}")
      }
      None => println("    - Cell \{dep_id.id}: (invalid)")
    }
  }
}
```

### Example 3: Testing Assertions

```moonbit
test "memo only depends on x, not y" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 1)
  let y = Signal::new(rt, 2)
  let m = Memo::new(rt, () => x.get() * 2)

  m.get() |> ignore

  let deps = m.dependencies()
  inspect(deps.contains(x.id()), content="true")
  inspect(deps.contains(y.id()), content="false")
}
```

## Documentation Updates

### API Reference

Add new sections:
- "Introspection and Debugging"
- Document all new methods with examples
- Explain `Revision(0)` for uncomputed memos
- Cross-reference with debugging cookbook

### Cookbook

Add recipes:
- "Debugging Why a Memo Recomputed"
- "Analyzing Dependency Chains"
- "Testing Dependency Tracking"
- "Understanding Backdating"

### Design Document

Update `docs/design.md`:
- Note that introspection API is available
- Reference this design doc for rationale

## Migration & Compatibility

This is a pure addition - no breaking changes:
- All new methods, no modifications to existing APIs
- No behavior changes to computation or verification
- Opt-in: only pay cost if you call these methods

## Success Criteria

1. Developers can programmatically answer "why did this memo recompute?"
2. Test assertions can verify dependency tracking correctness
3. Zero performance impact when introspection is not used
4. All 44 existing tests still pass
5. New introspection tests provide >90% coverage of new methods

## Future Work (Out of Scope)

- **Phase 2:** Debug formatting (`Signal::debug()`, `Memo::debug()`)
- **Phase 3:** Graph visualization (DOT format, textual output)
- **Phase 4:** Reverse dependencies (requires subscriber links)
- **Phase 2C:** Cell labels via builder pattern
- **Error diagnostics:** Enhanced `CycleError` with path tracking (separate design)

## References

- [Roadmap Phase 2A](../roadmap.md#phase-2a-introspection--debugging-high-priority)
- [TODO Introspection Tasks](../todo.md#introspection-api-phase-2a---high-priority)
- [API Design Guidelines](../api-design-guidelines.md)
- [Design Document](../design.md)
