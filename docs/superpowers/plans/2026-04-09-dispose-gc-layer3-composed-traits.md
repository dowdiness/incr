# Layer 3: Composed Traits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor cell lifecycle operations into trait-dispatched architecture (CellLifecycle trait + CellOps gc extensions), preparing for Layer 4 without changing user-visible behavior.

**Architecture:** Extend `CellOps` with `gc_role()`/`gc_dependencies()` (read-only metadata). Add one new `CellLifecycle` trait combining `dispose_cell`/`on_observe`/`on_unobserve`. Add one new `cell_lifecycle` array in RuntimeCore. Migrate existing `Runtime::dispose_*` method bodies into `CellLifecycle` impls on each SoA data struct. Add `is_hybrid` flag to MemoData.

**Tech Stack:** MoonBit, incr framework (types + cells packages)

---

### Task 1: GcRole Enum

**Files:**
- Modify: `types/revision.mbt` (append — this file already contains Durability enum, a natural home for GcRole)
- Modify: `types/cell_handles.mbt` (no change needed — GcRole is independent)
- Test: `cells/cell_ops_wbtest.mbt` (create — whitebox test for gc_role/gc_dependencies)

**Context:** GcRole is a pure value type with three variants. It lives in `types/` because it's referenced by CellOps (which is in `cells/`) and will be referenced by gc() in Layer 4. The `types/` package has zero dependencies, keeping the dependency graph clean.

- [ ] **Step 1: Add GcRole enum to types/revision.mbt**

Append to the end of `types/revision.mbt`:

```moonbit
///|
/// Categorizes a cell's role in garbage collection.
///
/// - `Source`: Input cells (signals, relations) — no upstream deps, never collected
/// - `Interior`: Derived cells (memos, reactives) — has deps, collectible when unobserved
/// - `Root`: Terminal cells (effects) — keeps upstream alive, never collected
pub enum GcRole {
  Source
  Interior
  Root
} derive(Debug, Eq)
```

- [ ] **Step 2: Re-export GcRole in incr.mbt**

In `incr.mbt`, add `type GcRole` to the `@incr_types` using block:

```moonbit
pub using @incr_types {
  type Revision,
  type Durability,
  type CellId,
  type SignalId,
  type MemoId,
  type ReactiveId,
  type RelationId,
  type RuleId,
  type FunctionalRelationId,
  DURABILITY_COUNT,
  trait HasChangedAt,
  trait BackdateEq,
  type GcRole,
}
```

- [ ] **Step 3: Run moon check**

Run: `moon check`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add types/revision.mbt incr.mbt
git commit -m "feat(types): add GcRole enum for gc categorization"
```

---

### Task 2: Extend CellOps with gc_role and gc_dependencies

**Files:**
- Modify: `cells/cell_ops.mbt` (add 2 methods with defaults)
- Modify: `cells/pull_memo.mbt` (override gc_role + gc_dependencies for MemoData)
- Modify: `cells/push_reactive.mbt` (override gc_role + gc_dependencies for PushReactiveData)
- Modify: `cells/push_effect.mbt` (override gc_role + gc_dependencies for PushEffectData)
- Modify: `cells/datalog_rule.mbt` (override gc_role for RuleData)
- Test: `cells/cell_ops_wbtest.mbt` (create — whitebox tests)

**Context:** CellOps is the read-only interface for cell metadata. gc_role and gc_dependencies are read-only metadata that fit naturally here. Default impls return `Source` and `[]` — correct for PullSignalData, RelationData, and FunctionalRelationData. Only 4 types need overrides.

Note: `cells/cell.mbt` contains `using @incr_types` which brings types from the types/ package. The `GcRole` enum added in Task 1 is available via this import.

- [ ] **Step 1: Write whitebox tests**

Create `cells/cell_ops_wbtest.mbt`:

```moonbit
///|
test "gc_role: signal is Source" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let ops : &CellOps = rt.pull.signals[0]
  inspect(ops.gc_role(), content="Source")
  sig.dispose()
}

///|
test "gc_role: memo is Interior" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() })
  let ops : &CellOps = rt.pull.memos[0]
  inspect(ops.gc_role(), content="Interior")
  m.dispose()
  sig.dispose()
}

///|
test "gc_role: reactive is Interior" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let r : Reactive[Int] = Reactive::new(rt, fn() { sig.get() })
  let ops : &CellOps = rt.push.reactives[0]
  inspect(ops.gc_role(), content="Interior")
  r.dispose()
  sig.dispose()
}

///|
test "gc_role: effect is Root" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let eff = Effect::new(rt, fn() { ignore(sig.get()) })
  let ops : &CellOps = rt.push.effects[0]
  inspect(ops.gc_role(), content="Root")
  eff.dispose()
  sig.dispose()
}

///|
test "gc_dependencies: signal has empty deps" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let ops : &CellOps = rt.pull.signals[0]
  inspect(ops.gc_dependencies().length(), content="0")
  sig.dispose()
}

///|
test "gc_dependencies: memo returns its dependencies" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() })
  let _ = m.get() // trigger compute to populate dependencies
  let ops : &CellOps = rt.pull.memos[0]
  let deps = ops.gc_dependencies()
  inspect(deps.length(), content="1")
  inspect(deps[0] == sig.id(), content="true")
  m.dispose()
  sig.dispose()
}

///|
test "gc_dependencies: effect returns its sources" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let eff = Effect::new(rt, fn() { ignore(sig.get()) })
  let ops : &CellOps = rt.push.effects[0]
  let deps = ops.gc_dependencies()
  inspect(deps.length(), content="1")
  inspect(deps[0] == sig.id(), content="true")
  eff.dispose()
  sig.dispose()
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f cell_ops_wbtest.mbt`
Expected: FAIL — `gc_role` and `gc_dependencies` not defined on CellOps.

- [ ] **Step 3: Add default methods to CellOps**

In `cells/cell_ops.mbt`, add to the `CellOps` trait definition (after the `push_reachable_count` method, before the closing `}`):

```moonbit
  /// Returns this cell's GC role. Default: Source (input cells).
  /// Override for Interior (memos, reactives) and Root (effects).
  gc_role(Self) -> GcRole = _

  /// Returns this cell's upstream dependencies for GC marking.
  /// Default: empty (leaf cells). Override for cells with dependencies.
  gc_dependencies(Self) -> Array[CellId] = _
```

Add default implementations after the existing `push_reachable_count` default impl:

```moonbit
///|
/// Default: Source role (signals, relations — no upstream deps, never collected).
impl CellOps with gc_role(_self) -> GcRole {
  Source
}

///|
/// Default: no dependencies (leaf cells).
impl CellOps with gc_dependencies(_self) -> Array[CellId] {
  []
}
```

- [ ] **Step 4: Add MemoData overrides**

Append to `cells/pull_memo.mbt` after the existing `dep_changed_since` override:

```moonbit
///|
impl CellOps for MemoData with gc_role(_self) -> GcRole {
  Interior
}

///|
impl CellOps for MemoData with gc_dependencies(self) -> Array[CellId] {
  self.dependencies
}
```

- [ ] **Step 5: Add PushReactiveData overrides**

Append to `cells/push_reactive.mbt` after the existing CellOps impls:

```moonbit
///|
impl CellOps for PushReactiveData with gc_role(_self) -> GcRole {
  Interior
}

///|
impl CellOps for PushReactiveData with gc_dependencies(self) -> Array[CellId] {
  self.sources
}
```

- [ ] **Step 6: Add PushEffectData overrides**

Append to `cells/push_effect.mbt` after the existing CellOps impls:

```moonbit
///|
impl CellOps for PushEffectData with gc_role(_self) -> GcRole {
  Root
}

///|
impl CellOps for PushEffectData with gc_dependencies(self) -> Array[CellId] {
  self.sources
}
```

- [ ] **Step 7: Add RuleData override**

Append to `cells/datalog_rule.mbt` after the existing CellOps impl:

```moonbit
///|
impl CellOps for RuleData with gc_role(_self) -> GcRole {
  Source
}
```

Note: RuleData's `input_relations` are already CellIds, but rules are Sources (they generate facts, not derived from upstream in the GC sense). `gc_dependencies` default `[]` is correct.

- [ ] **Step 8: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f cell_ops_wbtest.mbt`
Expected: PASS

- [ ] **Step 9: Run moon check and full test suite**

Run: `moon check && moon test`
Expected: No errors, all tests pass

- [ ] **Step 10: Commit**

```bash
git add cells/cell_ops.mbt cells/pull_memo.mbt cells/push_reactive.mbt cells/push_effect.mbt cells/datalog_rule.mbt cells/cell_ops_wbtest.mbt
git commit -m "feat(cells): extend CellOps with gc_role and gc_dependencies"
```

---

### Task 3: CellLifecycle Trait and is_hybrid Flag

**Files:**
- Modify: `cells/cell_ops.mbt` (append CellLifecycle trait)
- Modify: `cells/pull_memo.mbt` (add `is_hybrid` field to MemoData)
- Modify: `cells/memo.mbt` (set `is_hybrid = false` in `_create`)
- Modify: `cells/hybrid_memo.mbt` (set `is_hybrid = true` in `_create`)
- Test: `cells/cell_ops_wbtest.mbt` (append is_hybrid tests)

**Context:** CellLifecycle combines dispose, observe, and unobserve into a single trait requiring Runtime. All on_observe/on_unobserve impls are no-ops in Layer 3. The `is_hybrid` flag on MemoData is needed so the trait impl can distinguish PullMemo from HybridMemo in Layer 4. The trait lives in `cell_ops.mbt` alongside `CellOps` since both define cell dispatch interfaces.

- [ ] **Step 1: Write failing test for is_hybrid**

Append to `cells/cell_ops_wbtest.mbt`:

```moonbit
///|
test "is_hybrid: memo has is_hybrid false" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let m = Memo::new(rt, fn() { sig.get() })
  inspect(rt.pull.memos[0].is_hybrid, content="false")
  m.dispose()
  sig.dispose()
}

///|
test "is_hybrid: hybrid memo has is_hybrid true" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let hm = HybridMemo::new(rt, fn() { sig.get() })
  inspect(rt.pull.memos[0].is_hybrid, content="true")
  hm.dispose()
  sig.dispose()
}
```

- [ ] **Step 2: Add CellLifecycle trait to cell_ops.mbt**

Append to `cells/cell_ops.mbt` (after the `RevisionManager` trait):

```moonbit
///|
/// Lifecycle operations for cells: disposal, observer notifications.
///
/// Unlike CellOps (read-only metadata), CellLifecycle methods perform
/// mutations and require Runtime access. Stored as `&CellLifecycle` in
/// `RuntimeCore.cell_lifecycle`, indexed by `CellId.id`.
///
/// # Layer 3 status
///
/// `dispose_cell` migrates existing dispose logic into trait impls.
/// `on_observe` and `on_unobserve` are no-ops — Layer 4 fills them in
/// for HybridMemo (push activation/suspension) and PushReactive.
priv trait CellLifecycle {
  dispose_cell(Self, Runtime, CellId) -> Unit
  on_observe(Self, Runtime, CellId) -> Unit
  on_unobserve(Self, Runtime, CellId) -> Unit
}

///|
/// Default: on_observe is a no-op. Layer 4 overrides for push cells.
impl CellLifecycle with on_observe(_self, _rt, _cell_id) -> Unit {
  ()
}

///|
/// Default: on_unobserve is a no-op. Layer 4 overrides for push cells.
impl CellLifecycle with on_unobserve(_self, _rt, _cell_id) -> Unit {
  ()
}
```

Note: `dispose_cell` has no default — every cell type must provide an impl.

- [ ] **Step 3: Add is_hybrid flag to MemoData**

In `cells/pull_memo.mbt`, add `is_hybrid` to the MemoData struct:

```moonbit
priv struct MemoData {
  meta : CellMeta
  compute : () -> Result[Bool, CycleError]
  mut verified_at : Revision
  mut dependencies : Array[CellId]
  mut in_progress : Bool
  mut on_change : (() -> Unit)?
  is_hybrid : Bool
}
```

- [ ] **Step 4: Set is_hybrid in Memo::_create**

In `cells/memo.mbt`, find the `MemoData` struct literal in `Memo::_create` and add `is_hybrid: false`. The struct literal is around line 55-68. Add the field:

```moonbit
  let new_data : MemoData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
      push_reachable_count: 0,
    },
    compute: () => { Err(CycleError("uninitialized")) },
    verified_at: Revision::initial(),
    dependencies: [],
    in_progress: false,
    on_change: None,
    is_hybrid: false,
  }
```

- [ ] **Step 5: Set is_hybrid in HybridMemo::_create**

In `cells/hybrid_memo.mbt`, find the `MemoData` struct literal in `HybridMemo::_create` and add `is_hybrid: true`. The struct literal is around line 38-53. Add the field:

```moonbit
  let new_data : MemoData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
      push_reachable_count: 0,
    },
    compute: () => { Err(CycleError("uninitialized")) },
    verified_at: Revision::initial(),
    dependencies: [],
    in_progress: false,
    on_change: None,
    is_hybrid: true,
  }
```

- [ ] **Step 6: Run moon check**

Run: `moon check`
Expected: No errors

- [ ] **Step 7: Run tests**

Run: `moon test -p dowdiness/incr/cells -f cell_ops_wbtest.mbt`
Expected: PASS (including new is_hybrid tests)

- [ ] **Step 8: Commit**

```bash
git add cells/cell_ops.mbt cells/pull_memo.mbt cells/memo.mbt cells/hybrid_memo.mbt cells/cell_ops_wbtest.mbt
git commit -m "feat(cells): add CellLifecycle trait and is_hybrid flag on MemoData"
```

---

### Task 4: CellLifecycle Impls — Migrate Dispose Logic

**Files:**
- Modify: `cells/pull_signal.mbt` (add CellLifecycle impl for PullSignalData)
- Modify: `cells/pull_memo.mbt` (add CellLifecycle impl for MemoData)
- Modify: `cells/push_reactive.mbt` (add CellLifecycle impl for PushReactiveData)
- Modify: `cells/push_effect.mbt` (add CellLifecycle impl for PushEffectData)
- Modify: `cells/datalog_relation.mbt` (add CellLifecycle impl for RelationData)
- Modify: `cells/datalog_functional_relation.mbt` (add CellLifecycle impl for FunctionalRelationData)
- Modify: `cells/datalog_rule.mbt` (add CellLifecycle impl for RuleData)

**Context:** Each CellLifecycle::dispose_cell impl takes the body of the corresponding `Runtime::dispose_*` method. Key differences from the Runtime methods:
- No `is_cell_disposed` guard (handled by caller `Runtime::dispose_cell`)
- No `guard_dispose` call (handled by caller `Runtime::dispose_cell`)
- No `CellRef` match (the trait dispatch already resolved the type)
- Receives `Runtime` as a parameter for `remove_subscriber`, `remove_batch_signal`, free list access

The `on_observe` and `on_unobserve` methods use the default no-op impl for all types.

- [ ] **Step 1: Add PullSignalData CellLifecycle impl**

Append to `cells/pull_signal.mbt`:

```moonbit
///|
impl CellLifecycle for PullSignalData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  if rt.core.batch_depth > 0 {
    rt.remove_batch_signal(cell_id)
  }
  self.meta.subscribers.clear()
  self.meta.label = None
  self.on_change = None
  self.commit_pending = None
  rt.core.cell_index[cell_id.id] = Disposed
  match rt.core.cell_index[cell_id.id] {
    _ => ()
  }
  // Find the SoA index for free list
  for i in 0..<rt.pull.signals.length() {
    if rt.pull.signals[i].meta.cell_id == cell_id {
      rt.pull.free_signals.push(i)
      break
    }
  }
}
```

Wait — this approach has a problem. The dispose methods in `Runtime` use the `CellRef` variant to get the SoA index (e.g., `PullSignal(idx)`), but the CellLifecycle impl receives `self` which IS the SoA data, not the index. We need a way to find the index.

Actually, looking more carefully at the existing code: `dispose_signal` does `match self.core.cell_index[cell_id.id] { PullSignal(idx) => ... }`. The CellLifecycle impl can do the same thing since it receives both `Runtime` and `CellId`.

Let me rewrite:

```moonbit
///|
impl CellLifecycle for PullSignalData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  match rt.core.cell_index[cell_id.id] {
    PullSignal(idx) => {
      if rt.core.batch_depth > 0 {
        rt.remove_batch_signal(cell_id)
      }
      self.meta.subscribers.clear()
      self.meta.label = None
      self.on_change = None
      self.commit_pending = None
      rt.core.cell_index[cell_id.id] = Disposed
      rt.pull.free_signals.push(idx)
    }
    _ => ()
  }
}
```

- [ ] **Step 2: Add MemoData CellLifecycle impl**

Append to `cells/pull_memo.mbt`:

```moonbit
///|
impl CellLifecycle for MemoData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  match rt.core.cell_index[cell_id.id] {
    PullMemo(idx) | HybridMemo(idx) => {
      for dep in self.dependencies {
        rt.remove_subscriber(dep, cell_id)
      }
      self.dependencies = []
      self.meta.subscribers.clear()
      self.meta.label = None
      self.on_change = None
      self.verified_at = Revision::initial()
      self.in_progress = false
      rt.core.cell_index[cell_id.id] = Disposed
      rt.pull.free_memos.push(idx)
    }
    _ => ()
  }
}
```

- [ ] **Step 3: Add PushReactiveData CellLifecycle impl**

Append to `cells/push_reactive.mbt`:

```moonbit
///|
impl CellLifecycle for PushReactiveData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  match rt.core.cell_index[cell_id.id] {
    PushReactive(idx) => {
      for dep in self.sources {
        rt.remove_subscriber(dep, cell_id)
      }
      rt.core.cell_index[cell_id.id] = Disposed
      self.clear_slot()
      rt.push.free_reactives.push(idx)
      rt.push.node_count = rt.push.node_count - 1
    }
    _ => ()
  }
}
```

- [ ] **Step 4: Add PushEffectData CellLifecycle impl**

Append to `cells/push_effect.mbt`:

```moonbit
///|
impl CellLifecycle for PushEffectData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  match rt.core.cell_index[cell_id.id] {
    PushEffect(idx) => {
      for dep in self.sources {
        rt.remove_subscriber(dep, cell_id)
      }
      rt.core.cell_index[cell_id.id] = Disposed
      self.clear_slot()
      rt.push.free_effects.push(idx)
      rt.push.node_count = rt.push.node_count - 1
    }
    _ => ()
  }
}
```

- [ ] **Step 5: Add RelationData CellLifecycle impl**

Append to `cells/datalog_relation.mbt`:

```moonbit
///|
impl CellLifecycle for RelationData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  self.meta.subscribers.clear()
  self.meta.label = None
  rt.core.cell_index[cell_id.id] = Disposed
}
```

- [ ] **Step 6: Add FunctionalRelationData CellLifecycle impl**

Append to `cells/datalog_functional_relation.mbt`:

```moonbit
///|
impl CellLifecycle for FunctionalRelationData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  self.meta.subscribers.clear()
  self.meta.label = None
  rt.core.cell_index[cell_id.id] = Disposed
}
```

- [ ] **Step 7: Add RuleData CellLifecycle impl**

Append to `cells/datalog_rule.mbt`:

```moonbit
///|
impl CellLifecycle for RuleData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
  self.meta.subscribers.clear()
  self.meta.label = None
  rt.core.cell_index[cell_id.id] = Disposed
}
```

- [ ] **Step 8: Run moon check**

Run: `moon check`
Expected: No errors (impls exist but aren't called yet)

- [ ] **Step 9: Commit**

```bash
git add cells/pull_signal.mbt cells/pull_memo.mbt cells/push_reactive.mbt cells/push_effect.mbt cells/datalog_relation.mbt cells/datalog_functional_relation.mbt cells/datalog_rule.mbt
git commit -m "feat(cells): add CellLifecycle dispose impls for all cell types"
```

---

### Task 5: RuntimeCore cell_lifecycle Array and Creation Sites

**Files:**
- Modify: `cells/runtime.mbt` (add `cell_lifecycle` to RuntimeCore + Runtime::new + alloc_cell_id)
- Modify: `cells/memo.mbt` (add cell_lifecycle.push in `_create`)
- Modify: `cells/hybrid_memo.mbt` (add cell_lifecycle.push in `_create`)
- Modify: `cells/push_reactive.mbt` (add cell_lifecycle.push in `Reactive::new`)
- Modify: `cells/push_effect.mbt` (add cell_lifecycle.push in `Effect::new`)
- Modify: `cells/datalog_relation.mbt` (add cell_lifecycle.push in `Relation::new`)
- Modify: `cells/datalog_functional_relation.mbt` (add cell_lifecycle.push)
- Modify: `cells/datalog_rule.mbt` (add cell_lifecycle.push in `new_rule`)

**Context:** The `cell_lifecycle` array mirrors `cell_ops` — same index (`CellId.id`), populated at creation from the same SoA data struct. Each creation site already has a `cell_ops.push(ops)` line; add a matching `cell_lifecycle.push(lifecycle)` immediately after.

- [ ] **Step 1: Add cell_lifecycle to RuntimeCore**

In `cells/runtime.mbt`, add `cell_lifecycle` field to `RuntimeCore` struct (after `cell_ops`):

```moonbit
  cell_ops : Array[&CellOps]
  cell_lifecycle : Array[&CellLifecycle]
```

- [ ] **Step 2: Initialize cell_lifecycle in Runtime::new**

In `cells/runtime.mbt`, find the RuntimeCore initialization in `Runtime::new` (around line 130) and add `cell_lifecycle: []` to the struct literal.

- [ ] **Step 3: Add cell_lifecycle.push to signal creation**

In `cells/runtime.mbt`, after `rt.core.cell_ops.push(ops)` in `alloc_signal` (around line 248), add:

```moonbit
  let lifecycle : &CellLifecycle = self.pull.signals[signal_idx]
  self.core.cell_lifecycle.push(lifecycle)
```

- [ ] **Step 4: Add cell_lifecycle.push to Memo::_create**

In `cells/memo.mbt`, after `rt.core.cell_ops.push(ops)` (around line 75), add:

```moonbit
  let lifecycle : &CellLifecycle = rt.pull.memos[memo_idx]
  rt.core.cell_lifecycle.push(lifecycle)
```

- [ ] **Step 5: Add cell_lifecycle.push to HybridMemo::_create**

In `cells/hybrid_memo.mbt`, after `rt.core.cell_ops.push(ops)` (around line 59), add:

```moonbit
  let lifecycle : &CellLifecycle = rt.pull.memos[memo_idx]
  rt.core.cell_lifecycle.push(lifecycle)
```

- [ ] **Step 6: Add cell_lifecycle.push to Reactive::new**

In `cells/push_reactive.mbt`, after `rt.core.cell_ops.push(ops)` (around line 117), add:

```moonbit
  let lifecycle : &CellLifecycle = rt.push.reactives[reactive_idx]
  rt.core.cell_lifecycle.push(lifecycle)
```

- [ ] **Step 7: Add cell_lifecycle.push to Effect::new**

In `cells/push_effect.mbt`, after `rt.core.cell_ops.push(ops)` (around line 108), add:

```moonbit
  let lifecycle : &CellLifecycle = rt.push.effects[effect_idx]
  rt.core.cell_lifecycle.push(lifecycle)
```

- [ ] **Step 8: Add cell_lifecycle.push to Relation::new**

In `cells/datalog_relation.mbt`, after `rt.core.cell_ops.push(ops)` (around line 75), add:

```moonbit
  let lifecycle : &CellLifecycle = rt.datalog.relations[idx]
  rt.core.cell_lifecycle.push(lifecycle)
```

- [ ] **Step 9: Add cell_lifecycle.push to FunctionalRelation::new**

In `cells/datalog_functional_relation.mbt`, after `rt.core.cell_ops.push(ops)` (around line 82), add:

```moonbit
  let lifecycle : &CellLifecycle = rt.datalog.functional_relations[idx]
  rt.core.cell_lifecycle.push(lifecycle)
```

- [ ] **Step 10: Add cell_lifecycle.push to Runtime::new_rule**

In `cells/datalog_rule.mbt`, after `self.core.cell_ops.push(ops)` (around line 49), add:

```moonbit
  let lifecycle : &CellLifecycle = self.datalog.rules[idx]
  self.core.cell_lifecycle.push(lifecycle)
```

- [ ] **Step 11: Run moon check and full test suite**

Run: `moon check && moon test`
Expected: No errors, all tests pass (array is populated but not yet used for dispatch)

- [ ] **Step 12: Commit**

```bash
git add cells/runtime.mbt cells/memo.mbt cells/hybrid_memo.mbt cells/push_reactive.mbt cells/push_effect.mbt cells/datalog_relation.mbt cells/datalog_functional_relation.mbt cells/datalog_rule.mbt
git commit -m "feat(cells): add cell_lifecycle array and populate at all creation sites"
```

---

### Task 6: Switch dispose_cell to Trait Dispatch

**Files:**
- Modify: `cells/runtime.mbt` (rewrite `dispose_cell`, remove old `dispose_*` methods)

**Context:** This is the payoff — `dispose_cell` becomes 4 lines of trait dispatch. The old `Runtime::dispose_signal`, `dispose_memo`, etc. methods are removed since their logic now lives in CellLifecycle impls. `guard_dispose` is called once in `dispose_cell` instead of repeated in each method.

`dispose_rule` remains as a public forwarding wrapper (it takes `RuleId`, not `CellId`, and is called directly by users).

Each typed cell type (Signal, Memo, etc.) has its own `dispose()` method that calls `rt.dispose_cell(self.cell_id)` or `rt.dispose_TYPE(cell_id)`. These need to be updated to call `dispose_cell` instead.

- [ ] **Step 1: Check which typed dispose methods call which Runtime methods**

Before modifying, verify which `*.dispose()` methods call which `Runtime::dispose_*` methods:

Run: `grep -n 'dispose_signal\|dispose_memo\|dispose_reactive\|dispose_effect\|dispose_relation\|dispose_functional_relation' cells/*.mbt`

Expected callers:
- `Signal::dispose` → `self.rt.dispose_signal(self.cell_id)`
- `Memo::dispose` → `self.rt.dispose_memo(self.cell_id)`
- `HybridMemo::dispose` → `self.rt.dispose_memo(self.cell_id)`
- `Reactive::dispose` → `self.rt.dispose_reactive(self.cell_id)`
- `Effect::dispose` → `self.rt.dispose_effect(self.cell_id)`
- `Relation::dispose` → `self.rt.dispose_relation(self.cell_id)`
- `FunctionalRelation::dispose` → `self.rt.dispose_functional_relation(self.cell_id)`
- `TrackedCell::dispose` → `self.signal.dispose()` (delegates to Signal)

- [ ] **Step 2: Update typed dispose methods to use dispose_cell**

Update each typed wrapper's `dispose()` to call `self.rt.dispose_cell(self.cell_id)` instead of the typed method. For example, in `cells/signal.mbt`:

```moonbit
pub fn[T] Signal::dispose(self : Signal[T]) -> Unit {
  self.rt.dispose_cell(self.cell_id)
}
```

Apply the same change to: `Memo::dispose`, `HybridMemo::dispose`, `Reactive::dispose`, `Effect::dispose`, `Relation::dispose`, `FunctionalRelation::dispose`.

`TrackedCell::dispose` already delegates to `self.signal.dispose()` — no change needed.

- [ ] **Step 3: Rewrite Runtime::dispose_cell**

Replace the existing `dispose_cell` (lines 773-794) with:

```moonbit
///|
/// Disposes a cell by CellId, dispatching via CellLifecycle trait.
///
/// Validates runtime ownership, checks idempotency, and calls guard_dispose
/// before dispatching to the type-specific dispose implementation.
pub fn Runtime::dispose_cell(self : Runtime, cell_id : CellId) -> Unit {
  guard cell_id.runtime_id == self.core.runtime_id else {
    abort("dispose_cell: CellId belongs to a different Runtime")
  }
  guard !self.is_cell_disposed(cell_id) else { return }
  self.guard_dispose(cell_id)
  self.core.cell_lifecycle[cell_id.id].dispose_cell(self, cell_id)
}
```

- [ ] **Step 4: Update dispose_rule to forward to dispose_cell**

Replace the body of `Runtime::dispose_rule` (keep the public signature for API compat):

```moonbit
pub fn Runtime::dispose_rule(
  self : Runtime,
  rule_id : @incr_types.RuleId,
) -> Unit {
  self.dispose_cell(rule_id.id)
}
```

- [ ] **Step 5: Remove old Runtime::dispose_* methods**

Delete the following methods from `cells/runtime.mbt`:
- `Runtime::dispose_signal` (lines 622-643)
- `Runtime::dispose_memo` (lines 645-668)
- `Runtime::dispose_reactive` (lines 670-689)
- `Runtime::dispose_effect` (lines 691-709)
- `Runtime::dispose_relation` (lines 711-727)
- `Runtime::dispose_functional_relation` (lines 729-747)

Keep `Runtime::guard_dispose` (lines 611-620) — it's still called by `dispose_cell`.

- [ ] **Step 6: Run moon check**

Run: `moon check`
Expected: No errors. If any callers still reference the deleted methods, fix them.

- [ ] **Step 7: Run full test suite**

Run: `moon test`
Expected: All 410+ tests pass — behavior is identical.

- [ ] **Step 8: Commit**

```bash
git add cells/runtime.mbt cells/signal.mbt cells/memo.mbt cells/hybrid_memo.mbt cells/push_reactive.mbt cells/push_effect.mbt cells/datalog_relation.mbt cells/datalog_functional_relation.mbt
git commit -m "refactor(dispose): switch to CellLifecycle trait dispatch, remove old dispose methods"
```

---

### Task 7: Benchmarks, moon info, and Documentation

**Files:**
- Modify: `tests/bench_test.mbt` (no new benchmarks needed — re-run existing)
- Modify: `CLAUDE.md` (update architecture note)
- Run: `moon info && moon fmt`

**Context:** The design spec says "regression check for trait dispatch overhead." We re-run the existing Layer 1 and Layer 2 benchmarks. No new benchmarks needed — the same operations now go through trait dispatch instead of CellRef match, so existing benchmarks already measure the right thing.

- [ ] **Step 1: Run benchmarks**

Run: `moon bench --release`
Expected: No significant regression from Layer 2 baseline. Trait dispatch (one vtable call) should be comparable to CellRef match (one branch).

- [ ] **Step 2: Run moon info and moon fmt**

Run: `moon info && moon fmt`

- [ ] **Step 3: Check API surface**

Run: `git diff *.mbti`
Expected: New entries for `GcRole` enum in types/. `CellLifecycle` is `priv` so it should NOT appear in public `.mbti`. `gc_role` and `gc_dependencies` are on `priv trait CellOps` so they also should NOT appear.

- [ ] **Step 4: Run full test suite one final time**

Run: `moon test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "docs: regenerate .mbti and update architecture for Layer 3 traits"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] GcRole enum in types/ package
- [x] CellOps extended with gc_role() + gc_dependencies() with defaults
- [x] Overrides for MemoData (Interior), PushReactiveData (Interior), PushEffectData (Root), RuleData (Source)
- [x] CellLifecycle trait with dispose_cell + on_observe + on_unobserve
- [x] No-op defaults for on_observe/on_unobserve
- [x] CellLifecycle impls for all 7 cell types (dispose logic migrated)
- [x] is_hybrid flag on MemoData (false for Memo, true for HybridMemo)
- [x] cell_lifecycle array in RuntimeCore
- [x] Populated at all 8 creation sites
- [x] dispose_cell simplified to trait dispatch
- [x] guard_dispose called once in dispose_cell (not repeated per impl)
- [x] dispose_rule preserved as public forwarding wrapper
- [x] Old Runtime::dispose_* methods removed
- [x] Benchmark regression check
- [x] No new public API (internal refactoring only)
- [x] No behavioral changes — all existing tests pass

**Placeholder scan:** None found.

**Type consistency:** `CellLifecycle` used consistently. `GcRole` variants `Source`/`Interior`/`Root` match spec. `is_hybrid` field name consistent across MemoData, Memo::_create, HybridMemo::_create.

**Known risk:** The CellLifecycle impls re-read `cell_index[cell_id.id]` to get the SoA index for free list management. This is the same pattern the old methods used, but it means the trait impl has a slightly indirect path to the data it already has via `self`. This is acceptable because the alternative (storing the SoA index on CellMeta) would change the data layout for all cells.
