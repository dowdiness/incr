# FunctionalRelation[K, V] Design

**Status:** Complete (PR #21 merged, published as v0.4.1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `FunctionalRelation[K, V]` to incr — a key-value Datalog relation where each key maps to exactly one value. When a key is inserted with a different value, the old value is replaced and the update appears in the delta. This directly models egglog's function tables.

**Architecture:** Follows the same two-layer SoA pattern as `Relation[T]`: type-erased `FunctionalRelationData` with closures, typed `FunctionalRelation[K, V]` wrapper with `@hashmap.HashMap[K, V]` for current/delta/staged_delta. Integrates into the existing `fixpoint()` loop alongside `Relation[T]`. Adds `FunctionalRelation(Int)` variant to `CellRef` and `FunctionalRelationId[K, V]` handle to types. Re-exports via `incr.mbt` using `@internal` and `@incr_types` aliases.

**Tech Stack:** MoonBit, `dowdiness/incr` module

---

## Difference from Relation[T]

| | `Relation[T]` | `FunctionalRelation[K, V]` |
|---|---|---|
| Storage | `@hashset.HashSet[T]` | `@hashmap.HashMap[K, V]` |
| Insert semantics | Set-add (no-op if exists) | Replace value for existing key, produce delta |
| Delta tracking | New elements only | New keys + updated values |
| Use case | Plain Datalog facts | egglog function tables, key-value relations |
| Merge on conflict | N/A (set) | Optional `merge: (V, V) -> V` |
| Read visibility | `contains`/`iter` read only `current` | `get`/`iter` read only `current` |

**Visibility contract (same as `Relation`):** `get()` and `iter()` read only `current` (materialized post-drain). Writes go to `delta` (outside fixpoint) or `staged_delta` (during fixpoint). Values become visible in `current` after `fixpoint()` drains them.

**Effective value resolution for insert dedup:** When checking whether an insert is a no-op, the effective value for a key is resolved in layer priority order:
- Outside fixpoint: `delta` > `current`
- During fixpoint: `staged_delta` > `delta` > `current`

This ensures that two sequential writes `insert(k, 1); insert(k, 2); insert(k, 2)` correctly produce one delta (the first two change, the third is a no-op).

---

## File Structure

| File | Responsibility | Action |
|------|---------------|--------|
| `cells/cell_ref.mbt` | CellRef enum | Modify: add `FunctionalRelation(Int)` |
| `cells/runtime.mbt` | DatalogState, `cell_id_for` exhaustive match | Modify: add `functional_relations` array, add `FunctionalRelation(idx)` match arm |
| `cells/datalog_functional_relation.mbt` | `FunctionalRelationData` + `FunctionalRelation[K, V]` | Create |
| `cells/datalog_fixpoint.mbt` | Fixpoint loop | Modify: drain/promote/check functional_relations alongside relations |
| `cells/verify.mbt` | Pull verification | Modify: add `FunctionalRelation(_)` to fixpoint guard |
| `cells/datalog_rule.mbt` | Rule registration | Modify: accept `FunctionalRelation` in `assert_rule_relation_id` |
| `types/cell_handles.mbt` | Typed ID wrappers | Modify: add `FunctionalRelationId[K, V]` |
| `cells/datalog_functional_relation_wbtest.mbt` | Tests | Create |
| `incr.mbt` | Root re-exports | Modify: add `FunctionalRelation` and `FunctionalRelationId` |
| `pkg.generated.mbti` | Generated interface | Regenerate |

---

## Task 1: Add CellRef variant, handle type, and runtime match arm

**Files:**
- Modify: `cells/cell_ref.mbt`
- Modify: `cells/runtime.mbt` (DatalogState struct + `cell_id_for` match)
- Modify: `types/cell_handles.mbt`

- [ ] **Step 1: Add CellRef variant**

In `cells/cell_ref.mbt`, add after `Rule(Int)`:

```moonbit
  FunctionalRelation(Int)
```

- [ ] **Step 2: Add handle type**

In `types/cell_handles.mbt`, add:

```moonbit
///|
pub(all) struct FunctionalRelationId[K, V] {
  id : CellId
}
```

- [ ] **Step 3: Add functional_relations to DatalogState and update cell_id_for**

In `cells/runtime.mbt`:

Add to `DatalogState` struct:
```moonbit
  functional_relations : Array[FunctionalRelationData]
```

Initialize in `Runtime::new`:
```moonbit
  functional_relations: []
```

Add match arm to `cell_id_for`:
```moonbit
    FunctionalRelation(idx) => self.datalog.functional_relations[idx].meta.cell_id
```

- [ ] **Step 4: Update new_rule validation to accept FunctionalRelation**

In `cells/datalog_rule.mbt`, update `assert_rule_relation_id` match to accept both variants:

```moonbit
match self.core.cell_index[id.id] {
  Relation(_) | FunctionalRelation(_) => ()
  _ => abort(...)
}
```

This must happen before any test calls `new_rule` with a `FunctionalRelation` cell ID.

- [ ] **Step 5: Verify build**

Run: `moon check`
Expected: pass (FunctionalRelationData not yet defined — may need a stub or this task combines with Task 2)

- [ ] **Step 6: Commit**

```bash
git add cells/cell_ref.mbt cells/runtime.mbt cells/datalog_rule.mbt types/cell_handles.mbt
git commit -m "feat(datalog): add FunctionalRelation CellRef variant, handle type, runtime and rule support"
```

---

## Task 2: Implement FunctionalRelation[K, V]

**Files:**
- Create: `cells/datalog_functional_relation.mbt`
- Create: `cells/datalog_functional_relation_wbtest.mbt`

- [ ] **Step 1: Write the failing tests**

In `cells/datalog_functional_relation_wbtest.mbt`:

```moonbit
///|
test "functional_relation: insert and get after fixpoint" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let is_new = fr.insert("x", 1)
  inspect(is_new, content="true")
  // get reads only current — empty before fixpoint
  inspect(fr.get("x"), content="None")
  rt.fixpoint()
  // After fixpoint, current has the value
  inspect(fr.get("x"), content="Some(1)")
}

///|
test "functional_relation: insert same key with different value replaces" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let _ = fr.insert("x", 1)
  let changed = fr.insert("x", 2)
  inspect(changed, content="true")
  rt.fixpoint()
  inspect(fr.get("x"), content="Some(2)")
}

///|
test "functional_relation: insert same key with same value is no-op" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let _ = fr.insert("x", 1)
  let changed = fr.insert("x", 1)
  inspect(changed, content="false")
}

///|
test "functional_relation: effective value checked across layers" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let _ = fr.insert("x", 1)
  // delta has x=1, inserting x=1 again should be no-op
  let dup = fr.insert("x", 1)
  inspect(dup, content="false")
  // inserting x=2 should change (different from delta value)
  let changed = fr.insert("x", 2)
  inspect(changed, content="true")
  // inserting x=2 again should be no-op (matches delta)
  let dup2 = fr.insert("x", 2)
  inspect(dup2, content="false")
}

///|
test "functional_relation: merge function resolves conflicts" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(
    rt,
    merge=fn(a, b) { if a > b { a } else { b } },
  )
  let _ = fr.insert("x", 10)
  rt.fixpoint()
  // current has x=10; insert x=20 should merge to 20
  let changed = fr.insert("x", 20)
  inspect(changed, content="true")
  rt.fixpoint()
  inspect(fr.get("x"), content="Some(20)")
  // Merge with smaller value: resolves to 20 (same as current), no-op
  let changed2 = fr.insert("x", 5)
  inspect(changed2, content="false")
}

///|
test "functional_relation: delta_iter shows new and updated entries" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let _ = fr.insert("x", 1)
  let _ = fr.insert("y", 2)
  let delta_count = fr.delta_iter().fold(init=0, fn(acc, _) { acc + 1 })
  inspect(delta_count, content="2")
}

///|
test "functional_relation: iter reads current after fixpoint" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let _ = fr.insert("x", 1)
  // Before fixpoint, current is empty
  let before = fr.iter().fold(init=0, fn(acc, _) { acc + 1 })
  inspect(before, content="0")
  rt.fixpoint()
  let after = fr.iter().fold(init=0, fn(acc, _) { acc + 1 })
  inspect(after, content="1")
}

///|
test "functional_relation: value update produces delta in next fixpoint" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let _ = fr.insert("x", 1)
  rt.fixpoint()
  // Update value for existing key — goes to delta
  let changed = fr.insert("x", 2)
  inspect(changed, content="true")
  let delta_entries : Array[(String, Int)] = []
  for entry in fr.delta_iter() {
    delta_entries.push(entry)
  }
  inspect(delta_entries.length(), content="1")
}

///|
test "functional_relation: no-op convergence terminates" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let _ = fr.insert("x", 1)
  // Rule that reinserts same value — should not produce new staged delta
  let _ = rt.new_rule([fr.id()], [fr.id()], fn() {
    for entry in fr.delta_iter() {
      let (k, v) = entry
      let _ = fr.insert(k, v) // no-op, same value
    }
  })
  rt.fixpoint() // must not loop forever
  inspect(fr.get("x"), content="Some(1)")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f datalog_functional_relation_wbtest.mbt`
Expected: FAIL — `FunctionalRelation` not defined

- [ ] **Step 3: Write implementation**

In `cells/datalog_functional_relation.mbt`:

```moonbit
///|
/// Type-erased storage for one functional relation.
struct FunctionalRelationData {
  meta : CellMeta
  drain_delta : () -> Unit
  is_delta_empty : () -> Bool
  promote_staged_delta : () -> Unit
  is_staged_delta_empty : () -> Bool
}

///|
impl HasCellMeta for FunctionalRelationData with meta(self) {
  self.meta
}

///|
impl CellOps for FunctionalRelationData

///|
/// A Datalog functional relation: a key-value mapping with delta tracking.
///
/// Unlike `Relation[T]` (a set), `FunctionalRelation[K, V]` maps each key
/// to exactly one value. Inserting with an existing key replaces the value
/// and produces a delta entry. An optional merge function resolves conflicts.
///
/// Three layers (same contract as `Relation`):
/// - `current`: materialized post-drain mapping (readable via `iter()`, `get()`)
/// - `delta`: frontier of new/updated entries for this fixpoint iteration
/// - `staged_delta`: entries inserted during fixpoint (promoted to delta next round)
pub(all) struct FunctionalRelation[K, V] {
  priv rt : Runtime
  priv cell_id : CellId
  priv current : Ref[@hashmap.HashMap[K, V]]
  priv delta : Ref[@hashmap.HashMap[K, V]]
  priv staged_delta : Ref[@hashmap.HashMap[K, V]]
  priv merge : ((V, V) -> V)?

  fn[K : Hash + Eq, V : Eq] new(
    rt : Runtime,
    merge? : ((V, V) -> V)?,
    label? : String,
  ) -> FunctionalRelation[K, V]
}

///|
pub fn[K : Hash + Eq, V : Eq] FunctionalRelation::new(
  rt : Runtime,
  merge? : ((V, V) -> V)? = None,
  label? : String,
) -> FunctionalRelation[K, V] {
  let idx = rt.datalog.functional_relations.length()
  let cell_id = rt.alloc_cell_id(FunctionalRelation(idx))
  let current : Ref[@hashmap.HashMap[K, V]] = { val: @hashmap.new() }
  let delta : Ref[@hashmap.HashMap[K, V]] = { val: @hashmap.new() }
  let staged_delta : Ref[@hashmap.HashMap[K, V]] = { val: @hashmap.new() }
  let data : FunctionalRelationData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
    },
    drain_delta: fn() {
      delta.val.each(fn(k, v) { current.val.set(k, v) })
    },
    is_delta_empty: fn() { delta.val.is_empty() },
    promote_staged_delta: fn() {
      let previous_frontier = delta.val
      delta.val = staged_delta.val
      staged_delta.val = previous_frontier
      staged_delta.val.clear()
    },
    is_staged_delta_empty: fn() { staged_delta.val.is_empty() },
  }
  rt.datalog.functional_relations.push(data)
  let ops : &CellOps = rt.datalog.functional_relations[idx]
  rt.core.cell_ops.push(ops)
  { rt, cell_id, current, delta, staged_delta, merge }
}

///|
pub fn[K, V] FunctionalRelation::id(
  self : FunctionalRelation[K, V],
) -> CellId {
  self.cell_id
}

///|
/// Resolve the effective value for a key across all layers.
///
/// Layer priority: staged_delta > delta > current (during fixpoint)
///                 delta > current (outside fixpoint)
fn[K : Hash + Eq, V] FunctionalRelation::effective_value(
  self : FunctionalRelation[K, V],
  key : K,
) -> V? {
  if self.rt.datalog.in_fixpoint {
    match self.staged_delta.val.get(key) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  match self.delta.val.get(key) {
    Some(v) => Some(v)
    None => self.current.val.get(key)
  }
}

///|
/// Insert or update a key-value entry.
///
/// Returns `true` if the effective mapping changed (new key or different value).
/// Checks the effective value across all layers before deciding.
pub fn[K : Hash + Eq, V : Eq] FunctionalRelation::insert(
  self : FunctionalRelation[K, V],
  key : K,
  value : V,
) -> Bool {
  // Resolve the effective current value across all layers
  let effective = self.effective_value(key)
  // Apply merge if there is an existing value and a merge function
  let resolved = match effective {
    Some(old) =>
      match self.merge {
        Some(f) => {
          let merged = f(old, value)
          if merged == old {
            return false
          }
          merged
        }
        None =>
          if old == value {
            return false
          } else {
            value
          }
      }
    None => value
  }
  // Insert into appropriate layer
  if self.rt.datalog.in_fixpoint {
    self.staged_delta.val.set(key, resolved)
  } else {
    self.delta.val.set(key, resolved)
  }
  true
}

///|
/// Look up the current value for a key.
///
/// Reads only `current` (post-drain). Records a dependency for
/// pull verification.
pub fn[K : Hash + Eq, V] FunctionalRelation::get(
  self : FunctionalRelation[K, V],
  key : K,
) -> V? {
  self.record_read_dependency()
  self.current.val.get(key)
}

///|
/// Iterate over all current (materialized) key-value pairs.
/// Records a dependency for pull verification.
pub fn[K, V] FunctionalRelation::iter(
  self : FunctionalRelation[K, V],
) -> Iter[(K, V)] {
  self.record_read_dependency()
  self.current.val.iter()
}

///|
/// Iterate over delta entries (new/updated since last drain).
/// Used by rule bodies in fixpoint evaluation.
pub fn[K, V] FunctionalRelation::delta_iter(
  self : FunctionalRelation[K, V],
) -> Iter[(K, V)] {
  self.delta.val.iter()
}

///|
fn[K, V] FunctionalRelation::record_read_dependency(
  self : FunctionalRelation[K, V],
) -> Unit {
  let active_rt = current_computing_runtime_id.val
  if active_rt >= 0 && active_rt != self.rt.core.runtime_id {
    current_computing_runtime_id.val = -1
    abort(
      "Cross-runtime dependency: FunctionalRelation belongs to Runtime " +
      self.rt.core.runtime_id.to_string() +
      " but is read inside a computation on Runtime " +
      active_rt.to_string(),
    )
  }
  self.rt.record_dependency(self.cell_id)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/incr/cells -f datalog_functional_relation_wbtest.mbt`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add cells/datalog_functional_relation.mbt cells/datalog_functional_relation_wbtest.mbt
git commit -m "feat(datalog): implement FunctionalRelation[K, V] with delta tracking"
```

---

## Task 3: Integrate into fixpoint loop

**Files:**
- Modify: `cells/datalog_fixpoint.mbt`
- Modify: `cells/datalog_functional_relation_wbtest.mbt`

- [ ] **Step 1: Write the failing test**

Add to `cells/datalog_functional_relation_wbtest.mbt`:

```moonbit
///|
test "functional_relation: fixpoint with rule derives new entries" {
  let rt = Runtime::new()
  let input : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let output : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let _ = input.insert("a", 1)
  let _ = input.insert("b", 2)
  let _ = rt.new_rule([input.id()], [output.id()], fn() {
    for entry in input.delta_iter() {
      let (k, v) = entry
      let _ = output.insert(k, v * 10)
    }
  })
  rt.fixpoint()
  inspect(output.get("a"), content="Some(10)")
  inspect(output.get("b"), content="Some(20)")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f datalog_functional_relation_wbtest.mbt`
Expected: FAIL — fixpoint doesn't process functional_relations yet

- [ ] **Step 3: Update fixpoint loop**

In `cells/datalog_fixpoint.mbt`, add `functional_relations` processing alongside `relations` at each phase:

1. **Initial changed tracking** (after line 24): also iterate `self.datalog.functional_relations` and push `not(fr.is_delta_empty())`
2. **Drain delta** (after line 33): loop `self.datalog.functional_relations` and call `drain_delta()`
3. **Extend changed** (after line 41): extend for new functional_relations too
4. **Check convergence** (after line 51): also check `functional_relations[i].is_staged_delta_empty`
5. **Promote staged** (after line 58): also promote functional_relations
6. **Collect changed IDs** (after line 72): also collect from functional_relations

Use **two separate** `changed` arrays — `changed_relations: Array[Bool]` and `changed_functional_relations: Array[Bool]` — not one flat array with an offset. A single flat array is unsafe because `relations.length()` can grow mid-fixpoint if a rule creates a new `Relation`, shifting the functional_relation offset. Separate arrays avoid this misalignment.

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/incr/cells -f datalog_functional_relation_wbtest.mbt`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `moon test`
Expected: all existing + new tests pass

- [ ] **Step 6: Commit**

```bash
git add cells/datalog_fixpoint.mbt cells/datalog_functional_relation_wbtest.mbt
git commit -m "feat(datalog): integrate FunctionalRelation into fixpoint loop"
```

---

## Task 4: Update verify.mbt and add edge-case tests

**Files:**
- Modify: `cells/verify.mbt`
- Modify: `cells/datalog_functional_relation_wbtest.mbt`

- [ ] **Step 1: Add FunctionalRelation to fixpoint guard in verify.mbt**

Add `FunctionalRelation(_)` alongside `Relation(_) | Rule(_)` in both guard locations (lines ~83 and ~127):

```moonbit
Relation(_) | Rule(_) | FunctionalRelation(_) => { ... }
```

- [ ] **Step 2: Add edge-case tests**

```moonbit
///|
test "functional_relation: memo recomputes after fixpoint changes value" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let _ = fr.insert("x", 1)
  rt.fixpoint()
  let m = Memo::new(rt, fn() { fr.get("x").or(0) })
  inspect(m.get(), content="1")
  let _ = fr.insert("x", 2)
  rt.fixpoint()
  inspect(m.get(), content="2")
}

///|
test "panic functional_relation: cross-runtime read aborts" {
  let rt1 = Runtime::new()
  let rt2 = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt1)
  let _ = fr.insert("x", 1)
  rt1.fixpoint()
  let memo = Memo::new(rt2, fn() { fr.get("x").or(0) })
  let _ = memo.get() // triggers record_read_dependency → cross-runtime abort
}

///|
test "functional_relation: mixed Relation and FunctionalRelation rule" {
  let rt = Runtime::new()
  let edges : Relation[(Int, Int)] = Relation::new(rt)
  let weights : FunctionalRelation[(Int, Int), Int] = FunctionalRelation::new(rt)
  let _ = edges.insert((1, 2))
  let _ = rt.new_rule([edges.id()], [weights.id()], fn() {
    for e in edges.delta_iter() {
      let _ = weights.insert(e, 1)
    }
  })
  rt.fixpoint()
  inspect(weights.get((1, 2)), content="Some(1)")
}

///|
test "functional_relation: created during rule execution converges" {
  let rt = Runtime::new()
  let trigger : Relation[Int] = Relation::new(rt)
  let _ = trigger.insert(1)
  let mut dynamic_fr : FunctionalRelation[Int, Int]? = None
  let _ = rt.new_rule([trigger.id()], [], fn() {
    for _ in trigger.delta_iter() {
      let fr : FunctionalRelation[Int, Int] = FunctionalRelation::new(rt)
      let _ = fr.insert(1, 42)
      dynamic_fr = Some(fr)
    }
  })
  rt.fixpoint()
  match dynamic_fr {
    Some(fr) => inspect(fr.get(1), content="Some(42)")
    None => abort("dynamic fr not created")
  }
}

///|
test "functional_relation: multiple writes to same key in one fixpoint iteration" {
  let rt = Runtime::new()
  let fr : FunctionalRelation[String, Int] = FunctionalRelation::new(rt)
  let _ = fr.insert("x", 1)
  let _ = rt.new_rule([fr.id()], [fr.id()], fn() {
    for entry in fr.delta_iter() {
      let (k, v) = entry
      if v < 10 {
        let _ = fr.insert(k, v + 1)
      }
    }
  })
  rt.fixpoint()
  inspect(fr.get("x"), content="Some(10)")
}
```

- [ ] **Step 4: Run full test suite**

Run: `moon test`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add cells/verify.mbt cells/datalog_functional_relation_wbtest.mbt
git commit -m "feat(datalog): integrate FunctionalRelation into verify, add edge-case tests"
```

---

## Task 5: Add re-exports, regenerate interfaces, update changelog

**Files:**
- Modify: `incr.mbt` (root re-exports using `@internal` and `@incr_types` aliases)
- Regenerate: `pkg.generated.mbti`, `cells/pkg.generated.mbti`, `types/pkg.generated.mbti`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add re-exports in incr.mbt**

In `incr.mbt`, add to the `@internal` block:

```moonbit
  type FunctionalRelation,
```

Add to the `@incr_types` block:

```moonbit
  type FunctionalRelationId,
```

- [ ] **Step 2: Regenerate interfaces and format**

Run: `moon info && moon fmt`

- [ ] **Step 3: Run full test suite**

Run: `moon test`
Expected: all pass

- [ ] **Step 4: Update CHANGELOG.md**

Add to `[Unreleased]` section:

```markdown
### Added
- **FunctionalRelation[K, V]** — key-value Datalog relation with delta tracking for value updates. Unlike `Relation[T]` (set semantics), `FunctionalRelation` maps each key to one value; updates produce deltas. Optional merge function resolves conflicts.
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(datalog): add FunctionalRelation to public API, update changelog"
```

---

## Key Invariants

1. **`Relation[T]` unchanged**: zero modifications to existing Relation behavior or tests
2. **Same fixpoint loop**: FunctionalRelation participates in the same drain → apply → promote cycle
3. **Visibility contract matches Relation**: `get()`/`iter()` read only `current`; writes go to `delta`/`staged_delta`
4. **Effective value dedup**: insert checks `staged_delta > delta > current` priority to avoid false positives
5. **Value updates produce deltas**: inserting key K with value V2 when effective value is V1 (V1 != V2) produces a delta
6. **Merge semantics**: optional `merge(old, new) -> resolved`; if resolved == old, no delta produced
7. **Same safety guarantees**: cross-runtime detection, fixpoint guard in verify, batch abort
