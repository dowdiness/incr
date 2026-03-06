# Datalog Primitives: Relation, Rule, Fixpoint

**Goal:** Add Datalog primitives: `Relation[T]` (set of tuples with delta tracking), `Rule` (derives new facts from deltas), and `Runtime::fixpoint()` (fixpoint evaluation loop). Relations integrate with the pull verification system via `changed_at`, so pull memos can depend on relation results without a bridge layer.

**Architecture:** See `docs/incr-unified-design.md` §3.5–3.6, §4.3, §7.6–7.7, §8, §9 for data structures, type erasure pattern, and fixpoint algorithm.

**Prerequisite:** Phases 1–3 and 4A–4C (HybridMemo) are complete. This plan builds on the existing SoA architecture, push propagation, and hybrid memo infrastructure.

**Tech Stack:** MoonBit. Validate with `moon check` and `moon test`.

---

### Scope

In scope:
- `Relation`, `Rule` variants added to `CellRef`
- `RelationData`, `RuleData` structs with `CellOps` implementations
- `relations : Array[RelationData]`, `rules : Array[RuleData]` added to Runtime
- `Relation[T]` user-facing struct with typed `Ref[HashSet[T]]` and type-erased closures in `RelationData`
- `RelationId[T]`, `RuleId` newtype handles
- Root `@incr` API re-exports `Relation` from `incr.mbt` (following the pattern where `SignalId`/`MemoId` are not re-exported, `RelationId`/`RuleId` are also not re-exported)
- `Runtime::new_rule` for registering rules
- `Runtime::fixpoint` fixpoint evaluation loop
- `Relation::iter` calls `record_dependency` for pull-side dependency tracking
- `cell_id_for` extended with `Relation`/`Rule` match arms
- `CellOps` implemented for `RelationData` and `RuleData` (enables `cell_ops`-based dispatch for `get_changed_at`, `get_subscribers`, etc.)
- `pull_verify` and `pull_verify_hybrid` extended with `Relation`/`Rule` match arms

Out of scope:
- Full Datalog query language (not in scope for `incr`)

---

### Task 1: Extend `CellRef` with `Relation` and `Rule` variants

**Files:**
- Modify: `cells/cell_ref.mbt`
- Create: `cells/datalog_wbtest.mbt`

**Step 1: Write the failing test**

Create `cells/datalog_wbtest.mbt`:

```moonbit
///|
test "cell_ref: Relation and Rule variants exist" {
  let a : CellRef = CellRef::Relation(0)
  let b : CellRef = CellRef::Rule(1)
  let ia = match a { Relation(i) => i; _ => -1 }
  let ib = match b { Rule(i) => i; _ => -1 }
  inspect(ia, content="0")
  inspect(ib, content="1")
}
```

**Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt -i 0`
Expected: FAIL — `Relation`, `Rule` variants do not exist

**Step 3: Write minimal implementation**

In `cells/cell_ref.mbt`, add the new variants to the existing enum:

```moonbit
pub enum CellRef {
  PullSignal(Int)
  PullMemo(Int)
  PushReactive(Int)
  PushEffect(Int)
  HybridMemo(Int)
  Disposed
  Relation(Int)    // new
  Rule(Int)        // new
}
```

Note: `HybridMemo(Int)` already exists — do not remove it.

Update all existing `match` expressions on `CellRef` to handle the new variants. Key locations:
- `cells/runtime.mbt`: `cell_id_for` — add `Relation(idx) => self.relations[idx].cell_id` and `Rule(idx) => self.rules[idx].cell_id`
- `cells/verify.mbt`: `pull_verify` outer match and inner dep-walk match — add `Relation(_) | Rule(_) => Ok(())` (freshness managed by `fixpoint()`) for the outer match; for the inner dep-walk, treat as leaf: `Relation(_) | Rule(_) => if self.cell_ops[dep_id.id].changed_at() > memo.verified_at { ... }`
- `cells/verify.mbt`: `pull_verify_hybrid` inner dep-walk match — same leaf treatment as above
- `cells/runtime.mbt`: `cell_info` — add arms returning `Some(CellInfo { ... })` or extend the `_ => None` wildcard
- `cells/runtime.mbt`: `collect_in_progress_path` — no change needed (Relations/Rules don't have `in_progress`)
- `cells/propagate.mbt`: `get_level` (line 32) uses exhaustive matching — add `Relation(_) | Rule(_) => 0`. Other propagate matches already use `_ => ()` wildcards and need no changes

**Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt -i 0`
Expected: PASS

**Step 5: Run full suite**

Run: `moon test`
Expected: All existing tests pass

**Step 6: Commit**

```bash
git add cells/cell_ref.mbt cells/datalog_wbtest.mbt
git commit -m "feat(datalog): extend CellRef with Relation and Rule variants"
```

---

### Task 2: Add `RelationData`, `RuleData` and arrays to Runtime

**Files:**
- Create: `cells/relation.mbt`
- Create: `cells/rule.mbt`
- Modify: `cells/runtime.mbt`

**Step 1: Write the failing test**

Add to `cells/datalog_wbtest.mbt`:

```moonbit
///|
test "runtime: relation and rule arrays start empty" {
  let rt = Runtime::new()
  inspect(rt.relations.length(), content="0")
  inspect(rt.rules.length(), content="0")
}
```

**Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt`
Expected: FAIL — `relations`, `rules` fields do not exist

**Step 3: Write minimal implementation**

In `cells/relation.mbt`, define `RelationData` per `docs/incr-unified-design.md` §3.5:

```moonbit
struct RelationData {
  cell_id : CellId
  drain_delta : () -> Unit
  is_delta_empty : () -> Bool
  subscribers : @hashset.HashSet[CellId]
  mut changed_at : Revision
  mut changed : Bool
  label : String?
  durability : Durability
}
```

Note: `label` and `durability` fields are required for the `CellOps` trait implementation. Default `durability` to `Low` since relations are typically populated with external data.

Implement `CellOps` for `RelationData`:

```moonbit
impl CellOps for RelationData with cell_id(self) { self.cell_id }
impl CellOps for RelationData with changed_at(self) { self.changed_at }
impl CellOps for RelationData with set_changed_at(self, rev) { self.changed_at = rev }
impl CellOps for RelationData with subscribers(self) { self.subscribers }
impl CellOps for RelationData with label(self) { self.label }
impl CellOps for RelationData with durability(self) { self.durability }
```

In `cells/rule.mbt`, define `RuleData` per §3.6:

```moonbit
struct RuleData {
  cell_id : CellId
  label : String?
  apply_delta : () -> Unit
  input_relations : Array[CellId]
  output_relations : Array[CellId]
  subscribers : @hashset.HashSet[CellId]
  mut changed_at : Revision
  durability : Durability
}
```

Implement `CellOps` for `RuleData`:

```moonbit
impl CellOps for RuleData with cell_id(self) { self.cell_id }
impl CellOps for RuleData with changed_at(self) { self.changed_at }
impl CellOps for RuleData with set_changed_at(self, rev) { self.changed_at = rev }
impl CellOps for RuleData with subscribers(self) { self.subscribers }
impl CellOps for RuleData with label(self) { self.label }
impl CellOps for RuleData with durability(self) { self.durability }
```

Add `RelationId[T]` and `RuleId` newtype handles.

In `cells/runtime.mbt`, add to `Runtime`:

```moonbit
priv relations : Array[RelationData]
priv rules     : Array[RuleData]
```

Initialize both to `[]` in `Runtime::new()`.

**Important:** `RelationData` and `RuleData` must implement `CellOps` so they can be pushed to `Runtime.cell_ops` at allocation time. This enables the existing `cell_ops`-based dispatch in `get_changed_at`, `get_subscribers`, `get_subscribers_mut`, etc. to work automatically — no match arms needed in those helpers. The `cell_id_for` match arms for `Relation`/`Rule` are already added in Task 1.

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt`
Expected: PASS

**Step 5: Run full suite**

Run: `moon test`
Expected: All existing tests pass

**Step 6: Commit**

```bash
git add cells/relation.mbt cells/rule.mbt cells/runtime.mbt cells/datalog_wbtest.mbt
git commit -m "feat(datalog): add RelationData, RuleData, and relation/rule arrays to Runtime"
```

---

### Task 3: Implement `Relation[T]` user-facing struct

**Files:**
- Modify: `cells/relation.mbt`
- Modify: `incr.mbt`

**Step 1: Write the failing test**

Add to `cells/datalog_wbtest.mbt`:

```moonbit
///|
test "relation: insert adds to delta, not current" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let inserted = rel.insert(42)
  inspect(inserted, content="true")
  inspect(rel.contains(42), content="false")  // not in current yet
}

///|
test "relation: duplicate insert returns false" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let _ = rel.insert(1)
  let dup = rel.insert(1)
  inspect(dup, content="false")
}
```

Note: The "iter reads from current (post-fixpoint)" test is deferred to Task 5 since it depends on `Runtime::fixpoint`.

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt`
Expected: FAIL — `Relation::new` does not exist

**Step 3: Write minimal implementation**

In `cells/relation.mbt`, implement `Relation[T]` with typed `Ref[@hashset.HashSet[T]]` for `current` and `delta`, and type-erased `drain_delta` / `is_delta_empty` closures in `RelationData`. See `docs/incr-unified-design.md` §8 for the type erasure pattern.

The key type-erasure principle: `RelationData` closures capture the same `Ref`s as the `Relation[T]` handle — the Runtime never touches `T` directly.

`Relation::new` must:
1. Allocate a `CellId` via `rt.alloc_cell_id(Relation(idx))`
2. Push `RelationData` to `rt.relations`
3. Push `&CellOps` (the `RelationData` entry) to `rt.cell_ops`

Also add `Relation::delta_iter()` returning `Iter[T]` over `self.delta.val` — rule bodies use this to read only the new facts produced in the previous iteration. `Relation::iter()` continues to read from `current` (the materialized post-drain set).

`incr.mbt` must re-export `Relation` by adding it to the existing `pub using @internal { ... }` block (alongside `Signal`, `Memo`, `HybridMemo`, etc.):

```moonbit
pub using @internal {
  // ... existing types ...
  type Relation,
}
```

Note: `RelationId` and `RuleId` are NOT re-exported, following the existing pattern where `SignalId` and `MemoId` are also not re-exported from the root package. Users access `CellId` via `Relation::id()` directly.

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt`
Expected: PASS

**Step 5: Commit**

```bash
git add cells/relation.mbt incr.mbt cells/datalog_wbtest.mbt
git commit -m "feat(datalog): implement Relation[T] with type-erased closures"
```

---

### Task 4: Implement `Runtime::new_rule`

**Files:**
- Modify: `cells/rule.mbt`
- Modify: `cells/runtime.mbt`

**Step 1: Write the failing test**

Add to `cells/datalog_wbtest.mbt`:

```moonbit
///|
test "new_rule: registers rule with input and output relations" {
  let rt = Runtime::new()
  let input : Relation[String] = Relation::new(rt)
  let output : Relation[String] = Relation::new(rt)
  let rule_id = rt.new_rule(
    [input.id()],
    [output.id()],
    fn() { () }
  )
  inspect(rt.rules.length(), content="1")
  let _ = rule_id  // just check it was created
}

///|
test "panic new_rule: non-relation cell_id in inputs aborts" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  rt.new_rule([sig.id()], [], fn() { () }) |> ignore
}
```

Note: `Relation::id()` returns `CellId` directly (same pattern as `Signal::id()`, `Memo::id()`, etc.), so `new_rule` takes `Array[CellId]`.

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt`
Expected: FAIL on first test — `rt.new_rule` does not exist; PASS on panic test (abort fires)

**Step 3: Write minimal implementation**

In `cells/runtime.mbt`, implement `new_rule` per `docs/incr-unified-design.md` §7.7:
- Allocate a `CellId` via `self.alloc_cell_id(Rule(idx))`
- Validate each input/output `CellId` maps to a `Relation` variant (abort otherwise)
- Push `RuleData` into `rt.rules`
- Push `&CellOps` (the `RuleData` entry) to `rt.cell_ops`
- Return `RuleId`

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt`
Expected: PASS

**Step 5: Commit**

```bash
git add cells/rule.mbt cells/runtime.mbt cells/datalog_wbtest.mbt
git commit -m "feat(datalog): implement Runtime::new_rule"
```

---

### Task 5: Implement `Runtime::fixpoint`

**Files:**
- Create: `cells/fixpoint.mbt`

**Step 1: Write the failing test**

Add to `cells/datalog_wbtest.mbt`:

```moonbit
///|
test "relation: iter reads from current (post-fixpoint)" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let _ = rel.insert(10)
  let _ = rel.insert(20)
  rt.fixpoint()
  let sum = rel.iter().fold(0, fn(acc, x) { acc + x })
  inspect(sum, content="30")
}

///|
test "fixpoint: transitive closure — edge(a,b)+edge(b,c) derives path(a,c)" {
  let rt = Runtime::new()
  let edge : Relation[(String, String)] = Relation::new(rt)
  let path : Relation[(String, String)] = Relation::new(rt)
  let _ = rt.new_rule(
    [edge.id()],
    [path.id()],
    fn() {
      // path(x,y) :- edge(x,y)  [only new edges this iteration]
      for e in edge.delta_iter() { path.insert(e) |> ignore }
      // path(x,z) :- path(x,y), edge(y,z)  [current × current join]
      for (px, py) in path.iter() {
        for (ey, ez) in edge.iter() {
          if py == ey { path.insert((px, ez)) |> ignore }
        }
      }
    }
  )
  edge.insert(("a", "b")) |> ignore
  edge.insert(("b", "c")) |> ignore
  rt.fixpoint()
  inspect(path.contains(("a", "b")), content="true")
  inspect(path.contains(("b", "c")), content="true")
  inspect(path.contains(("a", "c")), content="true")
  inspect(path.contains(("a", "a")), content="false")
}

///|
test "fixpoint: pull memo depending on relation recomputes after fixpoint" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let m = Memo::new(rt, () => rel.iter().fold(0, fn(acc, x) { acc + x }))
  rel.insert(1) |> ignore
  rel.insert(2) |> ignore
  rt.fixpoint()
  inspect(m.get(), content="3")
  rel.insert(3) |> ignore
  rt.fixpoint()
  inspect(m.get(), content="6")
}

///|
test "fixpoint: terminates when no new facts derived" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let _ = rt.new_rule([rel.id()], [rel.id()], fn() { () })  // no-op rule
  rel.insert(1) |> ignore
  rt.fixpoint()  // must not loop forever
  inspect(rel.contains(1), content="true")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt`
Expected: FAIL — `rt.fixpoint` does not exist

**Step 3: Write minimal implementation**

Create `cells/fixpoint.mbt` with `Runtime::fixpoint` implementing fixpoint evaluation per `docs/incr-unified-design.md` §4.3 and §9:

1. Mark relations with non-empty deltas as `changed`
2. Precompute unique output-relation indices from all rules (only these drive convergence)
3. Loop: apply all rules via `(rule.apply_delta)()`; check if any output relation has non-empty deltas; if not, break; drain all deltas before next iteration
4. Final drain after loop (flushes remaining deltas including input-only relations)
5. If any relation changed: call `self.advance_revision(Low)` and update `changed_at` to `self.current_revision` for changed relations
6. If `self.push_node_count > 0`, call `self.push_propagate_from(changed_ids)` for push-side subscribers

Note: The design doc §4.3 references `self.revision` — use `self.current_revision` (the actual field name). The design doc also references `self.has_push_subscribers()` — use `self.push_node_count > 0` (the existing gate pattern).

**Step 4: Run full test suite**

Run: `moon test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add cells/fixpoint.mbt cells/datalog_wbtest.mbt
git commit -m "feat(datalog): implement Runtime::fixpoint with fixpoint evaluation"
```

---

### Task 6: Integrate Relation with pull verification and dependency tracking

**Files:**
- Modify: `cells/relation.mbt`
- Modify: `cells/verify.mbt`

**Step 1: Write the failing test**

Add to `cells/datalog_wbtest.mbt`:

```moonbit
///|
test "get_changed_at: relation changed_at updated by fixpoint" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let rev_before = rt.current_revision
  rel.insert(1) |> ignore
  rt.fixpoint()
  let rel_idx = match rt.cell_index[rel.id().id] { Relation(i) => i; _ => abort("") }
  inspect(rt.relations[rel_idx].changed_at > rev_before, content="true")
}
```

**Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt`
Expected: FAIL

**Step 3: Write minimal implementation**

**`Relation::iter` dependency tracking:** Add `rt.record_dependency(self.cell_id)` inside `Relation::iter` so pull memos that read a relation automatically record it as a dependency.

**`pull_verify` and `pull_verify_hybrid` match coverage:** Both functions exhaustively match `CellRef` in their inner dependency-walk loops. Add arms for the new variants:

In `pull_verify` inner dep-walk (the match inside `while stack.length() > 0`):
```moonbit
Relation(_) | Rule(_) =>
  if self.cell_ops[dep_id.id].changed_at() > memo.verified_at {
    stack[top].changed = true
    stack[top].dep_cursor = memo.dependencies.length()
  }
```

In `pull_verify_hybrid` inner dep-walk:
```moonbit
Relation(_) | Rule(_) =>
  if self.cell_ops[dep_id.id].changed_at() > verified_at_snap {
    dep_changed = true
  }
```

These treat Relations as leaf nodes in the pull verification graph — their freshness is managed by `fixpoint()`, analogous to how `PushReactive` freshness is managed by `push_propagate_from`.

**No changes needed for `get_changed_at`, `get_subscribers`, `get_subscribers_mut`:** These helpers dispatch through `self.cell_ops[id.id]` (trait objects). Since `RelationData` and `RuleData` implement `CellOps` (Task 2), they work automatically.

**Step 4: Run full test suite**

Run: `moon test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add cells/relation.mbt cells/verify.mbt cells/datalog_wbtest.mbt
git commit -m "feat(datalog): integrate Relation with pull verification; record_dependency in Relation::iter"
```

---

### Task 7: Refresh generated API summaries after public API changes

**Files:**
- Modify: `pkg.generated.mbti`
- Modify: `cells/pkg.generated.mbti`

**Step 1: Regenerate API summaries**

Run: `moon info`
Expected: generated `.mbti` files include new public types and methods.

**Step 2: Commit**

```bash
git add pkg.generated.mbti cells/pkg.generated.mbti
git commit -m "chore(datalog): refresh generated API summaries"
```

---

### Acceptance Criteria

- All existing tests pass (273+ tests across all packages)
- All Datalog tests above pass
- `moon check` has no type errors
- Transitive closure test produces correct results
- Pull memo depending on a Relation correctly recomputes after `fixpoint()`
- Fixpoint terminates on all monotone rule sets
- `Relation::iter` calls `record_dependency` to record pull-side dependencies
- Root `@incr` API re-exports `Relation` (not `RelationId`/`RuleId`, following `SignalId`/`MemoId` pattern)
- `moon info` updated `pkg.generated.mbti` and `cells/pkg.generated.mbti` for public API changes
- `RelationData` and `RuleData` implement `CellOps` for trait-object dispatch
- `pull_verify` and `pull_verify_hybrid` handle `Relation`/`Rule` deps as leaf nodes
