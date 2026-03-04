# Design: `on_change?` Optional Parameter for `Runtime::new`

**Date:** 2026-02-22
**Status:** Approved

## Context

Phase 2C added optional parameters (`label?`, `durability?`) to `Signal::new` and `Memo::new`, replacing the planned builder structs. The todo list included `Runtime::with_on_change(self, f) -> Runtime` for method chaining. This design applies the same optional-param pattern to `Runtime::new` instead, for consistency.

## Decision

Add `on_change? : (() -> Unit)` as an optional parameter to `Runtime::new`. Skip `with_on_change` (same treatment as the `SignalBuilder` items in Phase 2C).

## Changes

### `runtime.mbt` — `Runtime::new`

Add `on_change?` parameter:

```moonbit
pub fn Runtime::new(on_change? : (() -> Unit)) -> Runtime {
  ...
  {
    ...
    on_change,
  }
}
```

Update the doc comment example to show both forms:

```moonbit
/// let rt = Runtime::new()
/// let rt = Runtime::new(on_change=() => rerender())
```

### No other runtime changes

`set_on_change` and `clear_on_change` remain as-is for imperative post-construction use.

### `docs/todo.md`

Mark the `with_on_change` item as skipped:

```markdown
- ~~Add `Runtime::with_on_change(self, f) -> Runtime` for method chaining~~ — skipped (replaced by optional param in `Runtime::new`)
```

### Test

One new test in `runtime_test.mbt` (or the appropriate test file) verifying the callback fires when registered via the constructor.

## Non-Goals

- No `with_on_change` chaining method
- No deprecation of `set_on_change`
- No changes to Signal or Memo APIs
