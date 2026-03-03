# Datalog Primitives: Relation, Rule, Fixpoint (Phase 4)

**Goal:** Add Datalog primitives: `Relation[T]` (set of tuples with delta tracking), `Rule` (derives new facts from deltas), and `Runtime::fixpoint()` (semi-naive evaluation loop). Relations integrate with the pull verification system via `changed_at`, so pull memos can depend on relation results without a bridge layer.

**Architecture:** See `docs/incr-unified-design.md` §3.5–3.6, §4.3, §7.6–7.7, §8, §9 for data structures, type erasure pattern, and fixpoint algorithm.

**Prerequisite:** Phase 2 complete. Phase 3 is independent — Phase 4 can run in parallel with Phase 3.

**Tech Stack:** MoonBit. Validate with `moon check` and `moon test`.

---

### Scope

In scope:
- `Relation`, `Rule` variants added to `CellRef`
- `RelationData`, `RuleData` structs
- `relations : Array[RelationData]`, `rules : Array[RuleData]` added to Runtime
- `Relation[T]` user-facing struct with typed `Ref[HashSet[T]]` and type-erased closures in `RelationData`
- `RelationId[T]`, `RuleId` newtype handles
- `Runtime::new_rule` for registering rules
- `Runtime::fixpoint` semi-naive evaluation loop
- `Relation::iter` calls `track_read` for pull-side dependency tracking
- `get_subscribers`, `get_subscribers_mut`, `get_changed_at`, `cell_id_for` extended for new variants

Out of scope:
- HybridMemo (Phase 5)
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

In `cells/cell_ref.mbt`, add:

```moonbit
pub enum CellRef {
  PullSignal(index : Int)
  PullMemo(index : Int)
  PushReactive(index : Int)
  PushEffect(index : Int)
  Disposed
  Relation(index : Int)   // new
  Rule(index : Int)        // new
  // HybridMemo added in Phase 5
}
```

Update all existing `match` expressions to add wildcard arms for the new variants.

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

In `cells/relation.mbt`, define `RelationData` per `docs/incr-unified-design.md` §3.5. In `cells/rule.mbt`, define `RuleData` per §3.6. Add `RelationId[T]` and `RuleId` newtype handles.

In `cells/runtime.mbt`, add to `Runtime`:

```moonbit
relations : Array[RelationData]
rules     : Array[RuleData]
```

Initialize both to `[]` in `Runtime::new()`.

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
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt`
Expected: FAIL — `Relation::new` does not exist

**Step 3: Write minimal implementation**

In `cells/relation.mbt`, implement `Relation[T]` with typed `Ref[@hashset.HashSet[T]]` for `current` and `delta`, and type-erased `drain_delta` / `is_delta_empty` closures in `RelationData`. See `docs/incr-unified-design.md` §8 for the type erasure pattern.

The key type-erasure principle: `RelationData` closures capture the same `Ref`s as the `Relation[T]` handle — the Runtime never touches `T` directly.

Also add `Relation::delta_iter()` returning `Iter[T]` over `self.delta.val` — rule bodies use this to read only the new facts produced in the previous iteration. `Relation::iter()` continues to read from `current` (the materialized post-drain set).

**Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt`
Expected: PASS

**Step 5: Commit**

```bash
git add cells/relation.mbt cells/datalog_wbtest.mbt
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
    [input.id().id],
    [output.id().id],
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

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt`
Expected: FAIL on first test — `rt.new_rule` does not exist; PASS on panic test (abort fires)

**Step 3: Write minimal implementation**

In `cells/runtime.mbt`, implement `new_rule` per `docs/incr-unified-design.md` §7.7:
- Validate each input/output `CellId` maps to a `Relation` variant (abort otherwise)
- Push `RuleData` into `rt.rules`
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
test "fixpoint: transitive closure — edge(a,b)+edge(b,c) derives path(a,c)" {
  let rt = Runtime::new()
  let edge : Relation[(String, String)] = Relation::new(rt)
  let path : Relation[(String, String)] = Relation::new(rt)
  let _ = rt.new_rule(
    [edge.id().id],
    [path.id().id],
    fn() {
      // path(x,y) :- edge(x,y)  [semi-naive: only new edges this iteration]
      for e in edge.delta_iter() { path.insert(e) |> ignore }
      // path(x,z) :- path(x,y), edge(y,z)  [all known paths × all edges]
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
  let _ = rt.new_rule([rel.id().id], [rel.id().id], fn() { () })  // no-op rule
  rel.insert(1) |> ignore
  rt.fixpoint()  // must not loop forever
  inspect(rel.contains(1), content="true")
}
```

**Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/incr/cells -f datalog_wbtest.mbt`
Expected: FAIL — `rt.fixpoint` does not exist

**Step 3: Write minimal implementation**

Create `cells/fixpoint.mbt` with `Runtime::fixpoint` implementing semi-naive evaluation per `docs/incr-unified-design.md` §4.3 and §9:

1. Mark relations with non-empty deltas as `changed`
2. Loop: apply all rules to current deltas; check if any output relation got new facts; if not, break; drain all deltas before next iteration
3. Final drain after loop
4. If any relation changed: bump revision; update `changed_at` for changed relations
5. Optionally trigger `push_propagate_from` if Phase 3 is present

Add `Relation::delta_iter()` and `Relation::current_iter()` if needed by rule bodies (or use `Relation::iter()` post-drain).

**Step 4: Run full test suite**

Run: `moon test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add cells/fixpoint.mbt cells/datalog_wbtest.mbt
git commit -m "feat(datalog): implement Runtime::fixpoint with semi-naive evaluation"
```

---

### Task 6: Update helpers for Relation/Rule arms

**Files:**
- Modify: `cells/runtime.mbt`

**Step 1: Write the failing test**

Add to `cells/datalog_wbtest.mbt`:

```moonbit
///|
test "get_changed_at: relation changed_at updated by fixpoint" {
  let rt = Runtime::new()
  let rel : Relation[Int] = Relation::new(rt)
  let rev_before = rt.revision()
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

Extend `get_subscribers`, `get_subscribers_mut`, `get_changed_at`, `cell_id_for`, and `ensure_up_to_date` (in `pull_verify`) with `Relation` and `Rule` arms per `docs/incr-unified-design.md` §6.

Also add `track_read` call inside `Relation::iter` so pull memos record the relation as a dependency.

**Step 4: Run full test suite**

Run: `moon test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add cells/runtime.mbt cells/relation.mbt cells/datalog_wbtest.mbt
git commit -m "feat(datalog): extend helpers with Relation/Rule arms; track_read in Relation::iter"
```

---

### Acceptance Criteria

- All Phase 1 + Phase 2 tests pass
- All Phase 4 tests above pass
- `moon check` has no type errors
- Transitive closure test produces correct results
- Pull memo depending on a Relation correctly recomputes after `fixpoint()`
- Fixpoint terminates on all monotone rule sets
- `Relation::iter` calls `track_read` to record pull-side dependencies
