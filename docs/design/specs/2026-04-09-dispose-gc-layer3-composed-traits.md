# Layer 3: Composed Traits Design Spec

**Status:** Approved

**Goal:** Refactor cell lifecycle operations into trait-dispatched architecture, preparing for Layer 4 (Observer + gc) without changing user-visible behavior.

**Depends on:** Layer 1 (manual dispose), Layer 2 (Scope)

## Architecture Decision: Combined Approach

The original design spec proposed 3 new traits with 3 new parallel arrays. After analysis, we adopted a combined approach:

- **Extend `CellOps`** with `gc_role()` and `gc_dependencies()` — read-only metadata, fits existing trait
- **One new `CellLifecycle` trait** combining `dispose_cell`, `on_observe`, `on_unobserve` — all need Runtime
- **One new `cell_lifecycle` array** in RuntimeCore

Result: 3 total arrays (2 existing + 1 new) instead of 5. One new push per creation site instead of three.

## New Types

### GcRole Enum (types/ package)

```moonbit
pub enum GcRole {
  Source    // signals, relations — no upstream deps
  Interior // memos, reactives — has deps, collectible
  Root     // effects — terminal, keeps upstream alive
}
```

Pure value type, zero dependencies. Lives in `types/` alongside Revision, Durability, CellId.

### CellLifecycle Trait (cells/ package)

```moonbit
trait CellLifecycle {
  dispose_cell(Self, Runtime, CellId) -> Unit
  on_observe(Self, Runtime, CellId) -> Unit
  on_unobserve(Self, Runtime, CellId) -> Unit
}
```

All `on_observe`/`on_unobserve` impls are no-ops in Layer 3. Layer 4 fills them in for HybridMemo and PushReactive (push activation/suspension).

## CellOps Extensions

Two new methods with defaults:

```moonbit
trait CellOps {
  // ... existing 9 methods ...
  gc_role(Self) -> GcRole            // default: Source
  gc_dependencies(Self) -> Array[CellId]  // default: []
}
```

### Overrides Per Cell Type

| Cell type | gc_role | gc_dependencies |
|-----------|---------|-----------------|
| PullSignalData | `Source` (default) | `[]` (default) |
| MemoData | `Interior` | `self.dependencies` |
| PushReactiveData | `Interior` | `self.sources` |
| PushEffectData | `Root` | `self.sources` |
| RelationData | `Source` (default) | `[]` (default) |
| FunctionalRelationData | `Source` (default) | `[]` (default) |
| RuleData | `Source` | `self.input_relations` mapped to CellIds |

Only 4 types need overrides. Signals, Relations, and FunctionalRelations use defaults.

## CellLifecycle Implementations

Each `dispose_cell` impl takes the body of the existing `Runtime::dispose_*` method. The `guard_dispose` check moves to the common dispatch path in `Runtime::dispose_cell`.

| Cell type | dispose_cell | on_observe | on_unobserve |
|-----------|-------------|------------|--------------|
| PullSignalData | existing `dispose_signal` body | no-op | no-op |
| MemoData | existing `dispose_memo` body | no-op (Layer 4: hybrid push activate) | no-op (Layer 4: hybrid push suspend) |
| PushReactiveData | existing `dispose_reactive` body | no-op (Layer 4: push activate) | no-op (Layer 4: push suspend) |
| PushEffectData | existing `dispose_effect` body | no-op | no-op |
| RelationData | existing `dispose_relation` body | no-op | no-op |
| FunctionalRelationData | existing `dispose_functional_relation` body | no-op | no-op |
| RuleData | existing `dispose_rule` body | no-op | no-op |

## MemoData: is_hybrid Flag

```moonbit
priv struct MemoData {
  // existing fields...
  is_hybrid : Bool  // new — set at creation, immutable
}
```

- Set to `false` in `Memo::_create`
- Set to `true` in `HybridMemo::_create`
- Not read in Layer 3 (all observe methods are no-ops)
- Required so `CellLifecycle` impl can distinguish PullMemo from HybridMemo in Layer 4

## RuntimeCore Changes

```moonbit
priv struct RuntimeCore {
  // existing
  cell_index : Array[CellRef]
  cell_ops : Array[&CellOps]

  // new
  cell_lifecycle : Array[&CellLifecycle]
}
```

All three arrays share the same index (`CellId.id`). Populated together at cell creation from the same SoA data struct.

## Dispatch Simplification

### Before (8-arm CellRef match)

```moonbit
pub fn Runtime::dispose_cell(self, cell_id) {
  guard runtime_id ...
  guard !is_cell_disposed ...
  match self.core.cell_index[cell_id.id] {
    PullSignal(_) => self.dispose_signal(cell_id)
    PullMemo(_) | HybridMemo(_) => self.dispose_memo(cell_id)
    PushReactive(_) => self.dispose_reactive(cell_id)
    // ... 5 more arms
  }
}
```

### After (trait dispatch)

```moonbit
pub fn Runtime::dispose_cell(self, cell_id) {
  guard runtime_id ...
  guard !is_cell_disposed ...
  self.guard_dispose(cell_id)
  self.core.cell_lifecycle[cell_id.id].dispose_cell(self, cell_id)
}
```

## Migration of Existing Dispose Methods

Existing `Runtime::dispose_signal`, `dispose_memo`, etc.:
- Their bodies move into `CellLifecycle::dispose_cell` impls on each SoA data struct
- The `guard_dispose` call moves to the common `Runtime::dispose_cell` dispatcher
- The typed methods either become thin wrappers calling `dispose_cell`, or are removed
- `dispose_rule` (public, takes RuleId) remains as a forwarding wrapper

## Cell Creation Sites

8 creation sites each add one line:

```moonbit
let lifecycle : &CellLifecycle = rt.pull.signals[idx]
rt.core.cell_lifecycle.push(lifecycle)
```

## What Layer 3 Does NOT Include

- No observer logic (on_observe/on_unobserve are all no-ops)
- No gc() implementation
- No suspension state machine
- No new public API — internal refactoring only
- No behavioral changes — all 410 existing tests pass unchanged

## Testing Strategy

- All existing tests pass unchanged (pure refactoring)
- New whitebox test: verify `is_hybrid` flag set correctly on Memo vs HybridMemo
- New test: verify `gc_role()` returns correct role per cell type
- New test: verify `gc_dependencies()` returns correct deps per cell type
- Benchmark regression check: re-run Layer 1 + 2 benchmarks to verify trait dispatch overhead is negligible
