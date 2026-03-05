# Push Reactive + Effect (Phase 3)

**Goal:** Add eager push-mode cells: `Reactive[T]` (derived, recomputed when upstream changes) and `Effect` (terminal, side effects). Push propagation uses a level-sorted priority queue for glitch-free topological recomputation.

**Architecture:** See `docs/incr-unified-design.md` §3.3–3.4, §4.2, §7.4–7.5 for data structure definitions and propagation algorithm pseudocode.

**Prerequisite:** Phase 2 complete.

**Tech Stack:** MoonBit. Validate with `moon check` and `moon test`.

---

### Scope

In scope:
- `PushReactive`, `PushEffect`, `Disposed` variants added to `CellRef`
- `PushReactiveData`, `PushEffectData` structs
- `push_reactives`, `push_effects`, `free_push_reactives`, `free_push_effects` arrays added to Runtime
- `PushEntry` struct + `push_propagate_from` function (`cells/propagate.mbt`)
- `propagate_level_change`, `recompute_level`, `get_level` helpers
- Disposal: `dispose_reactive`, `dispose_effect`
- `has_push_subscribers` guard in `commit_batch`
- `get_subscribers`, `get_subscribers_mut`, `get_changed_at`, `cell_id_for` extended for push variants
- User-facing `Reactive[T]` and `Effect` structs
- `moonbitlang/core/priority_queue` added to `cells/moon.pkg`

Out of scope:
- Relation/Rule/HybridMemo (Phases 4–5)

---

### Task 1: Extend `CellRef` with push variants

**Files:**
- Modify: `cells/cell_ref.mbt`
- Create: `cells/push_wbtest.mbt`

**Step 1: Write the failing test**

Create `cells/push_wbtest.mbt`:

```moonbit
///|
test "cell_ref: PushReactive, PushEffect, Disposed variants exist" {
  let a : CellRef = CellRef::PushReactive(0)
  let b : CellRef = CellRef::PushEffect(2)
  let c : CellRef = CellRef::Disposed
  let ia = match a { PushReactive(i) => i; _ => -1 }
  let ib = match b { PushEffect(i) => i; _ => -1 }
  let ok = match c { Disposed => true; _ => false }
  inspect(ia, content="0")
  inspect(ib, content="2")
  inspect(ok, content="true")
}
```

**Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f push_wbtest.mbt -i 0`
Expected: FAIL — `PushReactive`, `PushEffect`, `Disposed` variants do not exist

**Step 3: Write minimal implementation**

In `cells/cell_ref.mbt`, add three new variants:

```moonbit
pub enum CellRef {
  PullSignal(index : Int)
  PullMemo(index : Int)
  PushReactive(index : Int)
  PushEffect(index : Int)
  Disposed
  // Relation, Rule added in Phase 4
  // HybridMemo added in Phase 5
}
```

Update all existing `match` expressions on `CellRef` to add wildcard arms for the new variants.

**Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/incr/cells -f push_wbtest.mbt -i 0`
Expected: PASS

**Step 5: Run full suite**

Run: `moon test`
Expected: All existing tests pass

**Step 6: Commit**

```bash
git add cells/cell_ref.mbt cells/push_wbtest.mbt
git commit -m "feat(push): extend CellRef with PushReactive, PushEffect, Disposed"
```

---

### Task 2: Add `PushReactiveData`, `PushEffectData` and push arrays to Runtime

**Files:**
- Create: `cells/reactive.mbt`
- Create: `cells/effect.mbt`
- Modify: `cells/runtime.mbt`

**Step 1: Write the failing test**

Add to `cells/push_wbtest.mbt`:

```moonbit
///|
test "runtime: push arrays start empty" {
  let rt = Runtime::new()
  inspect(rt.push_reactives.length(), content="0")
  inspect(rt.push_effects.length(), content="0")
  inspect(rt.free_push_reactives.length(), content="0")
  inspect(rt.free_push_effects.length(), content="0")
}
```

**Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f push_wbtest.mbt`
Expected: FAIL — push arrays do not exist on Runtime

**Step 3: Write minimal implementation**

In `cells/reactive.mbt`, define `PushReactiveData` per `docs/incr-unified-design.md` §3.3.

In `cells/effect.mbt`, define `PushEffectData` per §3.4.

In `cells/runtime.mbt`, add to `Runtime` struct:

```moonbit
push_reactives      : Array[PushReactiveData]
push_effects        : Array[PushEffectData]
free_push_reactives : Array[Int]
free_push_effects   : Array[Int]
```

Initialize all four to `[]` in `Runtime::new()`.

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f push_wbtest.mbt`
Expected: PASS

**Step 5: Run full suite**

Run: `moon test`
Expected: All existing tests pass

**Step 6: Commit**

```bash
git add cells/reactive.mbt cells/effect.mbt cells/runtime.mbt cells/push_wbtest.mbt
git commit -m "feat(push): add PushReactiveData, PushEffectData, and push arrays to Runtime"
```

---

### Task 3: Implement `push_propagate_from` in `propagate.mbt`

**Files:**
- Create: `cells/propagate.mbt`
- Modify: `cells/moon.pkg` (add `moonbitlang/core/priority_queue`)

**Step 1: Write the failing test**

Add to `cells/push_wbtest.mbt`:

```moonbit
///|
test "push propagation: basic reactive chain Signal → Reactive" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get() * 2)
  let _ = r.get()  // initial compute
  s.set(5)         // triggers push propagation
  inspect(r.get(), content="10")
}

///|
test "push propagation: glitch prevention in diamond" {
  // a → b(a+1), a → c(a*10), b+c → d
  // d should never see an inconsistent (b,c) pair (e.g. b from new a, c from old a)
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let b = Reactive::new(rt, () => a.get() + 1)
  let c = Reactive::new(rt, () => a.get() * 10)
  let mut saw_glitch = false
  let d = Reactive::new(rt, () => {
    let bv = b.get()
    let cv = c.get()
    // Invariant: bv - 1 == cv / 10 (both sides equal the current value of a)
    if bv - 1 != cv / 10 { saw_glitch = true }
    bv + cv
  })
  let _ = d.get()   // a=1: b=2, c=10, d=12
  a.set(5)          // a=5: b=6, c=50, d=56 — glitch would produce b=6,c=10 → d=16 or b=2,c=50 → d=52
  let _ = d.get()
  inspect(saw_glitch, content="false")
  inspect(d.get(), content="56")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f push_wbtest.mbt`
Expected: FAIL — `Reactive::new` / `push_propagate_from` do not exist

**Step 3: Write minimal implementation**

In `cells/moon.pkg`, add `moonbitlang/core/priority_queue` to imports.

Create `cells/propagate.mbt` with `PushEntry` (struct with `neg_level : Int` and `cell_ref : CellRef`, implementing `Compare`) and `push_propagate_from`. See `docs/incr-unified-design.md` §4.2 for the full algorithm.

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f push_wbtest.mbt`
Expected: PASS

**Step 5: Commit**

```bash
git add cells/propagate.mbt cells/moon.pkg cells/push_wbtest.mbt
git commit -m "feat(push): implement push_propagate_from with level-sorted priority queue"
```

---

### Task 4: Implement level helpers and `propagate_level_change`

**Files:**
- Modify: `cells/propagate.mbt`
- Modify: `cells/runtime.mbt`

**Step 1: Write the failing test**

Add to `cells/push_wbtest.mbt`:

```moonbit
///|
test "level: reactive level is source max + 1" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r1 = Reactive::new(rt, () => s.get())
  let r2 = Reactive::new(rt, () => r1.get() + 1)
  let _ = r1.get()
  let _ = r2.get()
  let r1_idx = match rt.cell_index[r1.id().id] { PushReactive(i) => i; _ => abort("") }
  let r2_idx = match rt.cell_index[r2.id().id] { PushReactive(i) => i; _ => abort("") }
  inspect(rt.push_reactives[r1_idx].level, content="1")
  inspect(rt.push_reactives[r2_idx].level, content="2")
}

///|
test "early cutoff: unchanged value does not propagate to downstream" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let always5 = Reactive::new(rt, () => { let _ = s.get(); 5 })  // ignores s, always returns 5
  let mut count = 0
  let downstream = Reactive::new(rt, () => { count += 1; always5.get() })
  let _ = downstream.get()
  inspect(count, content="1")
  s.set(99)
  inspect(count, content="1")  // always5 returned same value → downstream not recomputed
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f push_wbtest.mbt`
Expected: FAIL — level fields not set / early cutoff not working

**Step 3: Write minimal implementation**

In `cells/propagate.mbt`, implement:
- `recompute_level(cell_id, sources)` — max source level + 1
- `get_level(cell_id)` — dispatch on `CellRef`; pull cells and signals are level 0
- `propagate_level_change(changed_cell, update_queue)` — lazy deletion via stale-entry check

See `docs/incr-unified-design.md` §4.2 for pseudocode.

**Step 4: Run full test suite**

Run: `moon test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add cells/propagate.mbt cells/runtime.mbt cells/push_wbtest.mbt
git commit -m "feat(push): implement recompute_level, get_level, propagate_level_change"
```

---

### Task 5: User-facing `Reactive[T]` and `Effect`

**Files:**
- Modify: `cells/reactive.mbt`
- Modify: `cells/effect.mbt`

**Step 1: Write the failing test**

Add to `cells/push_wbtest.mbt`:

```moonbit
///|
test "reactive: get() returns cached value" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let r = Reactive::new(rt, () => s.get() * 3)
  inspect(r.get(), content="30")
  inspect(r.get(), content="30")  // cached
}

///|
test "effect: runs on creation, then re-runs on each dependency change" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let mut log : Array[Int] = []
  let _e = Effect::new(rt, () => log.push(s.get()))
  // Effect runs immediately on creation to establish dependencies
  inspect(log, content="[0]")
  s.set(1)
  inspect(log, content="[0, 1]")
  s.set(2)
  inspect(log, content="[0, 1, 2]")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f push_wbtest.mbt`
Expected: FAIL — `Reactive::new` / `Effect::new` not yet user-accessible

**Step 3: Write minimal implementation**

In `cells/reactive.mbt`, define:

```moonbit
pub struct Reactive[T : Eq] {
  id        : ReactiveId[T]
  value_ref : Ref[T?]
  rt        : Runtime
}
pub fn[T : Eq] Reactive::new(rt : Runtime, compute : () -> T) -> Reactive[T]
pub fn[T : Eq] Reactive::get(self : Reactive[T]) -> T
pub fn[T : Eq] Reactive::dispose(self : Reactive[T]) -> Unit
```

In `cells/effect.mbt`, define `Effect` with `new` and `dispose`. See `docs/incr-unified-design.md` §7.4–7.5 for full API.

**Step 4: Run full test suite**

Run: `moon test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add cells/reactive.mbt cells/effect.mbt cells/push_wbtest.mbt
git commit -m "feat(push): add user-facing Reactive[T] and Effect types"
```

---

### Task 6: Update `commit_batch` and extend helpers for push variants

**Files:**
- Modify: `cells/runtime.mbt`

**Step 1: Write the failing test**

Add to `cells/push_wbtest.mbt`:

```moonbit
///|
test "push: batch commit triggers propagation" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 0)
  let r = Reactive::new(rt, () => s.get() * 2)
  let _ = r.get()
  rt.batch(fn() {
    s.set(5)
    inspect(r.get(), content="0")  // not yet propagated inside batch
  })
  inspect(r.get(), content="10")   // propagated after commit
}

///|
test "mixed pull/push: Memo reads Reactive; Reactive reads Signal" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get() + 1)
  let m = Memo::new(rt, () => r.get() * 10)
  s.set(4)
  inspect(m.get(), content="50")  // r = 5, m = 50
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f push_wbtest.mbt`
Expected: FAIL — `commit_batch` does not call `push_propagate_from`

**Step 3: Write minimal implementation**

In `cells/runtime.mbt`:

1. Implement `has_push_subscribers(cell_ids)` — checks whether any cell in the list has a `PushReactive` or `PushEffect` subscriber.
2. In `commit_batch`, after `advance_revision`, call:

```moonbit
if self.has_push_subscribers(changed_ids) {
  self.push_propagate_from(changed_ids)
}
```

3. Extend `get_subscribers`, `get_subscribers_mut`, `get_changed_at`, `cell_id_for` with `PushReactive`, `PushEffect`, `Disposed` arms per `docs/incr-unified-design.md` §6.

**Step 4: Run full test suite**

Run: `moon test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add cells/runtime.mbt cells/push_wbtest.mbt
git commit -m "feat(push): update commit_batch to trigger push propagation"
```

---

### Task 7: Implement disposal

**Files:**
- Modify: `cells/runtime.mbt`
- Modify: `cells/reactive.mbt`, `cells/effect.mbt`

**Step 1: Write the failing test**

Add to `cells/push_wbtest.mbt`:

```moonbit
///|
test "dispose: disposed reactive not reachable via subscriber walk" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get() * 2)
  let _ = r.get()
  r.dispose()
  let subs = rt.get_subscribers(rt.cell_index[s.id().id]).collect()
  inspect(subs.length(), content="0")
}

///|
test "dispose: sources' subscriber sets updated after dispose" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let r = Reactive::new(rt, () => s.get())
  let _ = r.get()
  let s_idx = match rt.cell_index[s.id().id] { PullSignal(i) => i; _ => abort("") }
  inspect(rt.pull_signals[s_idx].subscribers.size(), content="1")
  r.dispose()
  inspect(rt.pull_signals[s_idx].subscribers.size(), content="0")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f push_wbtest.mbt`
Expected: FAIL — `dispose` does not update subscriber links

**Step 3: Write minimal implementation**

In `cells/runtime.mbt`, implement `dispose_reactive` and `dispose_effect` per the 4-step sequence in `docs/incr-unified-design.md` §7.4:
1. Remove cell from all sources' subscriber sets
2. Remove cell from all subscribers' sources arrays (reactive only)
3. Set `cell_index[cell_id.id] = Disposed`
4. Push index to free list

Wire into `Reactive::dispose` and `Effect::dispose`.

**Step 4: Run full test suite**

Run: `moon test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add cells/runtime.mbt cells/reactive.mbt cells/effect.mbt cells/push_wbtest.mbt
git commit -m "feat(push): implement reactive and effect disposal"
```

---

### Acceptance Criteria

- All Phase 1 + Phase 2 tests pass
- All Phase 3 tests above pass
- `moon check` has no type errors (including `priority_queue` import in `moon.pkg`)
- Diamond dependency test confirms no glitch (downstream sees consistent state)
- Early cutoff: downstream not recomputed when reactive value is unchanged
- A disposed reactive never appears in any subscriber walk
- `Reactive::dispose` and `Effect::dispose` correctly update all subscriber sets
