# Modularization Design

**Date:** 2026-02-22
**Status:** Approved

## Goal

Split the flat single-package library into MoonBit sub-packages with a clean
"API vs implementation" separation, using `pub typealias` re-exports to
maintain a zero-breaking-change public API from the root `@incr` package.

## Package Structure

```
dowdiness/incr/
├── moon.pkg                       (modify — add types + internal imports)
├── incr.mbt                       (new — pub typealias re-exports)
├── traits.mbt                     (modify — update refs, remove Memo::is_up_to_date)
├── *_test.mbt                     (unchanged — blackbox tests via public API)
│
├── types/                         (new package — zero dependencies)
│   ├── moon.pkg
│   ├── revision.mbt               (Revision, Durability, DURABILITY_COUNT)
│   └── cell_id.mbt                (CellId + Hash impl)
│
├── internal/                      (new package — all engine code)
│   ├── moon.pkg                   (imports types + hashset)
│   ├── cell.mbt                   (CellMeta, CellKind)
│   ├── cycle.mbt                  (CycleError)
│   ├── tracking.mbt               (ActiveQuery)
│   ├── runtime.mbt                (Runtime, CellInfo)
│   ├── verify.mbt                 (maybe_changed_after)
│   ├── signal.mbt                 (Signal[T])
│   ├── memo.mbt                   (Memo[T] + Memo::is_up_to_date)
│   └── *_wbtest.mbt               (whitebox tests — co-located for private access)
│
└── pipeline/                      (new package — zero dependencies)
    ├── moon.pkg
    └── pipeline_traits.mbt        (Sourceable, Parseable, Checkable, Executable)
```

## Package Roles

### `dowdiness/incr/types`

Pure value type definitions with no dependencies. Provides the foundational
types that every other package builds on.

**Contents:** `Revision`, `Durability`, `DURABILITY_COUNT`, `CellId`, `Hash` impl for `CellId`

**`types/moon.pkg`:**
```
import {}
```

### `dowdiness/incr/internal`

All engine implementation. The private internals of the library — cell metadata,
dependency tracking, verification algorithm, and the `Signal`/`Memo` types with
their full implementations including private field access.

**Contents:** `CellMeta`, `CellKind`, `CycleError`, `ActiveQuery`, `Runtime`,
`CellInfo`, `maybe_changed_after`, `Signal[T]`, `Memo[T]`

**`internal/moon.pkg`:**
```
import {
  "dowdiness/incr/types" as @incr_types,
  "moonbitlang/core/hashset",
}
```

All type references to `Revision`, `Durability`, `CellId`, `DURABILITY_COUNT`
become `@incr_types.Revision` etc. throughout internal source files.

### `dowdiness/incr/pipeline`

Experimental pipeline trait definitions. Zero internal dependencies — purely
structural traits that users may optionally implement.

**Contents:** `Sourceable`, `Parseable`, `Checkable`, `Executable`

**`pipeline/moon.pkg`:**
```
import {}
```

### `dowdiness/incr` (root — public API facade)

The public-facing package. Imports from `types` and `internal`, re-exports all
public types via `pub typealias`, and contains the `Database`/`Readable` traits
plus the `create_signal`, `create_memo`, `batch` helper functions.

**`moon.pkg` (modified):**
```
import {
  "dowdiness/incr/types" as @incr_types,
  "dowdiness/incr/internal" as @internal,
  "moonbitlang/core/hashset",
}
```

**`incr.mbt` (new):**
```moonbit
pub typealias Revision = @incr_types.Revision
pub typealias Durability = @incr_types.Durability
pub typealias CellId = @incr_types.CellId
pub typealias Runtime = @internal.Runtime
pub typealias CellInfo = @internal.CellInfo
pub typealias Signal[T] = @internal.Signal[T]
pub typealias Memo[T] = @internal.Memo[T]
pub typealias CycleError = @internal.CycleError
```

## Key Non-Mechanical Change: `Memo::is_up_to_date`

`Memo::is_up_to_date` currently lives in `traits.mbt` but accesses private
fields of `Memo` (`self.value`) and `Runtime` (`self.rt.current_revision`).
It must move to `internal/memo.mbt` where those fields are accessible.

Root `traits.mbt` retains `impl Readable for Memo[T]` but delegates:
```moonbit
pub impl[T] Readable for Memo[T] with is_up_to_date(self) {
  self.is_up_to_date()  // dispatches to @internal.Memo::is_up_to_date
}
```

## File Operations

### Create
| File | Contents |
|------|---------|
| `incr.mbt` | `pub typealias` declarations for all public types |
| `types/moon.pkg` | Empty import block |
| `types/revision.mbt` | `revision.mbt` verbatim |
| `types/cell_id.mbt` | `CellId` struct + `Hash` impl extracted from `cell.mbt` |
| `internal/moon.pkg` | Imports types + hashset |
| `pipeline/moon.pkg` | Empty import block |
| `pipeline/pipeline_traits.mbt` | `pipeline_traits.mbt` verbatim |

### Modify
| File | Change |
|------|--------|
| `moon.pkg` | Add `@incr_types` and `@internal` imports |
| `traits.mbt` | Qualify refs to `@internal.*` / `@incr_types.*`; remove `Memo::is_up_to_date` method body |

### Move + modify (qualify all type refs)
`cell.mbt`, `cycle.mbt`, `tracking.mbt`, `runtime.mbt`, `verify.mbt`,
`signal.mbt`, `memo.mbt` → all move to `internal/` with `@incr_types.*`
qualification for `Revision`, `Durability`, `CellId`, `DURABILITY_COUNT`.
`memo.mbt` also absorbs `Memo::is_up_to_date`.

### Move (verbatim)
All `*_wbtest.mbt` → `internal/`

### Delete from root
`revision.mbt`, `pipeline_traits.mbt` (replaced by sub-package files)

### Unchanged
All `*_test.mbt` blackbox tests — they import the root package and see all
types through `pub typealias` re-exports, requiring no edits.

## Testing

| Test type | Location | Reason |
|-----------|----------|--------|
| `*_wbtest.mbt` | `internal/` | Must be co-located with source for private field access |
| `*_test.mbt` | root | Test via public API; unaffected by internal reorganization |

`moon test` discovers all test packages recursively from the module root, so
the full test suite continues to run with the same command.

## Non-Goals

- Exposing any currently-private types or fields (`CellMeta`, `CellKind`,
  `Runtime` fields, etc.)
- Splitting `Signal`, `Memo`, `Runtime` into separate packages (would require
  making private fields public)
- Changing any public API behavior or method signatures
