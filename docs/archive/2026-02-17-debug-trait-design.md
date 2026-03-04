# Debug Trait Implementation Design

**Date:** 2026-02-17
**Status:** Approved

## Overview

Implement the `Debug` trait on `Signal[T]` and `Memo[T]` using MoonBit's
`derive(Debug(ignore=[...]))` syntax. This completes the Phase 2A introspection
API by giving users a standard way to inspect cell state during development.

## What Changes

### 1. `CellId` — add `Debug` to existing derive

```moonbit
} derive(Eq, Show, Debug)
```

`CellId` is used as a field in both `Signal` and `Memo`, so it needs `Debug`
before either struct can derive it.

### 2. `Signal[T]` — add `derive(Debug(ignore=[Runtime]))`

```moonbit
pub(all) struct Signal[T] {
  priv rt : Runtime
  priv cell_id : CellId
  priv mut value : T
  priv mut pending_value : T?
  priv durability : Durability
} derive(Debug(ignore=[Runtime]))
```

`Runtime` has no `Debug` implementation and is shown as `...`. All other fields
(`CellId`, `T`, `T?`, `Durability`) implement `Debug`. The generated impl
requires `T : Debug`.

Expected output:
```
{
  rt: ...,
  cell_id: { runtime_id: 0, id: 0 },
  value: 42,
  pending_value: None,
  durability: Low,
}
```

### 3. `Memo[T]` — add `derive(Debug(ignore=[Runtime, Fn]))`

```moonbit
pub(all) struct Memo[T] {
  priv rt : Runtime
  priv cell_id : CellId
  priv compute : () -> T
  priv mut value : T?
} derive(Debug(ignore=[Runtime, Fn]))
```

Both `Runtime` and the `compute : () -> T` function field are non-debuggable
and shown as `...`. The generated impl requires `T : Debug`.

Expected output:
```
{
  rt: ...,
  cell_id: { runtime_id: 0, id: 1 },
  compute: ...,
  value: Some(84),
}
```

## What Is Not Shown

`changed_at`, `verified_at`, and `dependencies` live in `CellMeta` inside the
runtime, not in the struct fields. They are not visible in the `Debug` output.
Users who need that information already have the introspection methods:
`Memo::changed_at()`, `Memo::verified_at()`, `Memo::dependencies()`.

## Testing

Tests use `debug_inspect` with `#|` multiline string literals:

```moonbit
test "Signal derives Debug" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 42)
  debug_inspect(
    s,
    content=(
      #|{
      #|  rt: ...,
      #|  cell_id: { runtime_id: 0, id: 0 },
      #|  value: 42,
      #|  pending_value: None,
      #|  durability: Low,
      #|}
    ),
  )
}

test "Memo derives Debug" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let m = Memo::new(rt, () => s.get() * 2)
  let _ = m.get()
  debug_inspect(
    m,
    content=(
      #|{
      #|  rt: ...,
      #|  cell_id: { runtime_id: 0, id: 1 },
      #|  compute: ...,
      #|  value: Some(20),
      #|}
    ),
  )
}
```

## Files Changed

| File | Change |
|------|--------|
| `cell.mbt` | Add `Debug` to `CellId` derive |
| `signal.mbt` | Add `derive(Debug(ignore=[Runtime]))` to `Signal[T]` |
| `memo.mbt` | Add `derive(Debug(ignore=[Runtime, Fn]))` to `Memo[T]` |
| `debug_test.mbt` | New file with `debug_inspect` tests |

## Todo Items Completed

From `docs/todo.md` (Introspection API section):
- `Add Signal::debug(self) -> String for formatted output`
- `Add Memo::debug(self) -> String for formatted output`

(Implemented as `Debug` trait instead of explicit `debug()` method, which is
the idiomatic MoonBit 0.8.0 approach.)
