# HybridMemo Public API, Integration Tests, and Design Docs

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expose `HybridMemo` in the `@incr` public API, add integration tests exercising it via that API, and update `design.md` to document the hybrid push-pull model.

**Architecture:** Three independent tasks in order: (1) expose the type + add a `create_hybrid_memo` helper matching the `create_signal`/`create_memo` pattern; (2) write integration tests using only the public `@incr` API; (3) update `design.md` prose and the file/test maps. No new files beyond `tests/hybrid_test.mbt`.

**Tech Stack:** MoonBit, `moon test` for verification, `moon check` for type-checking.

---

## Background

`HybridMemo[T]` is declared `pub(all)` in `cells/hybrid_memo.mbt` but is not re-exported through the root facade (`incr.mbt`). Downstream users importing `@incr` cannot access it without going through the internal package directly. This task makes it a first-class citizen of the public API.

The three existing cell types follow this pattern:
- `incr.mbt` — `pub using @internal { type Signal, type Memo, ... }`
- `traits.mbt` — `create_signal`, `create_memo` helper functions that delegate to the cell constructors

`HybridMemo` needs the same treatment.

---

### Task 1: Re-export HybridMemo and add create_hybrid_memo helper

**Files:**
- Modify: `incr.mbt` (add `HybridMemo` to the `pub using @internal` block)
- Modify: `traits.mbt` (add `create_hybrid_memo` function and `Readable` impl)

**Step 1: Add HybridMemo to incr.mbt**

Open `incr.mbt`. The current `pub using @internal` block ends after `TrackedCell`. Add `HybridMemo`:

```moonbit
pub using @internal {
  type Runtime,
  type CellInfo,
  type Signal,
  type Memo,
  type MemoMap,
  type CycleError,
  type TrackedCell,
  type HybridMemo,
}
```

**Step 2: Verify type-check passes**

```bash
moon check
```

Expected: no errors. `HybridMemo[T]` is already `pub(all)` so adding it to the re-export block requires no other changes.

**Step 3: Add Readable impl for HybridMemo in traits.mbt**

`HybridMemo` should implement `Readable` like `Signal`, `Memo`, and `TrackedCell`.

In `cells/hybrid_memo.mbt`, check whether `HybridMemo::is_up_to_date` exists. It doesn't yet — but `Readable` requires `is_up_to_date`. Look at `Memo::is_up_to_date` for the pattern:

```moonbit
// In cells/memo.mbt (for reference):
pub fn[T] Memo::is_up_to_date(self : Memo[T]) -> Bool {
  let memo = self.rt.get_pull_memo(self.cell_id)
  memo.verified_at >= self.rt.current_revision
}
```

Add `HybridMemo::is_up_to_date` to `cells/hybrid_memo.mbt`, just before or after the `id()` method:

```moonbit
///|
/// Returns true if the hybrid memo's value is verified at the current revision.
pub fn[T] HybridMemo::is_up_to_date(self : HybridMemo[T]) -> Bool {
  let cell = self.rt.get_hybrid_memo(self.cell_id)
  cell.verified_at >= self.rt.current_revision
}
```

Then add the `Readable` impl in `traits.mbt`, after the existing `TrackedCell` impl:

```moonbit
///|
/// A hybrid memo is up-to-date when its verified_at matches the
/// runtime's current revision.
pub impl[T : Eq] Readable for HybridMemo[T] with is_up_to_date(self) {
  HybridMemo::is_up_to_date(self)
}
```

**Step 4: Add create_hybrid_memo helper in traits.mbt**

After `create_memo` and before `create_memo_map`, add:

```moonbit
///|
/// Creates a new hybrid memo using the database's runtime.
///
/// A hybrid memo receives dirty flags eagerly (via push propagation from
/// upstream signals) but verifies and recomputes lazily on `get()`. This
/// combines the low-latency notification of push-based invalidation with
/// the wasted-work avoidance of pull-based verification.
///
/// Use `HybridMemo` when:
/// - The memo sits between push-reactive nodes and pull-based memos
/// - You want push notifications to reach downstream reactives without
///   eagerly recomputing intermediate derived values
///
/// # Parameters
///
/// - `db`: Any type implementing `Database`
/// - `f`: The compute function for the hybrid memo
/// - `label`: An optional human-readable name for debugging
///
/// # Returns
///
/// A new hybrid memo associated with the database's runtime
pub fn[Db : Database, T : Eq] create_hybrid_memo(
  db : Db,
  f : () -> T,
  label? : String,
) -> HybridMemo[T] {
  HybridMemo::new(db.runtime(), f, label?)
}
```

**Step 5: Type-check**

```bash
moon check
```

Expected: no errors.

**Step 6: Run tests (should still all pass)**

```bash
moon test
```

Expected: all existing tests pass (currently 261). No new tests yet.

**Step 7: Commit**

```bash
git add incr.mbt traits.mbt cells/hybrid_memo.mbt
git commit -m "feat: expose HybridMemo in public @incr API

- Re-export HybridMemo via incr.mbt pub using @internal
- Add HybridMemo::is_up_to_date for Readable impl
- Add Readable impl for HybridMemo in traits.mbt
- Add create_hybrid_memo helper matching create_signal/create_memo pattern"
```

---

### Task 2: Integration tests for HybridMemo

**Files:**
- Create: `tests/hybrid_test.mbt`

Integration tests use only the public `@incr` API — no private field access, no `@internal` imports. They test end-to-end graph scenarios. Model them on `tests/integration_test.mbt`.

**Step 1: Create the test file**

Create `tests/hybrid_test.mbt` with the following tests. Each `///|` line is required by MoonBit's test runner.

```moonbit
///|
test "hybrid: basic get and update" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get() * 2)
  inspect(h.get(), content="2")
  s.set(5)
  inspect(h.get(), content="10")
}

///|
test "hybrid: create_hybrid_memo helper" {
  struct Db {
    rt : Runtime
  }
  impl Database for Db with runtime(self) { self.rt }
  let db = { rt: Runtime::new() }
  let s = create_signal(db, 3)
  let h = create_hybrid_memo(db, () => s.get() + 1)
  inspect(h.get(), content="4")
  s.set(10)
  inspect(h.get(), content="11")
}

///|
test "hybrid: is_up_to_date via Readable" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get())
  let _ = h.get()
  inspect(h.is_up_to_date(), content="true")
  s.set(2)
  inspect(h.is_up_to_date(), content="false")
  let _ = h.get()
  inspect(h.is_up_to_date(), content="true")
}

///|
test "hybrid: unchanged value does not propagate (backdating)" {
  // If the hybrid memo recomputes to the same value, downstream memos skip.
  let rt = Runtime::new()
  let s = Signal::new(rt, 2)
  let h = HybridMemo::new(rt, () => s.get() % 2) // always 0
  let mut count = 0
  let m = Memo::new(rt, () => {
    count = count + 1
    h.get() + 1
  })
  inspect(m.get(), content="1")
  inspect(count, content="1")
  s.set(4) // h still computes 0 → backdated → m should not recompute
  inspect(m.get(), content="1")
  inspect(count, content="1") // no recompute
}

///|
test "hybrid: diamond — signal → two hybrids → memo" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 3)
  let h1 = HybridMemo::new(rt, () => s.get() + 1)
  let h2 = HybridMemo::new(rt, () => s.get() * 2)
  let mut count = 0
  let m = Memo::new(rt, () => {
    count = count + 1
    h1.get() + h2.get()
  })
  inspect(m.get(), content="10") // (3+1) + (3*2) = 4 + 6 = 10
  inspect(count, content="1")
  s.set(5)
  inspect(m.get(), content="16") // (5+1) + (5*2) = 6 + 10 = 16
  inspect(count, content="2")
}

///|
test "hybrid: batch update — single revision" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 1)
  let y = Signal::new(rt, 2)
  let mut count = 0
  let h = HybridMemo::new(rt, () => {
    count = count + 1
    x.get() + y.get()
  })
  inspect(h.get(), content="3")
  inspect(count, content="1")
  rt.batch(fn() {
    x.set(10)
    y.set(20)
  })
  inspect(h.get(), content="30")
  inspect(count, content="2") // only one recompute despite two signal changes
}

///|
test "hybrid: chained hybrids" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h1 = HybridMemo::new(rt, () => s.get() + 1)
  let h2 = HybridMemo::new(rt, () => h1.get() * 10)
  inspect(h2.get(), content="20")
  s.set(2)
  inspect(h2.get(), content="30")
}

///|
test "hybrid: hybrid as dep of memo — pull chain" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 1)
  let h = HybridMemo::new(rt, () => s.get() * 2)
  let mut count = 0
  let m = Memo::new(rt, () => {
    count = count + 1
    h.get() + 1
  })
  inspect(m.get(), content="3")
  inspect(count, content="1")
  s.set(3)
  inspect(m.get(), content="7")
  inspect(count, content="2")
}
```

**Step 2: Run the new tests**

```bash
moon test -p dowdiness/incr/tests
```

Expected: all tests pass, including the 8 new hybrid ones.

**Step 3: Run full suite**

```bash
moon test
```

Expected: 269 total (261 + 8), all passing.

**Step 4: Commit**

```bash
git add tests/hybrid_test.mbt
git commit -m "test: integration tests for HybridMemo public API

Tests cover: basic get/update, create_hybrid_memo helper, Readable
is_up_to_date, backdating (unchanged value does not propagate),
diamond graph, batch updates, chained hybrids, and hybrid-as-dep-of-memo."
```

---

### Task 3: Update design.md

**Files:**
- Modify: `docs/design.md`

Three sections need updates:

**Step 1: Update the "Push vs. Pull vs. Hybrid" section**

Find this paragraph (around line 34):

> `incr` uses a pure pull-based strategy: `Signal::set()` only bumps a revision counter and records the change. All verification and recomputation happens lazily when `Memo::get()` is called.

Replace it with:

```markdown
`incr` started with a pure pull-based strategy and has since added a hybrid cell type:

- **`Signal`/`Memo`** — Pure pull. `Signal::set()` only bumps a revision counter. All verification and recomputation happens lazily when `Memo::get()` is called.
- **`HybridMemo`** — Hybrid push-pull. Receives dirty flags eagerly (push) when upstream signals change, but verifies and recomputes lazily on `get()` (pull). The dirty flag enables a fast-path skip when no relevant signal has changed, without a full dependency walk.
```

**Step 2: Add a new "HybridMemo" section after the Backdating section**

Find the line `## Durability Levels` and insert a new section before it:

```markdown
## HybridMemo — Hybrid Push-Pull Cells

### Motivation

Pure pull-based verification (`Memo`) has excellent worst-case avoidance: cells never recompute unless read. But when downstream push-reactive nodes (`Reactive`, `Effect`) subscribe to derived values, the push propagation must bridge through those derived values to notify the reactives. With pure pull cells, the bridge is transparent — push propagation does a BFS through pull cell subscriber lists — but no individual pull cell knows whether _it_ was affected by the change without walking its dep chain.

`HybridMemo` adds a single `dirty : Bool` flag. Push propagation sets it eagerly. This gives `get()` a meaningful fast path:

- **Fast path**: `not(dirty) && verified_at >= current_revision` → return cached value immediately, no dep walk.
- **Slow path**: call `pull_verify_hybrid`, which walks deps, recomputes if needed, and clears `dirty`.

### SoA Layout

`Runtime` adds two arrays for hybrid memos:

- **`hybrid_memos : Array[HybridMemoData]`** — SoA entries, one per `HybridMemo`. Like `PullMemoData` but with an additional `mut dirty : Bool` field.
- **`hybrid_dirty : Array[CellId]`** — Tracks which hybrids were dirtied during the current propagation wave. Cleared at the end of each `push_propagate_from` call to prevent unbounded growth.

`HybridMemoData` implements `CellOps` so it participates in the uniform `cell_ops` trait-object array alongside signals and pull memos.

### Push Propagation Through HybridMemos

`push_propagate_from` in `cells/propagate.mbt` does a BFS (`enqueue_push_subscribers`) to find push-reactive nodes downstream of changed sources. HybridMemos are transparent bridges in this BFS:

```
HybridMemo(i) => {
  if not(self.hybrid_memos[i].dirty) {
    self.hybrid_memos[i].dirty = true
    self.hybrid_dirty.push(sub_id)
  }
  bfs_worklist.push(sub_id) // bridge through to reach downstream push nodes
}
```

This is the same treatment as `PullMemo` (which is also a transparent BFS bridge). The HybridMemo gets its dirty flag set, _and_ the BFS continues through it so downstream push-reactive and push-effect nodes are still found and enqueued.

### Verification of HybridMemo Dependencies

When a `PullMemo` or another `HybridMemo` has a `HybridMemo` as a dependency, the dep walk must call `pull_verify_hybrid` rather than just checking `changed_at`. A dirty `HybridMemo` has stale `changed_at` (it hasn't recomputed yet), so checking `changed_at` alone would give a false "nothing changed" answer. `pull_verify_hybrid` forces recomputation if needed before the `changed_at` check.

This is implemented in the `HybridMemo(_)` arm of both `pull_verify` (inner dep loop in `cells/verify.mbt`) and `pull_verify_hybrid`'s own dep loop.

### push_node_count Gate

`Signal::set_unconditional` only calls `push_propagate_from` when `push_node_count > 0`. `HybridMemo::new` increments `push_node_count` on creation, so even a graph with only signals and hybrid memos (no push reactives) correctly triggers push propagation.

```

**Step 3: Update the alien-signals "Ideas deferred" section**

Find the "Ideas deferred" subsection (around line 340). The subscriber links and push-pull hybrid bullets are out of date. Update them:

```markdown
### Ideas adopted (additions since initial implementation)

- **Subscriber (reverse) links**: `incr` now maintains bidirectional edges — each cell knows both its dependencies (forward) and its subscribers (reverse). Subscriber links enable push-based dirty propagation and are the foundation of `HybridMemo` and push-reactive cells.
- **Push-pull hybrid**: `HybridMemo` cells receive dirty flags via eager push propagation and verify/recompute lazily on `get()`. This is the hybrid model described above.

### Ideas deferred

- **Effect system**: alien-signals has first-class `Effect` nodes that trigger side effects when observed values change. `incr` has `Reactive` and `Effect` (push-based), but no higher-level effect abstraction integrated with the pull graph.
- **Automatic cleanup/GC**: alien-signals can garbage-collect unreachable nodes via subscriber reference counting. `incr` requires GC infrastructure (Phase 4 roadmap) before this is possible.
```

**Step 4: Update the Type Erasure / SoA section**

Find the numbered list of SoA arrays (around line 223). It currently lists 4 arrays. Add hybrid memos:

```markdown
1. **`pull_signals : Array[PullSignalData]`** — SoA entries for input cells (signals).
2. **`pull_memos : Array[PullMemoData]`** — SoA entries for derived cells (memos).
3. **`hybrid_memos : Array[HybridMemoData]`** — SoA entries for hybrid memo cells. Like `PullMemoData` but with an additional `dirty : Bool` flag set eagerly by push propagation.
4. **`cell_index : Array[CellRef]`** — Maps `CellId.id` → `PullSignal(idx)`, `PullMemo(idx)`, `HybridMemo(idx)`, `PushReactive(idx)`, `PushEffect(idx)`, or `Disposed` for O(1) dispatch.
5. **`cell_ops : Array[&CellOps]`** — Trait-object array indexed by `CellId.id`. `HybridMemoData` implements `CellOps` alongside signals and pull memos.
```

**Step 5: Update the File Map — cells/ table**

In the "cells/ package" table, add a row for `hybrid_memo.mbt` and `propagate.mbt` after `verify.mbt`:

```markdown
| `cells/hybrid_memo.mbt` | `HybridMemo[T]` — hybrid push-pull memo; `HybridMemoData` SoA entry with `dirty` flag |
| `cells/propagate.mbt` | `push_propagate_from`, `propagate_level_change` — level-sorted eager push propagation |
```

**Step 6: Update the File Map — Test files table**

Add a row for the new integration test and the whitebox test file:

```markdown
| `cells/hybrid_wbtest.mbt` | `HybridMemo` internal dirty flag, fast path, backdating, push propagation (whitebox) |
| `tests/hybrid_test.mbt` | `HybridMemo` public API: get, update, backdating, diamond, batch, chained, pull chain |
```

**Step 7: Verify mooncheck and tests**

```bash
moon check && moon test
```

Expected: all tests pass (269 total). No type errors.

**Step 8: Commit**

```bash
git add docs/design.md
git commit -m "docs: update design.md for HybridMemo push-pull model

- Update Push vs Pull vs Hybrid section to reflect HybridMemo
- Add HybridMemo section (motivation, SoA layout, propagation, verification)
- Update alien-signals comparison (subscriber links + hybrid now done)
- Update SoA array list and file maps"
```
