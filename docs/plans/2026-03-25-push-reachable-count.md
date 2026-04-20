# Push Reachable Count Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `push_reachable_count` to every cell so `push_propagate_from` can skip BFS entirely for signals with no downstream push cells, and prune dead branches within the BFS.

**Architecture:** `push_reachable_count : Int` lives on `CellMeta`, maintained via hooks in `add_subscriber`/`remove_subscriber` using a `push_contribution` helper that weights by the subscriber's own count. `collect_reachable_cells` walks upstream through pull deps (and includes non-pull sources as leaf nodes) to find all cells that need adjustment.

**Tech Stack:** MoonBit, `moonbitlang/core/hashset`, existing `CellOps`/`HasCellMeta` trait pattern.

**Spec:** `docs/design/specs/2026-03-25-push-reachable-count-design.md`

---

## File map

| File | Role |
|---|---|
| `cells/cell_ops.mbt` | Add field to `CellMeta`; add method to `CellOps` |
| `cells/runtime.mbt` | Add three helpers; extend `add_subscriber`/`remove_subscriber` |
| `cells/push_propagate.mbt` | Outer gate + inner BFS pruning |
| `cells/push_reachable_wbtest.mbt` *(new)* | All whitebox tests for this feature |
| `cells/push_efficiency_bench_test.mbt` | Existing benchmark — verify improvement |
| 9 constructor sites | Add `push_reachable_count: 0` to `CellMeta` literals |
| `cells/cell_ref_wbtest.mbt` | Existing test — update `PullSignalData` literal |

**Constructor sites to update** (all need `push_reachable_count: 0`):

| File | Line |
|---|---|
| `cells/runtime.mbt` | ~227 (PullSignal meta) |
| `cells/memo.mbt` | ~73 (PullMemo / HybridMemo shared meta) |
| `cells/hybrid_memo.mbt` | ~39 |
| `cells/push_reactive.mbt` | ~98 |
| `cells/push_effect.mbt` | ~89 |
| `cells/datalog_relation.mbt` | ~50 |
| `cells/datalog_functional_relation.mbt` | ~62 |
| `cells/datalog_rule.mbt` | ~35 |
| `cells/cell_ref_wbtest.mbt` | ~5 (test literal — must also update) |

---

## Task 1: Add `push_reachable_count` to `CellMeta` and `CellOps`

**Files:**
- Modify: `cells/cell_ops.mbt`
- Modify: `cells/cell_ref_wbtest.mbt` (existing test literal)
- Modify: all 8 production constructor sites listed above (plus cell_ref_wbtest)

- [ ] **Step 1: Write a failing whitebox test**

Create `cells/push_reachable_wbtest.mbt`:

```moonbit
///|
test "push_reachable_count: new signal starts at 0" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let idx = match rt.core.cell_index[s.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  inspect(rt.pull.signals[idx].meta.push_reachable_count, content="0")
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
# Run from the incr/ directory
moon test -p dowdiness/incr/cells -f push_reachable_wbtest.mbt
```

Expected: compile error — `push_reachable_count` field does not exist on `CellMeta`.

- [ ] **Step 3: Add the field to `CellMeta` in `cells/cell_ops.mbt`**

```moonbit
priv struct CellMeta {
  cell_id : CellId
  mut label : String?
  mut changed_at : Revision
  mut durability : Durability
  subscribers : @hashset.HashSet[CellId]
  mut push_reachable_count : Int   // NEW
}
```

- [ ] **Step 4: Add the method to `CellOps` in `cells/cell_ops.mbt`**

Inside the `trait CellOps: HasCellMeta` block, add after `dep_changed_since`:

```moonbit
  /// Number of subscriber-path routes from this cell to a live push cell.
  /// > 0 iff at least one live push cell (Reactive/Effect) is downstream.
  push_reachable_count(Self) -> Int = _
```

Then add the default impl block (alongside the other `impl CellOps with` blocks):

```moonbit
///|
/// Default: push_reachable_count from shared metadata.
impl CellOps with push_reachable_count(self) -> Int {
  HasCellMeta::meta(self).push_reachable_count
}
```

- [ ] **Step 5: Update all 9 `CellMeta` literal sites** — add `push_reachable_count: 0` after `subscribers: @hashset.new()`:

`cells/runtime.mbt` (~line 227):
```moonbit
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability,
      subscribers: @hashset.new(),
      push_reachable_count: 0,   // NEW
    },
```

`cells/memo.mbt` (~line 73):
```moonbit
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
      push_reachable_count: 0,   // NEW
    },
```

`cells/hybrid_memo.mbt` (~line 39) — same pattern.

`cells/push_reactive.mbt` (~line 98) — same pattern.

`cells/push_effect.mbt` (~line 89) — same pattern.

`cells/datalog_relation.mbt` (~line 50) — same pattern.

`cells/datalog_functional_relation.mbt` (~line 62) — same pattern.

`cells/datalog_rule.mbt` (~line 35) — same pattern.

`cells/cell_ref_wbtest.mbt` (~line 5) — update the test literal too:
```moonbit
    meta: {
      cell_id: id,
      label: None,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
      push_reachable_count: 0,   // NEW
    },
```

- [ ] **Step 6: Run the new test and all existing tests**

```bash
moon test -p dowdiness/incr/cells -f push_reachable_wbtest.mbt
moon test
```

Expected: new test passes; all 323 existing tests pass.

- [ ] **Step 7: Commit**

```bash
git add cells/cell_ops.mbt cells/runtime.mbt cells/memo.mbt cells/hybrid_memo.mbt \
        cells/push_reactive.mbt cells/push_effect.mbt cells/datalog_relation.mbt \
        cells/datalog_functional_relation.mbt cells/datalog_rule.mbt \
        cells/cell_ref_wbtest.mbt cells/push_reachable_wbtest.mbt
git commit -m "feat: add push_reachable_count field to CellMeta and CellOps trait"
```

---

## Task 2: Add `push_contribution`, `collect_reachable_cells`, `adjust_push_reachable` helpers

**Files:**
- Modify: `cells/runtime.mbt`
- Modify: `cells/push_reachable_wbtest.mbt`

- [ ] **Step 1: Write failing tests for the helpers**

Add to `cells/push_reachable_wbtest.mbt`:

```moonbit
///|
test "collect_reachable_cells: signal returns {signal}" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let cells = rt.collect_reachable_cells([s.id()])
  inspect(cells.contains(s.id()), content="true")
  inspect(cells.size(), content="1")
}

///|
test "collect_reachable_cells: memo returns memo + upstream signal" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let m = Memo::new(rt, () => s.get())
  ignore(m.get()) // force compute so dependencies are recorded
  let cells = rt.collect_reachable_cells([m.id()])
  inspect(cells.contains(m.id()), content="true")
  inspect(cells.contains(s.id()), content="true")
  inspect(cells.size(), content="2")
}

///|
test "collect_reachable_cells: uncomputed memo returns only memo" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let m = Memo::new(rt, () => s.get())
  // m.get() NOT called — dependencies array is empty
  let cells = rt.collect_reachable_cells([m.id()])
  inspect(cells.contains(m.id()), content="true")
  inspect(cells.size(), content="1")
}

///|
test "push_contribution: reactive returns 1" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let r = Reactive::new(rt, () => s.get())
  inspect(rt.push_contribution(r.id()), content="1")
}

///|
test "push_contribution: signal returns 0" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  inspect(rt.push_contribution(s.id()), content="0")
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
moon test -p dowdiness/incr/cells -f push_reachable_wbtest.mbt
```

Expected: compile errors — helpers not defined.

- [ ] **Step 3: Implement the three helpers in `cells/runtime.mbt`**

Add after `remove_subscriber` (around line 363):

```moonbit
///|
/// Returns the push-reachable contribution of `sub_id` as a subscriber.
///
/// - `PushReactive` / `PushEffect` → 1 (they are push cells themselves)
/// - `PullMemo` / `HybridMemo` → their current `push_reachable_count`
///   (they propagate their downstream push count upward)
/// - All other variants → 0
fn Runtime::push_contribution(self : Runtime, sub_id : CellId) -> Int {
  if sub_id.id < 0 || sub_id.id >= self.core.cell_index.length() {
    return 0
  }
  match self.core.cell_index[sub_id.id] {
    PushReactive(_) | PushEffect(_) => 1
    PullMemo(i) | HybridMemo(i) => self.pull.memos[i].meta.push_reachable_count
    _ => 0
  }
}

///|
/// Collects all cells reachable upstream of `sources` through the pull
/// dependency graph.
///
/// Rules:
/// - `PullSignal` → add to set, stop (leaf)
/// - `PullMemo` / `HybridMemo` → add to set, recurse into `dependencies`
/// - `PushReactive`, `Relation`, `FunctionalRelation`, `Rule` →
///     add to set, stop (leaf in count-propagation graph; do NOT recurse)
/// - `Disposed` → skip
/// - Already-visited cells are skipped (handles diamond fan-in)
fn Runtime::collect_reachable_cells(
  self : Runtime,
  sources : Array[CellId],
) -> @hashset.HashSet[CellId] {
  let result : @hashset.HashSet[CellId] = @hashset.new()
  let worklist : Array[CellId] = []
  for id in sources {
    worklist.push(id)
  }
  while worklist.length() > 0 {
    let id = worklist.pop().unwrap()
    if result.contains(id) {
      continue
    }
    if id.id < 0 || id.id >= self.core.cell_index.length() {
      continue
    }
    match self.core.cell_index[id.id] {
      Disposed => ()
      PullSignal(_) => result.add(id)
      PushReactive(_) | Relation(_) | FunctionalRelation(_) | Rule(_) =>
        result.add(id) // leaf in the count-propagation walk: add but don't recurse
      PullMemo(i) | HybridMemo(i) => {
        result.add(id)
        for dep in self.pull.memos[i].dependencies {
          worklist.push(dep)
        }
      }
      // PushEffect: effects are terminal leaf nodes — nothing subscribes to them,
      // so they are never passed as `dep` to add_subscriber, and thus never
      // appear as sources in collect_reachable_cells during normal operation.
      // They are excluded from the result set (not added) since their own
      // push_reachable_count is always 0 and they never need adjustment.
      PushEffect(_) => ()
    }
  }
  result
}

///|
/// Adjusts `push_reachable_count` by `delta` on every cell reachable upstream
/// of `sources` (including the sources themselves).
///
/// Uses direct SoA array access to mutate `push_reachable_count` — this is
/// required because `HasCellMeta::meta()` returns `CellMeta` by value, so
/// any mutation through the `&CellOps` trait object would be silently lost.
///
/// Asserts that no count goes negative.
fn Runtime::adjust_push_reachable(
  self : Runtime,
  sources : Array[CellId],
  delta : Int,
) -> Unit {
  let cells = self.collect_reachable_cells(sources)
  for id in cells {
    if id.id < 0 || id.id >= self.core.cell_index.length() {
      continue
    }
    // Route to the correct SoA array and mutate push_reachable_count directly.
    // Do NOT use HasCellMeta::meta() through &CellOps — it returns by value.
    let current = match self.core.cell_index[id.id] {
      PullSignal(i) => self.pull.signals[i].meta.push_reachable_count
      PullMemo(i) | HybridMemo(i) => self.pull.memos[i].meta.push_reachable_count
      PushReactive(i) => self.push.reactives[i].meta.push_reachable_count
      PushEffect(i) => self.push.effects[i].meta.push_reachable_count
      Relation(i) => self.datalog.relations[i].meta.push_reachable_count
      FunctionalRelation(i) =>
        self.datalog.functional_relations[i].meta.push_reachable_count
      Rule(i) => self.datalog.rules[i].meta.push_reachable_count
      Disposed => continue
    }
    let new_count = current + delta
    if new_count < 0 {
      abort(
        "adjust_push_reachable: count went negative for cell " +
        id.id.to_string() +
        " (delta=" +
        delta.to_string() +
        ", was=" +
        current.to_string() +
        ")",
      )
    }
    match self.core.cell_index[id.id] {
      PullSignal(i) => self.pull.signals[i].meta.push_reachable_count = new_count
      PullMemo(i) | HybridMemo(i) =>
        self.pull.memos[i].meta.push_reachable_count = new_count
      PushReactive(i) =>
        self.push.reactives[i].meta.push_reachable_count = new_count
      PushEffect(i) =>
        self.push.effects[i].meta.push_reachable_count = new_count
      Relation(i) =>
        self.datalog.relations[i].meta.push_reachable_count = new_count
      FunctionalRelation(i) =>
        self.datalog.functional_relations[i].meta.push_reachable_count = new_count
      Rule(i) => self.datalog.rules[i].meta.push_reachable_count = new_count
      Disposed => ()
    }
  }
}

- [ ] **Step 4: Run tests**

```bash
moon test -p dowdiness/incr/cells -f push_reachable_wbtest.mbt
moon test
```

Expected: all new tests pass; all 323 existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add cells/runtime.mbt cells/push_reachable_wbtest.mbt
git commit -m "feat: add collect_reachable_cells, adjust_push_reachable, push_contribution helpers"
```

---

## Task 3: Extend `add_subscriber`/`remove_subscriber` with count propagation

**Files:**
- Modify: `cells/runtime.mbt`
- Modify: `cells/push_reachable_wbtest.mbt`

- [ ] **Step 1: Write failing whitebox tests for count maintenance**

Add to `cells/push_reachable_wbtest.mbt`:

```moonbit
///|
/// Helper: read push_reachable_count from any cell via cell_index.
fn get_count(rt : Runtime, id : CellId) -> Int {
  match rt.core.cell_index[id.id] {
    PullSignal(i) => rt.pull.signals[i].meta.push_reachable_count
    PullMemo(i) | HybridMemo(i) => rt.pull.memos[i].meta.push_reachable_count
    PushReactive(i) => rt.push.reactives[i].meta.push_reachable_count
    PushEffect(i) => rt.push.effects[i].meta.push_reachable_count
    Relation(i) => rt.datalog.relations[i].meta.push_reachable_count
    FunctionalRelation(i) =>
      rt.datalog.functional_relations[i].meta.push_reachable_count
    Rule(i) => rt.datalog.rules[i].meta.push_reachable_count
    Disposed => 0
  }
}

///|
test "push_reachable_count: signal with direct reactive counts 1" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let _r = Reactive::new(rt, () => s.get())
  inspect(get_count(rt, s.id()), content="1")
}

///|
test "push_reachable_count: signal with reactive through hybrid memo" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let h = HybridMemo::new(rt, () => s.get())
  let _r = Reactive::new(rt, () => h.get())
  inspect(get_count(rt, s.id()), content="1")
  inspect(get_count(rt, h.id()), content="1")
}

///|
test "push_reachable_count: two-deep memo chain" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let mA = Memo::new(rt, () => s.get())
  let mB = Memo::new(rt, () => mA.get())
  let _r = Reactive::new(rt, () => mB.get())
  inspect(get_count(rt, s.id()), content="1")
  inspect(get_count(rt, mA.id()), content="1")
  inspect(get_count(rt, mB.id()), content="1")
}

///|
test "push_reachable_count: diamond topology" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let mA = Memo::new(rt, () => s.get() + 1)
  let mB = Memo::new(rt, () => s.get() + 2)
  let _r = Reactive::new(rt, () => mA.get() + mB.get())
  // Two paths: s→mA→r and s→mB→r
  inspect(get_count(rt, s.id()), content="2")
  inspect(get_count(rt, mA.id()), content="1")
  inspect(get_count(rt, mB.id()), content="1")
}

///|
test "push_reachable_count: reactive dispose returns counts to 0" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let r = Reactive::new(rt, () => s.get())
  inspect(get_count(rt, s.id()), content="1")
  r.dispose()
  inspect(get_count(rt, s.id()), content="0")
}

///|
test "push_reachable_count: diamond dispose returns to 0" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let mA = Memo::new(rt, () => s.get() + 1)
  let mB = Memo::new(rt, () => s.get() + 2)
  let r = Reactive::new(rt, () => mA.get() + mB.get())
  inspect(get_count(rt, s.id()), content="2")
  r.dispose()
  inspect(get_count(rt, s.id()), content="0")
  inspect(get_count(rt, mA.id()), content="0")
  inspect(get_count(rt, mB.id()), content="0")
}

///|
test "push_reachable_count: relation-to-reactive" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let mut count = 0
  let r = Reactive::new(rt, () => {
    count = count + 1
    rel.iter().fold(init=0, fn(acc, x) { acc + x })
  })
  ignore(r) // r is alive
  inspect(get_count(rt, rel.id()), content="1")
  r.dispose()
  inspect(get_count(rt, rel.id()), content="0")
}

///|
test "push_reachable_count: reactive-to-reactive chain" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let r1 = Reactive::new(rt, () => s.get() + 1)
  let _r2 = Reactive::new(rt, () => r1.get() + 1)
  inspect(get_count(rt, s.id()), content="1")
  inspect(get_count(rt, r1.id()), content="1")
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
moon test -p dowdiness/incr/cells -f push_reachable_wbtest.mbt
```

Expected: tests compile but fail — counts are all 0 because add/remove_subscriber don't propagate yet.

- [ ] **Step 3: Extend `add_subscriber` in `cells/runtime.mbt`**

Replace the current `add_subscriber` body:

```moonbit
///|
/// Adds `subscriber` to the subscriber set of `dep` and propagates the
/// subscriber's push contribution upstream through the pull dep graph.
fn Runtime::add_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  self.validate_cell(dep, "add_subscriber(dep)")
  self.core.cell_ops[dep.id].subscribers().add(subscriber)
  let contribution = self.push_contribution(subscriber)
  if contribution > 0 {
    self.adjust_push_reachable([dep], contribution)
  }
}
```

- [ ] **Step 4: Extend `remove_subscriber` in `cells/runtime.mbt`**

Replace the current `remove_subscriber` body:

```moonbit
///|
/// Removes `subscriber` from the subscriber set of `dep` and decrements the
/// subscriber's push contribution from upstream cells.
///
/// Contribution is computed BEFORE the subscriber's CellRef can be set to
/// Disposed by the caller — this ordering is critical. The subscriber set
/// mutation happens before the adjust call for clarity, but is safe because
/// adjust_push_reachable reads dep-graph structure, not subscriber sets.
fn Runtime::remove_subscriber(
  self : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  self.validate_cell(dep, "remove_subscriber(dep)")
  let contribution = self.push_contribution(subscriber)
  self.core.cell_ops[dep.id].subscribers().remove(subscriber)
  if contribution > 0 {
    self.adjust_push_reachable([dep], -contribution)
  }
}
```

- [ ] **Step 5: Run the tests**

```bash
moon test -p dowdiness/incr/cells -f push_reachable_wbtest.mbt
moon test
```

Expected: all new count-maintenance tests pass; all 323 existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add cells/runtime.mbt cells/push_reachable_wbtest.mbt
git commit -m "feat: propagate push_reachable_count in add_subscriber/remove_subscriber"
```

---

## Task 4: Test memo dep change and HybridMemo dispose

**Files:**
- Modify: `cells/push_reachable_wbtest.mbt`

These tests verify that lazy memo dep changes and HybridMemo disposal correctly update counts. They should pass without any additional code changes if Task 3 is correct.

- [ ] **Step 1: Write tests**

Add to `cells/push_reachable_wbtest.mbt`:

```moonbit
///|
test "push_reachable_count: source change on reactive recompute" {
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 0)
  let s2 = Signal::new(rt, 0)
  // reactive starts reading s1
  let flag = { val: true }
  let r = Reactive::new(rt, () => if flag.val { s1.get() } else { s2.get() })
  inspect(get_count(rt, s1.id()), content="1")
  inspect(get_count(rt, s2.id()), content="0")
  // switch reactive to read s2 by changing flag and triggering recompute
  flag.val = false
  s1.set(1) // triggers push propagation → r recomputes → now reads s2
  inspect(get_count(rt, s1.id()), content="0")
  inspect(get_count(rt, s2.id()), content="1")
}

///|
test "push_reachable_count: memo dep change updates upstream signal counts" {
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 0)
  let s2 = Signal::new(rt, 0)
  let flag = { val: true }
  // memoA conditionally reads s1 or s2
  let mA = Memo::new(rt, () => if flag.val { s1.get() } else { s2.get() })
  // reactive reads memoA (forces memoA to compute → deps=[s1])
  let _r = Reactive::new(rt, () => mA.get())
  inspect(get_count(rt, s1.id()), content="1")
  inspect(get_count(rt, s2.id()), content="0")
  // switch memoA to read s2: change flag, trigger recompute via signal change
  flag.val = false
  s1.set(1) // reactive recomputes → pull_verify memoA → memo_force_recompute → s2 added
  inspect(get_count(rt, s1.id()), content="0")
  inspect(get_count(rt, s2.id()), content="1")
}

///|
test "push_reachable_count: hybrid memo dispose decrements upstream" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let h = HybridMemo::new(rt, () => s.get())
  let _r = Reactive::new(rt, () => h.get())
  inspect(get_count(rt, s.id()), content="1")
  inspect(get_count(rt, h.id()), content="1")
  h.dispose()
  // After h is disposed, s and h should have count 0
  // Note: r is still alive but its source (h) is disposed.
  // h.dispose() removes h from s's subscribers → s.count decrements
  inspect(get_count(rt, s.id()), content="0")
}

///|
test "push_reachable_count: no push cells = zero everywhere" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let _m = Memo::new(rt, () => s.get())
  inspect(get_count(rt, s.id()), content="0")
}
```

- [ ] **Step 2: Run tests**

```bash
moon test -p dowdiness/incr/cells -f push_reachable_wbtest.mbt
moon test
```

Expected: all pass; 323 existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add cells/push_reachable_wbtest.mbt
git commit -m "test: add memo dep change and hybrid dispose count-maintenance tests"
```

---

## Task 5: Outer gate in `enqueue_push_subscribers`

**Files:**
- Modify: `cells/push_propagate.mbt`
- Modify: `cells/push_reachable_wbtest.mbt`

- [ ] **Step 1: Write a failing gate behavioral test**

Add to `cells/push_reachable_wbtest.mbt`:

```moonbit
///|
test "gate: signal with count 0 does not trigger reactive on separate signal" {
  let rt = Runtime::new()
  let s1 = Signal::new(rt, 0)
  let s2 = Signal::new(rt, 0)
  let mut recomputes = 0
  let _r = Reactive::new(rt, () => {
    recomputes = recomputes + 1
    s2.get()
  })
  let initial = recomputes
  // s1 has no downstream push cells (r reads s2, not s1)
  inspect(get_count(rt, s1.id()), content="0")
  // Changing s1 should NOT trigger r to recompute
  s1.set(1)
  inspect(recomputes, content=initial.to_string())
}
```

This test should already pass after Task 3 if the existing `node_count` gate is still active, but it will specifically validate the new per-signal gate works correctly once we replace the outer check.

- [ ] **Step 2: Run existing benchmarks to record baseline**

```bash
moon bench --release -p dowdiness/incr/cells 2>&1 | grep "push efficiency"
```

Record the output — this is the "before" measurement.

- [ ] **Step 3: Add the outer gate to `enqueue_push_subscribers` in `cells/push_propagate.mbt`**

Inside `push_propagate_from`, find the `fn enqueue_push_subscribers(source_id : CellId)` nested closure. Add the gate check at the very top, before the `bfs_worklist.clear()`:

```moonbit
fn enqueue_push_subscribers(source_id : CellId) -> Unit {
  // O(1) gate: skip BFS entirely if no push cell is downstream of this source.
  // push_reachable_count > 0 iff at least one live Reactive/Effect is reachable.
  if source_id.id >= 0 &&
     source_id.id < self.core.cell_ops.length() &&
     self.core.cell_ops[source_id.id].push_reachable_count() == 0 {
    return
  }
  // ... existing BFS code unchanged ...
  bfs_worklist.clear()
  bfs_worklist.push(source_id)
  // ...
}
```

- [ ] **Step 4: Run tests and benchmarks**

```bash
moon test
moon bench --release -p dowdiness/incr/cells 2>&1 | grep "push efficiency"
```

Expected:
- All 323+ tests pass
- The "100 hybrid subs, distant reactive" benchmark drops dramatically (≤ 0.05 µs target)

- [ ] **Step 5: Commit**

```bash
git add cells/push_propagate.mbt cells/push_reachable_wbtest.mbt
git commit -m "perf: add outer push_reachable_count gate in enqueue_push_subscribers"
```

---

## Task 6: Inner BFS pruning

**Files:**
- Modify: `cells/push_propagate.mbt`
- Modify: `cells/push_reachable_wbtest.mbt`

- [ ] **Step 1: Write inner pruning test (count-correctness proxy)**

Add to `cells/push_reachable_wbtest.mbt`:

```moonbit
///|
/// Inner BFS pruning correctness proxy:
/// After reactive2 is disposed, memoB.count == 0. The live branch (memoA → r1)
/// must still propagate correctly when sig changes.
test "push_reachable_count: inner pruning — live branch still fires after dead branch count reaches 0" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let mA = Memo::new(rt, () => sig.get() + 1)
  let mB = Memo::new(rt, () => sig.get() + 2)
  let mut r1_val = 0
  let r1 = Reactive::new(rt, () => {
    r1_val = mA.get()
    r1_val
  })
  let r2 = Reactive::new(rt, () => mB.get())
  inspect(get_count(rt, sig.id()), content="2")
  inspect(get_count(rt, mB.id()), content="1")
  r2.dispose()
  inspect(get_count(rt, mB.id()), content="0")
  inspect(get_count(rt, sig.id()), content="1")
  // The live branch must still work after the dead branch is pruned
  sig.set(10)
  inspect(r1_val, content="11") // mA.get() = sig.get() + 1 = 11
}
```

- [ ] **Step 2: Run the test** — it should pass already (the live branch fires regardless of pruning), verifying count correctness.

```bash
moon test -p dowdiness/incr/cells -f push_reachable_wbtest.mbt
```

- [ ] **Step 3: Add inner BFS pruning to `push_propagate.mbt`**

Inside `enqueue_push_subscribers`, find the `HybridMemo` and `PullMemo` arms of the subscriber loop match. Change them to check count before adding to worklist:

```moonbit
          HybridMemo(i) =>
            if self.pull.memos[i].meta.push_reachable_count > 0 {
              bfs_worklist.push(sub_id) // bridge only if push cells are downstream
            }
          PullMemo(i) =>
            if self.pull.memos[i].meta.push_reachable_count > 0 {
              bfs_worklist.push(sub_id) // bridge only if push cells are downstream
            }
```

The `_ => ()` arm and all other arms remain unchanged.

- [ ] **Step 4: Run full test suite and benchmarks**

```bash
moon test
moon bench --release -p dowdiness/incr/cells 2>&1 | grep "push efficiency"
```

Expected:
- All tests pass
- No benchmark regression (inner pruning should be neutral or slightly better)

- [ ] **Step 5: Commit**

```bash
git add cells/push_propagate.mbt cells/push_reachable_wbtest.mbt
git commit -m "perf: add inner BFS pruning for zero-count HybridMemo/PullMemo subscribers"
```

---

## Task 7: Final verification and interface update

**Files:**
- Run: `moon info && moon fmt`

- [ ] **Step 1: Update interfaces and format**

```bash
moon info && moon fmt
```

- [ ] **Step 2: Check that `.mbti` changes are expected**

```bash
git diff *.mbti
```

Expected changes: `CellMeta` struct gains `push_reachable_count` field. `CellOps` trait gains `push_reachable_count` method. Both are private implementation details — no public API surface changes.

- [ ] **Step 3: Run full test suite one final time**

```bash
moon test
```

Expected: all tests pass (≥ 323).

- [ ] **Step 4: Run benchmarks and record results**

```bash
moon bench --release -p dowdiness/incr/cells 2>&1 | grep "push efficiency"
```

Expected:
- `push efficiency: signal set, 100 hybrid subs, distant reactive` ≤ 0.05 µs
- `push efficiency: signal set, 1000 hybrid subs, distant reactive` ≤ 0.10 µs

- [ ] **Step 5: Final commit**

```bash
git add -p  # stage only .mbti and .mbt changes
git commit -m "chore: regenerate interfaces after push_reachable_count addition"
```

---

## Acceptance criteria

- [ ] All 323+ tests pass
- [ ] `push efficiency: signal set, 100 hybrid subs, distant reactive` ≤ 0.05 µs
- [ ] `push efficiency: signal set, 1000 hybrid subs, distant reactive` ≤ 0.10 µs
- [ ] `push_reachable_count` is 0 for all cells in graphs with no push nodes
- [ ] Counts return to 0 after all push cells are disposed
- [ ] No negative count asserts fire under any test
