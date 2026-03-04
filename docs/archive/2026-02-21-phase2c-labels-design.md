# Phase 2C: Cell Labels via Optional Parameters — Design

**Date:** 2026-02-21
**Status:** Approved

## Problem

The current API has two ergonomic gaps:

1. **Two constructors for Signal** — `Signal::new` and `Signal::new_with_durability` solve the same problem differently with no clean extension point for future options.
2. **Anonymous cells** — Debug output and cycle errors show `Cell[0] → Cell[1]` instead of `price → tax`. The `format_cell` function in `cycle.mbt` already threads `rt` through "for future use"; labels plug in there.

## Decision

Use MoonBit's native optional parameter syntax (`label? : String`, `~durability : Durability = Low`) instead of a builder pattern. Optional params are the idiomatic MoonBit solution — no new types, backward compatible, and they also allow unifying the two Signal constructors into one.

## Section 1: Constructor API

### Signal

```moonbit
// Before: two constructors
pub fn[T] Signal::new(rt, initial) -> Signal[T]
pub fn[T] Signal::new_with_durability(rt, initial, durability) -> Signal[T]

// After: one unified constructor
pub fn[T] Signal::new(
  rt : Runtime,
  initial : T,
  ~durability : Durability = Low,
  label? : String,
) -> Signal[T]
```

All existing call sites remain valid:

```moonbit
Signal::new(rt, 0)                               // unchanged
Signal::new(rt, "prod", durability=High)         // replaces new_with_durability
Signal::new(rt, 0, label="count")               // new capability
Signal::new(rt, 0, durability=High, label="cfg") // new capability
```

### Memo

```moonbit
pub fn[T : Eq] Memo::new(
  rt : Runtime,
  compute : () -> T,
  label? : String,
) -> Memo[T]
```

### Database helpers

```moonbit
// Before: two helpers
pub fn create_signal(db, value) -> Signal[T]
pub fn create_signal_durable(db, value, durability) -> Signal[T]

// After: unified helpers with optional params
pub fn create_signal(db, value, ~durability : Durability = Low, label? : String) -> Signal[T]
pub fn create_memo(db, f, label? : String) -> Memo[T]
```

## Section 2: Data Model

### Signal[T] and Memo[T] structs

Add `label : String?` field so the existing `derive(Debug(...))` picks it up automatically:

```moonbit
pub(all) struct Signal[T] {
  priv label : String?     // new — appears in Debug output
  priv rt : Runtime
  priv cell_id : CellId
  priv mut value : T
  priv mut pending_value : T?
  priv durability : Durability
} derive(Debug(ignore=[Runtime, CellId]))
// Debug: Signal { label: Some("count"), value: 42 }

pub(all) struct Memo[T] {
  priv label : String?     // new — appears in Debug output
  priv rt : Runtime
  priv cell_id : CellId
  priv compute : () -> T
  priv mut value : T?
} derive(Debug(ignore=[Runtime, Fn, CellId]))
```

### CellMeta

```moonbit
priv struct CellMeta {
  mut label : String?      // new — used by format_path and CellInfo
  // ... existing fields unchanged
}
```

Label is passed through `CellMeta::new_input` and `CellMeta::new_derived`.

### CellInfo

```moonbit
pub(all) struct CellInfo {
  label : String?          // new — exposed to introspection callers
  id : CellId
  changed_at : Revision
  verified_at : Revision
  durability : Durability
  dependencies : Array[CellId]
}
```

Label is stored in both `Signal[T]`/`Memo[T]` (for `derive(Debug)`) and `CellMeta` (for `format_path`, `CellInfo`). The duplication is harmless — label is write-once at construction time.

## Section 3: Debug Output and format_path

`format_cell` in `cycle.mbt` already accepts `rt` with a comment saying it is "for future use". Labels plug in there:

```moonbit
// Before
fn format_cell(_rt : Runtime, cell_id : CellId) -> String {
  "Cell[" + cell_id.id.to_string() + "]"
}

// After
fn format_cell(rt : Runtime, cell_id : CellId) -> String {
  match rt.cell_info(cell_id) {
    Some({ label: Some(l), .. }) => l
    _ => "Cell[" + cell_id.id.to_string() + "]"
  }
}
```

Cycle error output before and after:

```
// Before
Cycle detected: Cell[0] → Cell[1] → Cell[0]

// After (all labeled)
Cycle detected: price → tax → price

// After (mixed — unlabeled cells fall back gracefully)
Cycle detected: Cell[0] → tax → price
```

The `Debug` trait output from `derive(Debug)` covers the debug string case automatically once `label` is a struct field — no separate `debug()` method needed.

## Section 4: Deprecation

| Removed | Replacement |
|---------|-------------|
| `Signal::new_with_durability` | `Signal::new(rt, v, durability=High)` |
| `create_signal_durable` | `create_signal(db, v, durability=High)` |

Both functions have no external users at v0.3.0. Direct removal — no deprecation shim required.

## Files Affected

| File | Change |
|------|--------|
| `signal.mbt` | Unify constructors, add `label` field to struct |
| `memo.mbt` | Add `label?` param, add `label` field to struct |
| `cell.mbt` | Add `label : String?` to `CellMeta`, update `new_input`/`new_derived` |
| `runtime.mbt` | Add `label` to `CellInfo`, expose in `cell_info()` |
| `cycle.mbt` | Update `format_cell` to use label from `rt.cell_info()` |
| `traits.mbt` | Unify `create_signal`/`create_signal_durable`, update `create_memo` |
| Test files | Update any tests constructing cells with `new_with_durability` or `create_signal_durable` |

## Non-Goals

- Builder pattern (`SignalBuilder[T]`) — replaced entirely by optional params
- `Runtime::with_on_change` method chaining — deferred (minimal value)
- `signal()`/`memo()` function aliases — skipped (name collision risk)
