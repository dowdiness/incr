# Runtime Modularization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose the Runtime god-object into smaller, well-bounded components with explicit phase transitions, grouped state, and unified subscriber maintenance.

**Architecture:** Replace ad-hoc boolean guards (`in_fixpoint`, `in_push_propagation`) with a `PropagationPhase` enum for compile-time exhaustiveness. Group related fields in RuntimeCore into sub-structs (`RevisionState`, `TrackingState`, `BatchState`). Unify the duplicated subscriber-diff logic between `memo_force_recompute` and `finish_tracking` into a single shared function. Keep `batch_depth` as a separate counter (it's orthogonal to propagation phase — used for re-entrancy during commit callbacks).

**Tech Stack:** MoonBit, moon check/test/fmt/info

---

## File Structure

All changes are internal to the `cells/` package. No public API changes.

**Modified files:**

| File | Changes |
|------|---------|
| `cells/runtime.mbt` | Add `PropagationPhase` enum; replace `in_fixpoint`/`in_push_propagation` with `phase` field; add `RevisionState`, `TrackingState`, `BatchState` sub-structs; add phase transition helpers |
| `cells/cell_ops.mbt` | Update `RevisionManager` trait comment (references `batch_depth`) |
| `cells/verify.mbt` | Replace `self.core.in_fixpoint` reads with `self.core.phase` checks |
| `cells/memo.mbt` | Replace `self.rt.core.in_fixpoint` read with phase check; extract subscriber diff into shared function |
| `cells/hybrid_memo.mbt` | Replace `self.rt.core.in_fixpoint` read with phase check |
| `cells/signal.mbt` | No change — `batch_depth` stays as-is |
| `cells/batch.mbt` | Update field paths for `BatchState` sub-struct |
| `cells/tracking.mbt` | Update field paths for `TrackingState` sub-struct; refactor `finish_tracking` to use shared diff function |
| `cells/push_propagate.mbt` | Replace `self.core.in_push_propagation` writes with phase transitions |
| `cells/push_reactive.mbt` | Replace `rt.core.in_fixpoint` and `rt.core.in_push_propagation` reads with phase checks |
| `cells/datalog_fixpoint.mbt` | Replace `self.core.in_fixpoint` writes/reads with phase transitions |
| `cells/datalog_relation.mbt` | Replace `self.rt.core.in_fixpoint` read with phase check |
| `cells/datalog_functional_relation.mbt` | Replace `self.rt.core.in_fixpoint` reads with phase checks |
| `cells/gc_wbtest.mbt` | Update whitebox test to check `phase` instead of `in_push_propagation` |
| `cells/batch_wbtest.mbt` | Update field paths for `BatchState` sub-struct |
| `cells/datalog_wbtest.mbt` | Update `batch_depth` access path |
| `cells/pull_signal.mbt` | Update `batch_depth` access path |

---

## Task 1: Add PropagationPhase Enum

**Files:**
- Modify: `cells/runtime.mbt`

- [ ] **Step 1: Add the PropagationPhase enum to runtime.mbt**

Add above the `RuntimeCore` struct definition:

```moonbit
///|
/// Mutually exclusive runtime phases for cross-engine guards.
///
/// These phases are never active simultaneously. `batch_depth` is
/// orthogonal — batches compose with any propagation phase (e.g.
/// commit_batch temporarily raises batch_depth during callbacks
/// while the propagation phase is Idle).
priv enum PropagationPhase {
  Idle
  PushPropagating
  InFixpoint
  GarbageCollecting
} derive(Eq, Debug)
```

- [ ] **Step 2: Replace boolean fields with phase field in RuntimeCore**

In `RuntimeCore`, replace these two fields:

```moonbit
  mut in_fixpoint : Bool
```

and:

```moonbit
  mut in_push_propagation : Bool
```

with a single field:

```moonbit
  mut phase : PropagationPhase
```

- [ ] **Step 3: Update RuntimeCore comments**

Remove the doc comments for `in_fixpoint` (lines 59-62) and `in_push_propagation` (lines 68-70). The `PropagationPhase` enum doc replaces them.

- [ ] **Step 4: Update Runtime::new initializer**

In `Runtime::new`, replace:

```moonbit
      in_fixpoint: false,
```

and:

```moonbit
      in_push_propagation: false,
```

with:

```moonbit
      phase: Idle,
```

- [ ] **Step 5: Add phase transition helpers**

Add after `Runtime::new`:

```moonbit
///|
/// Transitions to a new propagation phase.
///
/// Aborts if the current phase is not `Idle` — phases are mutually
/// exclusive. The one exception is returning to `Idle`, which is
/// always allowed from any active phase (used in finally-style cleanup).
fn Runtime::enter_phase(self : Runtime, next : PropagationPhase) -> Unit {
  guard self.core.phase is Idle else {
    abort(
      "enter_phase: cannot enter " +
      next.to_string() +
      " while in " +
      self.core.phase.to_string(),
    )
  }
  self.core.phase = next
}

///|
/// Returns to the Idle phase. Unconditional — always succeeds.
fn Runtime::leave_phase(self : Runtime) -> Unit {
  self.core.phase = Idle
}

///|
/// Returns true if the runtime is currently in the given phase.
fn Runtime::is_in_phase(self : Runtime, phase : PropagationPhase) -> Bool {
  self.core.phase == phase
}
```

- [ ] **Step 6: Run moon check**

Run: `moon check 2>&1`
Expected: Errors — old field names still referenced in other files. This is expected; we fix them in the next steps.

- [ ] **Step 7: Commit**

```bash
git add cells/runtime.mbt
git commit -m "refactor: add PropagationPhase enum, replace boolean flags in RuntimeCore"
```

---

## Task 2: Migrate All Guard Sites to Phase Checks

**Files:**
- Modify: `cells/runtime.mbt`, `cells/verify.mbt`, `cells/memo.mbt`, `cells/hybrid_memo.mbt`, `cells/push_propagate.mbt`, `cells/push_reactive.mbt`, `cells/datalog_fixpoint.mbt`, `cells/datalog_relation.mbt`, `cells/datalog_functional_relation.mbt`, `cells/gc_wbtest.mbt`

- [ ] **Step 1: Update runtime.mbt guard sites**

In `Runtime::guard_dispose` (line ~625), replace:

```moonbit
  guard !self.core.in_fixpoint else {
```

with:

```moonbit
  guard !(self.core.phase is InFixpoint) else {
```

In `Runtime::gc` (line ~715-721), replace:

```moonbit
  guard self.core.batch_depth == 0 else { abort("gc: cannot run during batch") }
  guard !self.core.in_fixpoint else {
    abort("gc: cannot run during fixpoint evaluation")
  }
  guard !self.core.in_push_propagation else {
    abort("gc: cannot run during push propagation")
  }
```

with:

```moonbit
  guard self.core.batch_depth == 0 else { abort("gc: cannot run during batch") }
  guard self.core.phase is Idle else {
    abort(
      "gc: cannot run during " + self.core.phase.to_string(),
    )
  }
```

Then wrap the `gc_sweep()` call with phase transitions:

```moonbit
  self.enter_phase(GarbageCollecting)
  self.gc_sweep()
  self.leave_phase()
```

- [ ] **Step 2: Update verify.mbt guard sites**

In `Runtime::pull_verify`, at line ~84, replace:

```moonbit
      if self.core.in_fixpoint {
        abort("pull_verify: cannot verify Relation/Rule during fixpoint()")
      }
```

with:

```moonbit
      if self.core.phase is InFixpoint {
        abort("pull_verify: cannot verify Relation/Rule during fixpoint()")
      }
```

At line ~127, replace:

```moonbit
              if self.core.in_fixpoint {
```

with:

```moonbit
              if self.core.phase is InFixpoint {
```

- [ ] **Step 3: Update memo.mbt guard site**

In `Memo::get_result_inner` (line ~230), replace:

```moonbit
  if self.rt.core.in_fixpoint {
```

with:

```moonbit
  if self.rt.core.phase is InFixpoint {
```

- [ ] **Step 4: Update hybrid_memo.mbt guard site**

In `HybridMemo::get_result_inner` (line ~104), replace:

```moonbit
  if self.rt.core.in_fixpoint {
```

with:

```moonbit
  if self.rt.core.phase is InFixpoint {
```

- [ ] **Step 5: Update push_propagate.mbt phase transitions**

In `Runtime::push_propagate_from` (line ~129), replace:

```moonbit
  self.core.in_push_propagation = true
```

with:

```moonbit
  self.enter_phase(PushPropagating)
```

At the end (line ~252), replace:

```moonbit
  self.core.in_push_propagation = false
```

with:

```moonbit
  self.leave_phase()
```

- [ ] **Step 6: Update push_reactive.mbt guard sites**

In the `Reactive` constructor (line ~88), replace:

```moonbit
  guard !rt.core.in_push_propagation else {
```

with:

```moonbit
  guard !(rt.core.phase is PushPropagating) else {
```

At line ~91, replace:

```moonbit
  guard !rt.core.in_fixpoint else {
```

with:

```moonbit
  guard !(rt.core.phase is InFixpoint) else {
```

- [ ] **Step 7: Update datalog_fixpoint.mbt phase transitions**

In `Runtime::fixpoint` (line ~13), replace:

```moonbit
  if self.core.in_fixpoint {
```

with:

```moonbit
  if self.core.phase is InFixpoint {
```

At line ~30, replace:

```moonbit
  self.core.in_fixpoint = true
```

with:

```moonbit
  self.enter_phase(InFixpoint)
```

At line ~90, replace:

```moonbit
  self.core.in_fixpoint = false
```

with:

```moonbit
  self.leave_phase()
```

- [ ] **Step 8: Update datalog_relation.mbt guard site**

In `Relation::insert` (line ~111), replace:

```moonbit
  if self.rt.core.in_fixpoint {
```

with:

```moonbit
  if self.rt.core.phase is InFixpoint {
```

- [ ] **Step 9: Update datalog_functional_relation.mbt guard sites**

At line ~114 and ~164, replace both:

```moonbit
  if self.rt.core.in_fixpoint {
```

with:

```moonbit
  if self.rt.core.phase is InFixpoint {
```

- [ ] **Step 10: Update gc_wbtest.mbt**

In the whitebox test (line ~89-91), replace:

```moonbit
test "in_push_propagation: false by default" {
  let rt = Runtime()
  inspect(rt.core.in_push_propagation, content="false")
```

with:

```moonbit
test "phase: Idle by default" {
  let rt = Runtime()
  inspect(rt.core.phase, content="Idle")
```

- [ ] **Step 11: Run moon check**

Run: `moon check 2>&1`
Expected: PASS (all references to old fields are gone)

- [ ] **Step 12: Run moon test**

Run: `moon test 2>&1`
Expected: All 508+ tests pass

- [ ] **Step 13: Commit**

```bash
git add cells/
git commit -m "refactor: migrate all guard sites to PropagationPhase checks"
```

---

## Task 3: Add Phase Transition Tests

**Files:**
- Create: `cells/phase_test.mbt`

- [ ] **Step 1: Write tests for valid and invalid phase transitions**

Create `cells/phase_test.mbt`:

```moonbit
///|
test "phase: starts at Idle" {
  let rt = Runtime()
  inspect(rt.core.phase, content="Idle")
}

///|
test "phase: enter and leave PushPropagating" {
  let rt = Runtime()
  rt.enter_phase(PushPropagating)
  inspect(rt.core.phase, content="PushPropagating")
  rt.leave_phase()
  inspect(rt.core.phase, content="Idle")
}

///|
test "phase: enter and leave InFixpoint" {
  let rt = Runtime()
  rt.enter_phase(InFixpoint)
  inspect(rt.core.phase, content="InFixpoint")
  rt.leave_phase()
  inspect(rt.core.phase, content="Idle")
}

///|
test "phase: enter and leave GarbageCollecting" {
  let rt = Runtime()
  rt.enter_phase(GarbageCollecting)
  inspect(rt.core.phase, content="GarbageCollecting")
  rt.leave_phase()
  inspect(rt.core.phase, content="Idle")
}

///|
test "panic phase: enter PushPropagating while InFixpoint" {
  let rt = Runtime()
  rt.enter_phase(InFixpoint)
  rt.enter_phase(PushPropagating) |> ignore
}

///|
test "panic phase: enter InFixpoint while PushPropagating" {
  let rt = Runtime()
  rt.enter_phase(PushPropagating)
  rt.enter_phase(InFixpoint) |> ignore
}

///|
test "panic phase: enter GarbageCollecting while InFixpoint" {
  let rt = Runtime()
  rt.enter_phase(InFixpoint)
  rt.enter_phase(GarbageCollecting) |> ignore
}

///|
test "phase: gc sets GarbageCollecting phase" {
  let rt = Runtime()
  // gc() on an empty graph should succeed without error
  rt.gc()
  // After gc completes, phase should be back to Idle
  inspect(rt.core.phase, content="Idle")
}
```

- [ ] **Step 2: Run tests**

Run: `moon test -p dowdiness/incr/cells -f phase_test.mbt 2>&1`
Expected: All 8 tests pass (3 panic tests expect abort)

- [ ] **Step 3: Commit**

```bash
git add cells/phase_test.mbt
git commit -m "test: add phase transition tests for PropagationPhase"
```

---

## Task 4: Extract RevisionState Sub-Struct

**Files:**
- Modify: `cells/runtime.mbt`

- [ ] **Step 1: Define RevisionState struct**

Add above `RuntimeCore`:

```moonbit
///|
/// Revision tracking: global clock and per-durability change timestamps.
priv struct RevisionState {
  mut current_revision : Revision
  durability_last_changed : FixedArray[Revision]
}
```

- [ ] **Step 2: Replace fields in RuntimeCore**

In `RuntimeCore`, replace:

```moonbit
  mut current_revision : Revision
```

and (a few lines later):

```moonbit
  durability_last_changed : FixedArray[Revision]
```

with:

```moonbit
  revision : RevisionState
```

- [ ] **Step 3: Update Runtime::new initializer**

Replace the two field initializations:

```moonbit
      current_revision: Revision::initial(),
```

and:

```moonbit
      durability_last_changed: FixedArray::make(
        @incr_types.DURABILITY_COUNT,
        Revision::initial(),
      ),
```

with:

```moonbit
      revision: {
        current_revision: Revision::initial(),
        durability_last_changed: FixedArray::make(
          @incr_types.DURABILITY_COUNT,
          Revision::initial(),
        ),
      },
```

- [ ] **Step 4: Update all `self.core.current_revision` references**

Search and replace across `cells/`:

| Old | New |
|-----|-----|
| `self.core.current_revision` | `self.core.revision.current_revision` |
| `self.rt.core.current_revision` | `self.rt.core.revision.current_revision` |

Files affected: `runtime.mbt`, `verify.mbt`, `memo.mbt`, `hybrid_memo.mbt`, `push_propagate.mbt`, `signal.mbt`, `batch.mbt`, `datalog_fixpoint.mbt`.

- [ ] **Step 5: Update all `self.core.durability_last_changed` references**

| Old | New |
|-----|-----|
| `self.core.durability_last_changed` | `self.core.revision.durability_last_changed` |

Files affected: `runtime.mbt`, `verify.mbt`.

- [ ] **Step 6: Run moon check**

Run: `moon check 2>&1`
Expected: PASS

- [ ] **Step 7: Run moon test**

Run: `moon test 2>&1`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add cells/
git commit -m "refactor: extract RevisionState sub-struct from RuntimeCore"
```

---

## Task 5: Extract TrackingState Sub-Struct

**Files:**
- Modify: `cells/runtime.mbt`, `cells/tracking.mbt`

- [ ] **Step 1: Define TrackingState struct**

Add next to `RevisionState`:

```moonbit
///|
/// Dependency tracking: recording which cells are read during computation.
priv struct TrackingState {
  stack : Array[ActiveQuery]
}
```

- [ ] **Step 2: Replace field in RuntimeCore**

Replace:

```moonbit
  tracking_stack : Array[ActiveQuery]
```

with:

```moonbit
  tracking : TrackingState
```

- [ ] **Step 3: Update Runtime::new initializer**

Replace:

```moonbit
      tracking_stack: [],
```

with:

```moonbit
      tracking: { stack: [] },
```

- [ ] **Step 4: Update all `self.core.tracking_stack` references**

Search and replace across `cells/`:

| Old | New |
|-----|-----|
| `self.core.tracking_stack` | `self.core.tracking.stack` |
| `self.rt.core.tracking_stack` | `self.rt.core.tracking.stack` |

Files affected: `runtime.mbt` (gc guard), `tracking.mbt` (push/pop/record), `memo.mbt` (get guard), `hybrid_memo.mbt` (get guard), `signal.mbt` (if any).

- [ ] **Step 5: Run moon check then moon test**

Run: `moon check 2>&1 && moon test 2>&1`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add cells/
git commit -m "refactor: extract TrackingState sub-struct from RuntimeCore"
```

---

## Task 6: Extract BatchState Sub-Struct

**Files:**
- Modify: `cells/runtime.mbt`, `cells/batch.mbt`, `cells/signal.mbt`, `cells/pull_signal.mbt`, `cells/datalog_fixpoint.mbt`, `cells/batch_wbtest.mbt`, `cells/datalog_wbtest.mbt`

- [ ] **Step 1: Define BatchState struct**

Add next to `TrackingState`:

```moonbit
///|
/// Batch update management: deferred signal writes and rollback.
priv struct BatchState {
  mut depth : Int
  pending : Array[&Committable]
  frames : Array[BatchFrame]
  mut max_durability : Durability
}
```

- [ ] **Step 2: Replace fields in RuntimeCore**

Replace these four fields:

```moonbit
  mut batch_depth : Int
  batch_pending : Array[&Committable]
  batch_frames : Array[BatchFrame]
  mut batch_max_durability : Durability
```

with:

```moonbit
  batch : BatchState
```

- [ ] **Step 3: Update Runtime::new initializer**

Replace:

```moonbit
      batch_depth: 0,
      batch_pending: [],
      batch_frames: [],
      batch_max_durability: Low,
```

with:

```moonbit
      batch: { depth: 0, pending: [], frames: [], max_durability: Low },
```

- [ ] **Step 4: Update all batch field references**

Search and replace across `cells/`:

| Old | New |
|-----|-----|
| `self.core.batch_depth` | `self.core.batch.depth` |
| `self.rt.core.batch_depth` | `self.rt.core.batch.depth` |
| `rt.core.batch_depth` | `rt.core.batch.depth` |
| `self.core.batch_pending` | `self.core.batch.pending` |
| `self.core.batch_frames` | `self.core.batch.frames` |
| `self.core.batch_max_durability` | `self.core.batch.max_durability` |

Files affected: `batch.mbt` (most changes), `signal.mbt`, `pull_signal.mbt`, `runtime.mbt` (bump_revision, gc), `datalog_fixpoint.mbt`, `batch_wbtest.mbt`, `datalog_wbtest.mbt`.

- [ ] **Step 5: Run moon check then moon test**

Run: `moon check 2>&1 && moon test 2>&1`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add cells/
git commit -m "refactor: extract BatchState sub-struct from RuntimeCore"
```

---

## Task 7: Unify Subscriber Diff Logic

**Files:**
- Create: `cells/subscriber_diff.mbt`
- Modify: `cells/memo.mbt`, `cells/tracking.mbt`

- [ ] **Step 1: Write test for the shared diff function**

Create `cells/subscriber_diff_test.mbt`:

```moonbit
///|
test "diff_subscribers: add new deps" {
  let rt = Runtime()
  let s1 = Signal(rt, 1)
  let s2 = Signal(rt, 2)
  let m = Memo(rt, fn() { s1.get() })
  let obs = m.observe()
  // m currently depends on s1 only. Simulate a dep change to [s1, s2].
  let old_deps = [s1.id()]
  let new_deps = [s1.id(), s2.id()]
  rt.diff_and_update_subscribers(m.id(), old_deps, new_deps)
  // s2 should now have m as a subscriber
  let s2_subs = rt.dependents(s2.id())
  inspect(s2_subs.contains(m.id()), content="true")
  obs.dispose()
}

///|
test "diff_subscribers: remove old deps" {
  let rt = Runtime()
  let s1 = Signal(rt, 1)
  let s2 = Signal(rt, 2)
  let m = Memo(rt, fn() { s1.get() + s2.get() })
  let obs = m.observe()
  // m depends on [s1, s2]. Simulate dep change to [s1] only.
  let old_deps = [s1.id(), s2.id()]
  let new_deps = [s1.id()]
  rt.diff_and_update_subscribers(m.id(), old_deps, new_deps)
  // s2 should no longer have m as subscriber
  let s2_subs = rt.dependents(s2.id())
  inspect(s2_subs.contains(m.id()), content="false")
  obs.dispose()
}

///|
test "diff_subscribers: no change is no-op" {
  let rt = Runtime()
  let s1 = Signal(rt, 1)
  let m = Memo(rt, fn() { s1.get() })
  let obs = m.observe()
  let deps = [s1.id()]
  // Diff identical lists — should be a no-op
  rt.diff_and_update_subscribers(m.id(), deps, deps)
  let s1_subs = rt.dependents(s1.id())
  inspect(s1_subs.contains(m.id()), content="true")
  obs.dispose()
}
```

- [ ] **Step 2: Create the shared diff function**

Create `cells/subscriber_diff.mbt`:

```moonbit
///|
/// Diffs old_deps against new_deps and updates subscriber links.
///
/// Removes `cell_id` from subscribers of dropped deps, adds `cell_id`
/// to subscribers of new deps. Accepts an optional pre-built `new_seen`
/// set (from `pop_tracking`) to avoid rebuilding it.
///
/// Returns true if dependencies actually changed.
fn Runtime::diff_and_update_subscribers(
  self : Runtime,
  cell_id : CellId,
  old_deps : Array[CellId],
  new_deps : Array[CellId],
  new_seen? : @hashset.HashSet[CellId],
) -> Bool {
  let new_seen = match new_seen {
    Some(s) => s
    None => {
      let s : @hashset.HashSet[CellId] = @hashset.new()
      for dep in new_deps {
        s.add(dep)
      }
      s
    }
  }
  let mut changed = new_deps.length() != old_deps.length()
  let old_seen : @hashset.HashSet[CellId] = @hashset.new()
  for dep in old_deps {
    old_seen.add(dep)
    if !new_seen.contains(dep) {
      changed = true
    }
  }
  if changed {
    for dep in old_deps {
      if !new_seen.contains(dep) {
        self.remove_subscriber(dep, cell_id)
      }
    }
    for dep in new_deps {
      if !old_seen.contains(dep) {
        self.add_subscriber(dep, cell_id)
      }
    }
  }
  changed
}
```

- [ ] **Step 3: Run moon check**

Run: `moon check 2>&1`
Expected: PASS

- [ ] **Step 4: Run the new tests**

Run: `moon test -p dowdiness/incr/cells -f subscriber_diff_test.mbt 2>&1`
Expected: All 3 tests pass

- [ ] **Step 5: Commit shared function and tests**

```bash
git add cells/subscriber_diff.mbt cells/subscriber_diff_test.mbt
git commit -m "refactor: add shared diff_and_update_subscribers function"
```

---

## Task 8: Migrate memo_force_recompute to Use Shared Diff

**Files:**
- Modify: `cells/memo.mbt`

- [ ] **Step 1: Replace inline subscriber diff in memo_force_recompute**

In `Runtime::memo_force_recompute` (line ~404-424), replace this block:

```moonbit
  let (new_deps, new_seen) = self.pop_tracking()
  let mut deps_changed = new_deps.length() != old_deps.length()
  let old_seen : @hashset.HashSet[CellId] = @hashset.new()
  for dep in old_deps {
    old_seen.add(dep)
    if !new_seen.contains(dep) {
      deps_changed = true
    }
  }
  if deps_changed {
    for dep in old_deps {
      if !new_seen.contains(dep) {
        self.remove_subscriber(dep, cell_id)
      }
    }
    for dep in new_deps {
      if !old_seen.contains(dep) {
        self.add_subscriber(dep, cell_id)
      }
    }
  }
  cell.dependencies = new_deps
  if deps_changed {
    cell.meta.durability = compute_durability(self, new_deps)
  }
```

with:

```moonbit
  let (new_deps, new_seen) = self.pop_tracking()
  let deps_changed = self.diff_and_update_subscribers(
    cell_id, old_deps, new_deps, new_seen?,
  )
  cell.dependencies = new_deps
  if deps_changed {
    cell.meta.durability = compute_durability(self, new_deps)
  }
```

Note: The `new_seen?` optional parameter passes the pre-built set from `pop_tracking`, preserving the O(1) optimization.

- [ ] **Step 2: Run moon check then moon test**

Run: `moon check 2>&1 && moon test 2>&1`
Expected: All tests pass (including all cycle, backdating, dependency diff tests)

- [ ] **Step 3: Commit**

```bash
git add cells/memo.mbt
git commit -m "refactor: migrate memo_force_recompute to shared subscriber diff"
```

---

## Task 9: Migrate finish_tracking to Use Shared Diff

**Files:**
- Modify: `cells/tracking.mbt`

- [ ] **Step 1: Replace finish_tracking body with shared diff call**

Replace the body of `Runtime::finish_tracking` (lines ~147-166):

```moonbit
fn Runtime::finish_tracking(
  self : Runtime,
  cell_id : CellId,
  old_deps : Array[CellId],
  new_deps : Array[CellId],
) -> Unit {
  if old_deps.length() == 0 && new_deps.length() == 0 {
    return
  }
  let new_seen : @hashset.HashSet[CellId] = @hashset.new()
  for dep in new_deps {
    new_seen.add(dep)
  }
  let old_seen : @hashset.HashSet[CellId] = @hashset.new()
  for dep in old_deps {
    old_seen.add(dep)
    if !new_seen.contains(dep) {
      self.remove_subscriber(dep, cell_id)
    }
  }
  for dep in new_deps {
    if !old_seen.contains(dep) {
      self.add_subscriber(dep, cell_id)
    }
  }
}
```

with:

```moonbit
fn Runtime::finish_tracking(
  self : Runtime,
  cell_id : CellId,
  old_deps : Array[CellId],
  new_deps : Array[CellId],
) -> Unit {
  self.diff_and_update_subscribers(cell_id, old_deps, new_deps) |> ignore
}
```

- [ ] **Step 2: Run moon check then moon test**

Run: `moon check 2>&1 && moon test 2>&1`
Expected: All tests pass (including push reactive, effect, and hybrid tests)

- [ ] **Step 3: Commit**

```bash
git add cells/tracking.mbt
git commit -m "refactor: migrate finish_tracking to shared subscriber diff"
```

---

## Task 10: Final Verification and Cleanup

**Files:**
- Modify: `cells/runtime.mbt` (comment updates)

- [ ] **Step 1: Run full test suite**

Run: `moon test 2>&1`
Expected: All 508+ tests pass

- [ ] **Step 2: Run integration tests**

Run: `moon test -p dowdiness/incr/tests 2>&1`
Expected: All integration tests pass

- [ ] **Step 3: Run moon fmt and moon info**

Run: `moon info && moon fmt 2>&1`
Expected: No errors

- [ ] **Step 4: Check .mbti for unintended API changes**

Run: `git diff *.mbti`
Expected: No changes to public API (all changes are to `priv` types inside `cells/`)

- [ ] **Step 5: Commit any formatting changes**

```bash
git add -A
git diff --cached --stat  # verify only expected files
git commit -m "chore: run moon fmt and moon info after modularization"
```
