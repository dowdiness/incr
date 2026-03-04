# Subscriber Links (Reverse Edges) Implementation Plan

**Goal:** Add reverse dependency edges (`subscribers`) to `CellMeta` so each cell knows which other cells depend on it. This is pure data structure work — the pull-based verification algorithm is unchanged.

**Architecture:** Add a `HashSet[CellId]` subscriber set to each `CellMeta`. Maintain it incrementally during `Memo::force_recompute`, which already diffs old vs new dependency lists (see `memo.mbt:183-195` — the Phase 4 comments mark exactly where subscriber updates should go). Expose via `Runtime::dependents(CellId)` introspection API.

**Tech Stack:** MoonBit. Validate with `moon check`, `moon test`, and refresh API summaries with `moon info`.

---

### Scope

In scope:
- `subscribers` field on `CellMeta` (reverse edges)
- Subscriber link maintenance in `Memo::force_recompute` dep diff
- `Runtime::dependents(CellId) -> Array[CellId]` introspection API
- `subscribers` field added to `CellInfo`
- Tests for link maintenance across recompute, dynamic deps, and removal

Out of scope:
- Push-based dirty flag propagation (future Phase 4 work)
- GC / cell removal (future — uses subscriber links but separate feature)
- Changes to verification algorithm (`verify.mbt` is untouched)

---

### Task 1: Add `subscribers` field to `CellMeta`

**Files:**
- Modify: `internal/cell.mbt`

**Step 1: Write the failing test**

Create `internal/subscriber_wbtest.mbt`:

```moonbit
test "subscriber: new cells have empty subscribers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 10)
  let meta = rt.get_cell(sig.id())
  inspect(meta.subscribers.size(), content="0")
}
```

**Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/internal -f subscriber_wbtest.mbt -i 0`
Expected: FAIL — `subscribers` field does not exist

**Step 3: Write minimal implementation**

In `internal/cell.mbt`, add to `CellMeta` struct:

```moonbit
  /// Reverse dependency links: cells that depend on this cell.
  /// Maintained during Memo::force_recompute dep diffing.
  subscribers : @hashset.HashSet[CellId]
```

Initialize in both `CellMeta::new_input` and `CellMeta::new_derived`:

```moonbit
  subscribers: @hashset.new(),
```

**Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/incr/internal -f subscriber_wbtest.mbt -i 0`
Expected: PASS

**Step 5: Commit**

```bash
git add internal/cell.mbt internal/subscriber_wbtest.mbt
git commit -m "feat: add subscribers field to CellMeta"
```

---

### Task 2: Maintain subscriber links during `Memo::force_recompute`

**Files:**
- Modify: `internal/memo.mbt` (lines ~183-195, replacing Phase 4 comments)

**Step 1: Write the failing test**

Add to `internal/subscriber_wbtest.mbt`:

```moonbit
test "subscriber: memo subscribes to its dependencies" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let b = Signal::new(rt, 2)
  let sum = Memo::new(rt, () => a.get() + b.get())
  let _ = sum.get()
  // a and b should list sum as a subscriber
  let a_meta = rt.get_cell(a.id())
  let b_meta = rt.get_cell(b.id())
  inspect(a_meta.subscribers.contains(sum.id()), content="true")
  inspect(b_meta.subscribers.contains(sum.id()), content="true")
}

test "subscriber: dynamic dep change updates subscribers" {
  let rt = Runtime::new()
  let flag = Signal::new(rt, true)
  let a = Signal::new(rt, 10)
  let b = Signal::new(rt, 20)
  let pick = Memo::new(rt, () => if flag.get() { a.get() } else { b.get() })
  let _ = pick.get()  // deps: flag, a
  let a_meta = rt.get_cell(a.id())
  let b_meta = rt.get_cell(b.id())
  inspect(a_meta.subscribers.contains(pick.id()), content="true")
  inspect(b_meta.subscribers.contains(pick.id()), content="false")
  // Switch branch: deps become flag, b
  flag.set(false)
  let _ = pick.get()
  let a_meta2 = rt.get_cell(a.id())
  let b_meta2 = rt.get_cell(b.id())
  inspect(a_meta2.subscribers.contains(pick.id()), content="false")
  inspect(b_meta2.subscribers.contains(pick.id()), content="true")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/internal -f subscriber_wbtest.mbt`
Expected: FAIL — subscribers are never populated

**Step 3: Write minimal implementation**

In `internal/memo.mbt`, in `Memo::force_recompute`, replace the Phase 4 comments (lines ~189-190) with actual subscriber link maintenance. After the dep diff section where `deps_changed` is computed, add:

```moonbit
  // Maintain subscriber links (reverse edges)
  if deps_changed {
    // Remove self from old deps that are no longer dependencies
    for dep in old_deps {
      if not(new_seen.contains(dep)) {
        let dep_meta = self.rt.get_cell(dep)
        dep_meta.subscribers.remove(dep_meta.subscribers.iter().find_first(
          fn(id) { id == self.cell_id }
        ).or(self.cell_id))
      }
    }
    // Build old set for checking which new deps are truly new
    let old_seen : @hashset.HashSet[CellId] = @hashset.new()
    for dep in old_deps {
      old_seen.add(dep)
    }
    // Add self to new deps that were not in old deps
    for dep in new_deps {
      if not(old_seen.contains(dep)) {
        let dep_meta = self.rt.get_cell(dep)
        dep_meta.subscribers.add(self.cell_id)
      }
    }
  }
```

Wait — `HashSet::remove` takes the key directly. Simpler:

```moonbit
  // Maintain subscriber links (reverse edges)
  if deps_changed {
    // Remove self from subscribers of deps that were dropped
    for dep in old_deps {
      if not(new_seen.contains(dep)) {
        let dep_meta = self.rt.get_cell(dep)
        dep_meta.subscribers.remove(self.cell_id)
      }
    }
    // Build old_seen for symmetric diff
    let old_seen : @hashset.HashSet[CellId] = @hashset.new()
    for dep in old_deps {
      old_seen.add(dep)
    }
    // Add self to subscribers of newly added deps
    for dep in new_deps {
      if not(old_seen.contains(dep)) {
        let dep_meta = self.rt.get_cell(dep)
        dep_meta.subscribers.add(self.cell_id)
      }
    }
  }
```

For the **first computation** (when `old_deps` is empty), `deps_changed` is already `true` (lengths differ: `new_deps.length() != 0`), so all new deps get subscriber links added via the "newly added deps" loop. The "dropped deps" loop is a no-op since `old_deps` is empty.

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/internal -f subscriber_wbtest.mbt`
Expected: PASS

**Step 5: Run full suite**

Run: `moon test`
Expected: All 167+ tests pass (existing behavior unchanged)

**Step 6: Commit**

```bash
git add internal/memo.mbt internal/subscriber_wbtest.mbt
git commit -m "feat: maintain subscriber links during memo recompute"
```

---

### Task 3: Add `Runtime::dependents` introspection API

**Files:**
- Modify: `internal/runtime.mbt`

**Step 1: Write the failing test**

Add to `internal/subscriber_wbtest.mbt`:

```moonbit
test "subscriber: dependents returns subscriber list" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let m1 = Memo::new(rt, () => a.get() + 1)
  let m2 = Memo::new(rt, () => a.get() * 2)
  let _ = m1.get()
  let _ = m2.get()
  let deps = rt.dependents(a.id())
  inspect(deps.length(), content="2")
  inspect(deps.contains(m1.id()), content="true")
  inspect(deps.contains(m2.id()), content="true")
}

test "subscriber: dependents returns empty for leaf memo" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let m = Memo::new(rt, () => a.get())
  let _ = m.get()
  let deps = rt.dependents(m.id())
  inspect(deps.length(), content="0")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/internal -f subscriber_wbtest.mbt`
Expected: FAIL — `dependents` method does not exist

**Step 3: Write minimal implementation**

In `internal/runtime.mbt`:

```moonbit
///|
/// Returns the cell IDs that depend on the given cell (reverse edges).
///
/// This enables introspection of the dependency graph in both directions.
/// The returned array is a snapshot; modifying it does not affect the runtime.
///
/// # Parameters
///
/// - `id`: The cell to query
///
/// # Returns
///
/// Array of CellIds that have `id` in their dependency list
pub fn Runtime::dependents(self : Runtime, id : CellId) -> Array[CellId] {
  let meta = self.get_cell(id)
  let result : Array[CellId] = []
  for sub in meta.subscribers {
    result.push(sub)
  }
  result
}
```

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/internal -f subscriber_wbtest.mbt`
Expected: PASS

**Step 5: Commit**

```bash
git add internal/runtime.mbt internal/subscriber_wbtest.mbt
git commit -m "feat: add Runtime::dependents introspection API"
```

---

### Task 4: Add `subscribers` to `CellInfo`

**Files:**
- Modify: `internal/runtime.mbt` (`CellInfo` struct and `cell_info` method)

**Step 1: Write the failing test**

Add to `internal/subscriber_wbtest.mbt`:

```moonbit
test "subscriber: cell_info includes subscribers" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let m = Memo::new(rt, () => a.get() + 1)
  let _ = m.get()
  match rt.cell_info(a.id()) {
    Some(info) => inspect(info.subscribers.contains(m.id()), content="true")
    None => abort("expected cell info")
  }
}
```

**Step 2: Run test to verify it fails**

Expected: FAIL — `subscribers` field not on `CellInfo`

**Step 3: Write minimal implementation**

Add `subscribers : Array[CellId]` field to `CellInfo` struct.

In `Runtime::cell_info`, populate it:

```moonbit
  subscribers: {
    let subs : Array[CellId] = []
    for sub in meta.subscribers {
      subs.push(sub)
    }
    subs
  },
```

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/internal -f subscriber_wbtest.mbt`
Expected: PASS

**Step 5: Commit**

```bash
git add internal/runtime.mbt internal/subscriber_wbtest.mbt
git commit -m "feat: add subscribers to CellInfo"
```

---

### Task 5: Integration test via public API

**Files:**
- Modify: `tests/` (add integration test through `@incr` facade)

**Step 1: Write integration test**

Create or add to an existing test file in `tests/`:

```moonbit
test "subscriber: dependents accessible via public API" {
  let rt = @incr.Runtime()
  let x = @incr.Signal(rt, 10)
  let doubled = @incr.Memo(rt, () => x.get() * 2)
  let _ = doubled.get()
  let deps = rt.dependents(x.id())
  inspect(deps.length(), content="1")
  inspect(deps.contains(doubled.id()), content="true")
}

test "subscriber: chain dependencies tracked" {
  let rt = @incr.Runtime()
  let a = @incr.Signal(rt, 1)
  let b = @incr.Memo(rt, () => a.get() + 1)
  let c = @incr.Memo(rt, () => b.get() * 2)
  let _ = c.get()
  // a -> b -> c
  let a_deps = rt.dependents(a.id())
  inspect(a_deps.length(), content="1")
  inspect(a_deps.contains(b.id()), content="true")
  let b_deps = rt.dependents(b.id())
  inspect(b_deps.length(), content="1")
  inspect(b_deps.contains(c.id()), content="true")
  let c_deps = rt.dependents(c.id())
  inspect(c_deps.length(), content="0")
}
```

**Step 2: Run tests**

Run: `moon test`
Expected: All tests pass

**Step 3: Commit**

```bash
git add tests/
git commit -m "test: add subscriber links integration tests"
```

---

### Task 6: Update documentation and generated API

**Step 1: Update docs**

- Update `docs/api-reference.md` to document `Runtime::dependents(CellId)` and the `subscribers` field on `CellInfo`
- Update `docs/roadmap.md` to mark subscriber links as ✓
- Update `docs/todo.md` to check off subscriber links and `Runtime::dependents`

**Step 2: Refresh generated API**

Run:
```bash
moon info
```

Verify `pkg.generated.mbti` files include:
- `pub fn Runtime::dependents(Self, CellId) -> Array[CellId]`
- `subscribers : Array[CellId]` in `CellInfo`

**Step 3: Commit**

```bash
git add docs/ internal/pkg.generated.mbti pkg.generated.mbti
git commit -m "docs: add subscriber links to API reference and roadmap"
```

---

### Acceptance Criteria

- Every `CellMeta` has a `subscribers : HashSet[CellId]` field
- Subscriber links are maintained incrementally during `Memo::force_recompute` dep diffing
- `Runtime::dependents(id)` returns the correct subscriber list
- `CellInfo` includes a `subscribers` snapshot
- Dynamic dependency changes (branch switching) correctly update subscriber links
- All existing 167 tests still pass (verification algorithm unchanged)
- No changes to `internal/verify.mbt`
