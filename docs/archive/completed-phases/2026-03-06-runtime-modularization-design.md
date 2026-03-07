# Runtime Modularization Design

**Status:** Complete

**Goal:** Decompose the Runtime god object into a modular architecture using three complementary techniques: sub-structs for ownership boundaries, refunctionalized CellOps for open behavioral dispatch, and capability traits for method organization.

**Motivation:** Every new propagation mode (push, hybrid, datalog) requires editing every `match self.cell_index[...]` site — currently 16 across 4 files. This is the classic Expression Problem: defunctionalized `CellRef` dispatch makes adding new operations easy but adding new cell types hard.

---

## Problem Analysis

### Current: Defunctionalized Dispatch

`CellRef` is a closed enum with 8 variants. Behavioral dispatch is scattered across match sites:

| File | Match sites | Purpose |
|------|-------------|---------|
| `verify.mbt` | 4 | `pull_verify` outer + inner dep-walk, `pull_verify_hybrid` root + inner dep-walk |
| `push_propagate.mbt` | 5 | `get_level`, `propagate_level_change`, `push_propagate_from` (enqueue + dequeue × 2) |
| `runtime.mbt` | 6 | `get_pull_signal`, `get_pull_memo`, `get_hybrid_memo`, `cell_info`, `dispose_reactive`, `dispose_effect` |
| `datalog_rule.mbt` | 1 | `new_rule` validation |

Adding a new mode requires editing all 16 sites. This coupling is the primary modularization obstacle.

### Root Cause: Expression Problem

| Axis | Current approach | Cost of extension |
|------|-----------------|-------------------|
| New operation (e.g., `cell_info`) | Add a new match function | Easy — one new function |
| New cell type (e.g., Relation) | Edit every existing match | Hard — 16+ edit sites |

Since we add new cell types more often than new operations, refunctionalization is the correct direction.

---

## Design: Three-Layer Architecture

### Layer 1: Sub-Structs (Ownership Boundaries)

Group Runtime's 24 private fields by concern:

```moonbit
struct RuntimeCore {
  runtime_id : Int
  mut current_revision : Revision
  mut next_cell_id : Int
  tracking_stack : Array[ActiveQuery]
  durability_last_changed : FixedArray[Revision]
  // Batch state
  mut batch_depth : Int
  batch_pending : Array[&Committable]
  batch_frames : Array[BatchFrame]
  mut batch_max_durability : Durability
  mut on_change : (() -> Unit)?
  // Unified dispatch tables
  cell_index : Array[CellRef]
  cell_ops : Array[&CellOps]
}

struct PullState {
  pull_signals : Array[PullSignalData]
  pull_memos : Array[PullMemoData]
}

struct PushState {
  push_reactives : Array[PushReactiveData]
  push_effects : Array[PushEffectData]
  free_push_reactives : Array[Int]
  free_push_effects : Array[Int]
  mut push_node_count : Int
  hybrid_memos : Array[HybridMemoData]
  hybrid_dirty : Array[CellId]
}

struct DatalogState {
  mut in_fixpoint : Bool
  relations : Array[RelationData]
  rules : Array[RuleData]
}
```

Runtime becomes a composition:

```moonbit
pub(all) struct Runtime {
  priv core : RuntimeCore
  priv pull : PullState
  priv push : PushState
  priv datalog : DatalogState
}
```

**Benefit:** Reading `fixpoint()` shows it touches `self.datalog` + `self.core` — clear ownership. Reading `push_propagate_from()` shows it touches `self.push` + `self.core`.

**Migration:** Field access changes from `self.pull_signals` to `self.pull.pull_signals` (or just `self.pull.signals` after renaming). This is a mechanical find-and-replace refactor.

### Layer 2: Refunctionalized CellOps (Open Dispatch)

Extend `CellOps` with behavioral methods that replace CellRef match sites:

```moonbit
trait CellOps {
  // Existing data access (unchanged)
  cell_id(Self) -> CellId
  changed_at(Self) -> Revision
  set_changed_at(Self, Revision) -> Unit
  subscribers(Self) -> @hashset.HashSet[CellId]
  label(Self) -> String?
  durability(Self) -> Durability

  // NEW: Refunctionalized from CellRef matches
  /// Returns the topological level of this cell for push propagation.
  /// Pull cells and leaf cells return 0. Push reactives return their stored level.
  level(Self) -> Int

  /// Determines whether this cell's dependency has changed since `verified_at`.
  /// Used by `pull_verify` inner dep-walk to replace the CellRef match.
  ///
  /// - Signal: `self.changed_at > verified_at`
  /// - PushReactive/Effect: `self.changed_at > verified_at`
  /// - Relation/Rule: `self.changed_at > verified_at`
  /// - PullMemo: returns `None` (needs deep verification — caller pushes verify frame)
  /// - HybridMemo: returns `None` (needs deep verification via `pull_verify_hybrid`)
  ///
  /// Returns `Some(true)` if changed, `Some(false)` if fresh, `None` if deep
  /// verification is required (memo-like cells).
  dep_changed_since(Self, Revision) -> Bool?
}
```

**Key design decision:** `dep_changed_since` returns `Bool?` (Option):
- `Some(true)` — dep changed, short-circuit
- `Some(false)` — dep is fresh, continue
- `None` — needs deep verification (PullMemo, HybridMemo)

This cleanly separates leaf-cell freshness (5 cell types, trivial) from memo-style verification (2 cell types, complex). The caller only needs special handling for `None`.

#### Implementations

```moonbit
// Leaf cells — compare changed_at (5 implementations, all identical)
impl CellOps for PullSignalData with dep_changed_since(self, verified_at) {
  Some(self.changed_at > verified_at)
}
impl CellOps for PushReactiveData with dep_changed_since(self, verified_at) {
  Some(self.changed_at > verified_at)
}
impl CellOps for PushEffectData with dep_changed_since(self, verified_at) {
  Some(self.changed_at > verified_at)
}
impl CellOps for RelationData with dep_changed_since(self, verified_at) {
  Some(self.changed_at > verified_at)
}
impl CellOps for RuleData with dep_changed_since(self, verified_at) {
  Some(self.changed_at > verified_at)
}

// Memo-like cells — need deep verification
impl CellOps for PullMemoData with dep_changed_since(_, _) { None }
impl CellOps for HybridMemoData with dep_changed_since(_, _) { None }

// Level: leaf cells return 0, push reactives return stored level
impl CellOps for PullSignalData with level(_) { 0 }
impl CellOps for PullMemoData with level(_) { 0 }
impl CellOps for PushReactiveData with level(self) { self.level }
impl CellOps for PushEffectData with level(self) { self.level }
impl CellOps for HybridMemoData with level(_) { 0 }
impl CellOps for RelationData with level(_) { 0 }
impl CellOps for RuleData with level(_) { 0 }
```

#### Impact on `pull_verify` Inner Dep-Walk

Before (16 match arms across `pull_verify` + `pull_verify_hybrid`):

```moonbit
match self.cell_index[dep_id.id] {
  PullSignal(sig_idx) =>
    if self.pull_signals[sig_idx].changed_at > memo.verified_at { ... }
  PushReactive(_) | PushEffect(_) =>
    if self.cell_ops[dep_id.id].changed_at() > memo.verified_at { ... }
  Relation(_) | Rule(_) => {
    if self.in_fixpoint { abort(...) }
    if self.cell_ops[dep_id.id].changed_at() > memo.verified_at { ... }
  }
  HybridMemo(_) =>
    match self.pull_verify_hybrid(dep_id) { ... }
  PullMemo(dep_idx) => { /* complex frame push logic */ }
  Disposed => abort(...)
}
```

After:

```moonbit
let dep_ops = self.core.cell_ops[dep_id.id]
match dep_ops.dep_changed_since(memo.verified_at) {
  Some(true) => {
    // Dep changed — short-circuit
    stack[top].changed = true
    stack[top].dep_cursor = memo.dependencies.length()
  }
  Some(false) => () // Dep is fresh, continue to next dep
  None => {
    // Needs deep verification — only PullMemo and HybridMemo reach here
    match self.core.cell_index[dep_id.id] {
      PullMemo(dep_idx) => { /* existing frame push logic */ }
      HybridMemo(_) =>
        match self.pull_verify_hybrid(dep_id) { ... }
      _ => () // unreachable — only memo-like cells return None
    }
  }
}
```

The match on `CellRef` is reduced from 8 arms to 2 (only the memo-like cells that need deep verification). The common case (5 leaf cell types) is fully dispatched through the trait.

**Fixpoint guard:** The `in_fixpoint` check for Relation deps is handled inside `RelationData::dep_changed_since`:

```moonbit
impl CellOps for RelationData with dep_changed_since(self, verified_at) {
  // Note: fixpoint guard is checked at the Relation::iter / Memo::get level,
  // not here — dep_changed_since is a pure freshness check
  Some(self.changed_at > verified_at)
}
```

The `in_fixpoint` abort stays in `pull_verify`'s outer match (the root cell dispatch), which is already a necessary match on `PullMemo` vs other cell types.

#### Impact on `get_level`

Before:

```moonbit
fn Runtime::get_level(self : Runtime, cell_id : CellId) -> Int {
  match self.cell_index[cell_id.id] {
    PullSignal(_) | PullMemo(_) => 0
    PushReactive(idx) => self.push_reactives[idx].level
    PushEffect(_) | HybridMemo(_) | Disposed | Relation(_) | Rule(_) => 0
  }
}
```

After:

```moonbit
fn Runtime::get_level(self : Runtime, cell_id : CellId) -> Int {
  if cell_id.id < 0 || cell_id.id >= self.core.cell_ops.length() {
    return 0
  }
  self.core.cell_ops[cell_id.id].level()
}
```

No CellRef match at all. Adding a new cell type = implement `level(Self) -> Int`.

#### Match Sites That Remain

Not all matches can be refunctionalized. These stay as CellRef matches:

| Match site | Why it stays |
|------------|-------------|
| `pull_verify` outer (root dispatch) | Must distinguish PullMemo (push verify frame) from non-memo (return Ok) |
| `pull_verify` inner `None` branch | Must distinguish PullMemo (push frame) from HybridMemo (call pull_verify_hybrid) |
| `push_propagate_from` enqueue | Must mark dirty flags on specific SoA arrays (HybridMemo vs PushReactive vs PushEffect) |
| `propagate_level_change` | Must access specific SoA arrays to update level and re-enqueue |
| `dispose_reactive/effect` | Must access specific SoA arrays to clear slots |
| `cell_info` | Must return mode-specific metadata (dependencies, verified_at) |
| `new_rule` validation | Must verify inputs are Relations |

These are structural operations (Solution 2 in the Expression Problem framework) — they need to observe the concrete cell type. The Two-Layer Architecture keeps `CellRef` for these while using `CellOps` for behavioral dispatch.

### Layer 3: Capability Traits (Method Organization)

Organize Runtime methods into small, focused traits:

```moonbit
/// Dependency tracking during computation
trait Tracker {
  push_tracking(Self, ActiveQuery) -> Unit
  pop_tracking(Self) -> (Array[CellId], @hashset.HashSet[CellId])
  record_dependency(Self, CellId) -> Unit
}

/// Revision management
trait RevisionManager {
  advance_revision(Self, Durability) -> Unit
  bump_revision(Self, Durability) -> Unit
}
```

`impl Tracker for Runtime`, `impl RevisionManager for Runtime`, etc. This is organizational — methods are grouped by concern, making the 1000+ line `runtime.mbt` navigable.

**Note:** These traits are not used for polymorphic dispatch — they're purely for code organization. They could equally be comment headers or separate files. The trait approach is preferred because:
1. MoonBit enforces one `impl Trait for Type with method` per method — naturally groups methods
2. IDE can show "all Tracker methods" as a navigation aid
3. The trait serves as documentation of the contract

---

## Two-Layer Architecture Summary

| Layer | Role | Pattern |
|-------|------|---------|
| `CellOps` trait (behavioral) | Open dispatch — new cell types implement trait methods | Refunctionalized (Finally Tagless for operations) |
| `CellRef` enum (structural) | Closed observation — introspection, disposal, allocation | Defunctionalized (concrete enum for structure) |

The `cell_ops : Array[&CellOps]` array is the "replay" bridge — it maps from a `CellId` (tag) to behavioral dispatch (trait object).

---

## Migration Strategy

### Phase 1: Add `level` and `dep_changed_since` to CellOps

**Low risk.** Add new methods to `CellOps`, implement on all 7 data structs. Existing code unchanged — new methods exist alongside old matches.

### Phase 2: Replace match sites with trait dispatch

**Medium risk.** One match site at a time:
1. `get_level` → `cell_ops[id].level()` (simplest, no fallback path)
2. `pull_verify_hybrid` inner dep-walk → `dep_changed_since` + `None` fallback
3. `pull_verify` inner dep-walk → same pattern
4. `pull_verify` outer dispatch → keep match but simplified

Each replacement is independently testable — all 295 existing tests must continue passing.

### Phase 3: Extract sub-structs

**Medium risk.** Mechanical find-and-replace: `self.pull_signals` → `self.pull.signals`. No behavioral changes. Can be done after or in parallel with Phase 2.

### Phase 4: Organize methods into capability traits

**Low risk.** Pure reorganization — move method impls under trait headers. No behavioral changes.

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `dep_changed_since` adds vtable call overhead on hot path | Benchmark before/after. The inner dep-walk is the hot path but `cell_ops` dispatch is already used there (`changed_at()` calls). Net effect should be neutral. |
| Sub-struct nesting adds field access depth | MoonBit structs are heap-allocated; `self.pull.signals[idx]` is two pointer chases vs one. Profile if concern arises. |
| `None` return from `dep_changed_since` requires fallback match | Only 2 of 7 cell types return `None`. The fallback match has 2 arms (PullMemo + HybridMemo) instead of 8. |
| Capability traits may hit orphan rule | All traits and types are in the same `cells` package — no orphan issues. |

---

## Non-Goals

- **Package split:** Stays in single `cells` package. Sub-structs provide logical separation without fighting MoonBit's package-level visibility.
- **Push propagation refunctionalization:** The `push_propagate_from` enqueue logic needs SoA-specific dirty flag access. Adding `notify_dirty` to CellOps is possible but low priority — push propagation already works well and rarely gains new cell types.
- **Full verify refunctionalization:** PullMemo's stack-based dep-walk stays in `verify.mbt`. Only the per-dep freshness check is refunctionalized. Moving the full walk into the cell type would require passing the verify stack through the trait, which adds complexity for no modularity gain.

---

## Implementation Notes

Notes from code review during implementation, for future reference.

### Two-Layer Dispatch in verify.mbt

The per-dependency inner loop in `pull_verify` and `pull_verify_hybrid` uses two `cell_index` lookups per dep in the worst case (memo-like deps), not one:

1. **Structural guard** (before `dep_changed_since`): Catches `Disposed` deps before calling trait methods on stale SoA slots. Also enforces the fixpoint guard for `Relation`/`Rule` deps.
2. **Behavioral dispatch** (`dep_changed_since` via `CellOps`): Returns `Some(true/false)` for leaf cells (5 of 7 types — the common fast path). Returns `None` for PullMemo and HybridMemo.
3. **Structural fallback** (only when `None`): A second `cell_index` lookup to distinguish PullMemo from HybridMemo for deep verification dispatch.

These two lookups serve different purposes and cannot be merged: the first is a precondition guard that must run before trait dispatch; the second is a type-specific dispatch that only runs for the 2-of-7 cell types returning `None`. For leaf deps (signals, reactives, effects — the common case in most graphs), only the first lookup + one trait call executes.

### HybridMemo Dirty Flag Invariant

Both early-exit paths in `pull_verify_hybrid` (fast path and durability shortcut) must be gated on `not(root.dirty)`. A dirty hybrid memo must always walk deps and potentially recompute, even if `verified_at >= current_revision` or durability hasn't changed. This matches `HybridMemo::get()` semantics. The `dirty` flag is cleared by `HybridMemo::get()` after verification succeeds, not by `pull_verify_hybrid`.

### Capability Traits (Tracker, RevisionManager)

These are `priv` traits with a single implementor (`Runtime`). They exist purely for code organization — grouping related methods under a trait name for navigability. All call sites invoke methods on a concrete `Runtime` value, never through a trait object. MoonBit resolves `impl Trait for Type with method` calls statically when the receiver type is known, so there is no vtable overhead.

### Sub-Struct Pointer Chases

`RuntimeCore`, `PullState`, `PushState`, and `DatalogState` are separate heap allocations. Every field access (e.g. `self.core.current_revision`) requires one extra pointer dereference compared to the old flat layout. In hot loops, the sub-struct pointers are cache-hot (dereferenced every iteration). Validate with `moon bench --release` if performance regressions are suspected.

### HybridMemo Placement in PushState

`hybrid_memos` and `hybrid_dirty` live in `PushState` despite HybridMemo participating in pull verification. Push propagation manages the `dirty` flag and `node_count` — these are the hot-path write fields. Pull verification's cross-boundary access to `self.push.hybrid_memos` is deliberate, not a structural leak.

### Silent `_ => ()` Arms in None Fallback

The `_ => ()` arms in the `None` branch of `dep_changed_since` (in both `pull_verify` and `pull_verify_hybrid`) are genuinely unreachable: only `PullMemoData` and `HybridMemoData` override `dep_changed_since` to return `None`. Using `abort("unreachable")` was considered but rejected — if a future cell type legitimately returns `None` and has its own verification path, aborting would be incorrect. The `_ => ()` with comments is the defensive choice.

---

## References

- Expression Problem: Wadler (1998). CellRef matches are the defunctionalized "apply" sites.
- Finally Tagless: Carette, Kiselyov, Shan (2009). CellOps behavioral methods are the refunctionalized interpretation.
- Two-Layer Architecture: Concrete enum (CellRef) for structural observation + trait (CellOps) for open behavioral dispatch.
- MoonBit trait constraints: Self-based, no type parameters, no associated types. All CellOps method signatures use concrete domain types — no workarounds needed.
