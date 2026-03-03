# Subscriber Tracking (Phase 2)

**Goal:** Add bidirectional subscriber links to pull cells. Every `A reads B` dependency edge gains a reverse `B → subscribers → A` edge, maintained incrementally by `finish_tracking`. Links are populated but unused for propagation yet — push propagation uses them in Phase 3.

**Architecture:** See `docs/incr-unified-design.md` §5 for `begin_tracking`, `end_tracking`, `finish_tracking` pseudocode.

**Prerequisite:** Phase 1 complete.

**Tech Stack:** MoonBit. Validate with `moon check` and `moon test`.

---

### Scope

In scope:
- `Runtime::begin_tracking(cell_id)` — push fresh `ActiveQuery` frame onto tracking stack
- `Runtime::end_tracking()` — pop frame, return collected deps as `Array[CellId]`
- `Runtime::finish_tracking(cell_id, old_deps, new_deps)` — diff old vs new; add/remove from `subscribers`
- `Runtime::get_subscribers(cell_ref)` — return `Iter[CellId]`
- `Runtime::get_subscribers_mut(cell_id)` — return mutable `@hashset.HashSet[CellId]`
- Updated `compute` closure in `new_memo_id` to call tracking helpers
- Updated `PullMemoData.dependencies` from result of `end_tracking`

Out of scope:
- Push propagation via subscriber links (Phase 3)
- Relation/Rule subscriber arms (Phase 4)

---

### Task 1: Add `begin_tracking`, `end_tracking`, `finish_tracking`

**Files:**
- Modify: `cells/tracking.mbt`
- Modify: `cells/runtime.mbt`
- Create: `cells/tracking_wbtest.mbt`

**Step 1: Write the failing test**

Create `cells/tracking_wbtest.mbt`:

```moonbit
///|
test "tracking: begin/end tracking records dependency" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let memo_id = rt.alloc_cell_id(CellRef::PullMemo(0))
  rt.begin_tracking(memo_id)
  let _ = sig.get()
  let deps = rt.end_tracking()
  inspect(deps.length(), content="1")
  inspect(deps[0] == sig.id(), content="true")
}

///|
test "tracking: finish_tracking adds memo to dep subscribers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => sig.get())
  let _ = m.get()
  // After get, finish_tracking should have added m to sig's subscribers
  let sig_idx = match rt.cell_index[sig.id().id] {
    PullSignal(i) => i
    _ => abort("expected PullSignal")
  }
  inspect(rt.pull_signals[sig_idx].subscribers.contains(m.id()), content="true")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f tracking_wbtest.mbt`
Expected: FAIL — `begin_tracking` / `end_tracking` do not exist, or subscribers not populated

**Step 3: Write minimal implementation**

In `cells/tracking.mbt` (or `cells/runtime.mbt`):

1. `begin_tracking(cell_id)` — push new `ActiveQuery { cell_id, deps: [], seen: @hashset.new() }` onto `self.tracking_stack`. See `docs/incr-unified-design.md` §5.
2. `end_tracking()` — pop the top `ActiveQuery` and return its `deps` as `Array[CellId]`. See §5.
3. `finish_tracking(cell_id, old_deps, new_deps)` — compute symmetric diff; remove `cell_id` from `subscribers` of dropped deps; add to `subscribers` of new deps. Use `get_subscribers_mut` for mutations. See §5.

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f tracking_wbtest.mbt`
Expected: PASS

**Step 5: Commit**

```bash
git add cells/tracking.mbt cells/runtime.mbt cells/tracking_wbtest.mbt
git commit -m "feat(subscribers): add begin/end/finish_tracking helpers"
```

---

### Task 2: Add `get_subscribers` and `get_subscribers_mut`

**Files:**
- Modify: `cells/runtime.mbt`

**Step 1: Write the failing test**

Add to `cells/tracking_wbtest.mbt`:

```moonbit
///|
test "get_subscribers: returns empty iter for new signal" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let count = rt.get_subscribers(rt.cell_index[sig.id().id]).fold(0, fn(acc, _) { acc + 1 })
  inspect(count, content="0")
}

///|
test "get_subscribers: contains memo after first get" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => sig.get())
  let _ = m.get()
  let subs = rt.get_subscribers(rt.cell_index[sig.id().id]).collect()
  inspect(subs.length(), content="1")
  inspect(subs[0] == m.id(), content="true")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f tracking_wbtest.mbt`
Expected: FAIL — `get_subscribers` does not exist

**Step 3: Write minimal implementation**

In `cells/runtime.mbt`, implement `get_subscribers` and `get_subscribers_mut` dispatching on `CellRef`. See `docs/incr-unified-design.md` §6 for the full dispatch table. Phase 2 only requires `PullSignal` and `PullMemo` arms:

```moonbit
fn Runtime::get_subscribers(self, cell_ref : CellRef) -> Iter[CellId] {
  match cell_ref {
    PullSignal(idx) => self.pull_signals[idx].subscribers.iter()
    PullMemo(idx)   => self.pull_memos[idx].subscribers.iter()
    // Phase 3+ arms added later
  }
}

fn Runtime::get_subscribers_mut(self, cell_id : CellId) -> @hashset.HashSet[CellId] {
  match self.cell_index[cell_id.id] {
    PullSignal(idx) => self.pull_signals[idx].subscribers
    PullMemo(idx)   => self.pull_memos[idx].subscribers
    _ => abort("get_subscribers_mut: unsupported cell kind")
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f tracking_wbtest.mbt`
Expected: PASS

**Step 5: Commit**

```bash
git add cells/runtime.mbt cells/tracking_wbtest.mbt
git commit -m "feat(subscribers): add get_subscribers and get_subscribers_mut"
```

---

### Task 3: Update memo `compute` closure to maintain subscriber links

**Files:**
- Modify: `cells/runtime.mbt` (`new_memo_id` closure)
- Modify: `cells/memo.mbt`
- Create: `cells/subscriber_link_wbtest.mbt`

**Step 1: Write the failing test**

Create `cells/subscriber_link_wbtest.mbt`:

```moonbit
///|
test "subscriber: after memo.get(), memo is in all deps' subscribers" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let b = Signal::new(rt, 2)
  let sum = Memo::new(rt, () => a.get() + b.get())
  let _ = sum.get()
  let a_idx = match rt.cell_index[a.id().id] { PullSignal(i) => i; _ => abort("") }
  let b_idx = match rt.cell_index[b.id().id] { PullSignal(i) => i; _ => abort("") }
  inspect(rt.pull_signals[a_idx].subscribers.contains(sum.id()), content="true")
  inspect(rt.pull_signals[b_idx].subscribers.contains(sum.id()), content="true")
}

///|
test "subscriber: dynamic dep changes update subscriber links" {
  let rt = Runtime::new()
  let flag = Signal::new(rt, true)
  let a = Signal::new(rt, 10)
  let b = Signal::new(rt, 20)
  let pick = Memo::new(rt, () => if flag.get() { a.get() } else { b.get() })
  let _ = pick.get()  // deps: flag, a
  let a_idx = match rt.cell_index[a.id().id] { PullSignal(i) => i; _ => abort("") }
  let b_idx = match rt.cell_index[b.id().id] { PullSignal(i) => i; _ => abort("") }
  inspect(rt.pull_signals[a_idx].subscribers.contains(pick.id()), content="true")
  inspect(rt.pull_signals[b_idx].subscribers.contains(pick.id()), content="false")
  flag.set(false)
  let _ = pick.get()  // deps: flag, b
  inspect(rt.pull_signals[a_idx].subscribers.contains(pick.id()), content="false")
  inspect(rt.pull_signals[b_idx].subscribers.contains(pick.id()), content="true")
}

///|
test "subscriber: memo.get() idempotent — no duplicate subscriber entries" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1)
  let m = Memo::new(rt, () => a.get() + 1)
  let _ = m.get()
  let _ = m.get()
  let a_idx = match rt.cell_index[a.id().id] { PullSignal(i) => i; _ => abort("") }
  inspect(rt.pull_signals[a_idx].subscribers.size(), content="1")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f subscriber_link_wbtest.mbt`
Expected: FAIL — compute closure does not call tracking helpers

**Step 3: Write minimal implementation**

In `new_memo_id`, update the `compute` closure to:

1. Call `self.begin_tracking(cell_id)` before invoking the user function
2. Invoke the user function to get the new value
3. Call `self.end_tracking()` to get `new_deps`
4. Call `self.finish_tracking(cell_id, old_deps, new_deps)` to sync subscriber links
5. Update `PullMemoData.dependencies = new_deps`

See `docs/incr-unified-design.md` §5 for the full pattern.

**Step 4: Run full test suite**

Run: `moon test`
Expected: All 200 existing tests pass

**Step 5: Commit**

```bash
git add cells/runtime.mbt cells/memo.mbt cells/subscriber_link_wbtest.mbt
git commit -m "feat(subscribers): update memo compute closure to maintain subscriber links"
```

---

### Acceptance Criteria

- `moon test` passes all 200 existing tests
- `moon check` reports no type errors
- After `memo.get()`, the memo's `cell_id` appears in every dependency's `subscribers` set
- Dynamic dep changes (branch switching) correctly add/remove subscriber links
- `memo.get()` is idempotent — calling it twice does not create duplicate subscriber entries
- Subscriber/dependency consistency holds: for every live memo, each dep's `subscribers` contains that memo's `cell_id`
