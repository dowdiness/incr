# Phase 4: Relation + Rule + Fixpoint

**Reference**: `docs/incr-unified-design.md` §3.5–3.6, §4.3, §7.6–7.7, §8 (Relation type erasure), §9, §10 Phase 4

## Goal

Add Datalog primitives: `Relation[T]` (set of tuples with delta tracking), `Rule` (derives new tuples from deltas), and `Runtime::fixpoint()` (semi-naive evaluation loop). Relations integrate with the pull verification system via `changed_at`, so pull memos can depend on relation results without special bridge code.

## Starting State

Phase 2 is complete (subscriber links). Phase 3 is **independent** — Phase 4 can be developed in parallel with Phase 3, or after it. The only hard requirement is Phase 2 (subscriber links and `get_subscribers`).

## Deliverables

| File | Action |
|------|--------|
| `cells/relation.mbt` | **Create** — `RelationData`, `RelationId[T]`, `Relation[T]` |
| `cells/rule.mbt` | **Create** — `RuleData`, `RuleId` |
| `cells/fixpoint.mbt` | **Create** — `Runtime::fixpoint` |
| `cells/cell_ref.mbt` | **Adapt** — add `Relation`, `Rule` variants |
| `cells/runtime.mbt` | **Adapt** — add `relations`/`rules` arrays; update `get_subscribers`, `get_changed_at`, `cell_id_for`, `ensure_up_to_date` |

## Step 1: Extend `CellRef`

```moonbit
pub enum CellRef {
  PullSignal(index : Int)
  PullMemo(index : Int)
  PushReactive(index : Int)   // Phase 3
  PushEffect(index : Int)     // Phase 3
  Disposed                    // Phase 3
  Relation(index : Int)       // new
  Rule(index : Int)           // new
}
```

## Step 2: Add data structs

```moonbit
struct RelationData {
  cell_id : CellId
  // Typed data lives in Ref[HashSet[T]] captured by Relation[T].
  // Runtime only needs these two closures for the fixpoint loop.
  drain_delta    : () -> Unit    // move delta into current; clear delta
  is_delta_empty : () -> Bool    // convergence check
  subscribers : @hashset.HashSet[CellId]
  mut changed_at : Revision
  mut changed : Bool
}

struct RuleData {
  cell_id : CellId
  label : String?
  apply_delta      : () -> Unit    // read input deltas, insert into output Relations
  input_relations  : Array[CellId]
  output_relations : Array[CellId]
}
```

## Step 3: `Relation[T]` user-facing struct and type erasure

The typed `HashSet[T]`s live in `Ref`s owned by the `Relation[T]` handle. `RelationData` closures capture the **same** `Ref`s — no Runtime dispatch needed for typed operations.

```moonbit
pub struct Relation[T : Eq + Hash] {
  id      : RelationId[T]
  rt      : Runtime
  current : Ref[@hashset.HashSet[T]]
  delta   : Ref[@hashset.HashSet[T]]
}

pub fn Relation[T : Eq + Hash](rt : Runtime) -> Relation[T] {
  let current : Ref[@hashset.HashSet[T]] = Ref(@hashset.new())
  let delta   : Ref[@hashset.HashSet[T]] = Ref(@hashset.new())
  let idx = rt.relations.length()
  let cell_id = rt.alloc_cell_id(CellRef::Relation(idx))
  rt.relations.push(RelationData {
    cell_id,
    drain_delta: fn() {
      for t in delta.val { current.val.insert(t) |> ignore }
      delta.val = @hashset.new()
    },
    is_delta_empty: fn() { delta.val.size() == 0 },
    subscribers: @hashset.new(),
    changed_at: rt.revision,
    changed: false,
  })
  Relation { id: RelationId { id: cell_id }, rt, current, delta }
}

pub fn Relation::insert[T : Eq + Hash](self, tuple : T) -> Bool {
  // Insert into delta if not already in current or delta
  if self.current.val.contains(tuple) || self.delta.val.contains(tuple) { return false }
  self.delta.val.insert(tuple) |> ignore
  true
}

pub fn Relation::contains[T : Eq + Hash](self, tuple : T) -> Bool {
  self.current.val.contains(tuple)
}

pub fn Relation::iter[T : Eq + Hash](self) -> Iter[T] {
  self.current.val.iter()
}

pub fn Relation::id[T : Eq + Hash](self) -> RelationId[T] {
  self.id
}
```

> **`iter` reads from `current`** (the post-fixpoint materialized set), not `delta`. Callers reading from inside a `Memo` compute function should call `relation_iter` after `fixpoint()` has been run.

## Step 4: Rule registration

```moonbit
pub fn Runtime::new_rule(
  self,
  inputs  : Array[CellId],
  outputs : Array[CellId],
  apply   : () -> Unit,
) -> RuleId {
  // Validate: each CellId in inputs/outputs must map to a Relation variant
  for id in inputs {
    match self.cell_index[id.id] {
      Relation(_) => ()
      _ => abort("new_rule: input CellId does not refer to a Relation")
    }
  }
  for id in outputs {
    match self.cell_index[id.id] {
      Relation(_) => ()
      _ => abort("new_rule: output CellId does not refer to a Relation")
    }
  }
  let idx = self.rules.length()
  let cell_id = self.alloc_cell_id(CellRef::Rule(idx))
  self.rules.push(RuleData {
    cell_id, label: None,
    apply_delta: apply,
    input_relations: inputs,
    output_relations: outputs,
  })
  RuleId { id: cell_id }
}
```

## Step 5: Implement `fixpoint`

Semi-naive evaluation: each iteration applies rules to the *delta* (new facts from the previous iteration), derives new facts, and repeats until no new facts are derived.

```moonbit
pub fn Runtime::fixpoint(self) -> Unit {
  // Phase 0: mark relations with pending external inserts
  for relation in self.relations { relation.changed = false }
  for relation in self.relations {
    if not((relation.is_delta_empty)()) { relation.changed = true }
  }

  // Precompute output-relation indices (only these can grow during fixpoint)
  let output_rel_indices : @hashset.HashSet[Int] = @hashset.new()
  for rule in self.rules {
    for out_id in rule.output_relations {
      match self.cell_index[out_id.id] {
        Relation(idx) => output_rel_indices.insert(idx) |> ignore
        _ => ()
      }
    }
  }

  while true {
    for rule in self.rules { (rule.apply_delta)() }

    // Convergence check: only output relations matter
    let mut any_derived = false
    for idx in output_rel_indices {
      if not((self.relations[idx].is_delta_empty)()) {
        any_derived = true
        self.relations[idx].changed = true
      }
    }
    if not(any_derived) { break }

    // Drain ALL deltas before next iteration
    for relation in self.relations { (relation.drain_delta)() }
  }

  // Final drain: flush remaining deltas (input-only relations, last iteration outputs)
  for relation in self.relations { (relation.drain_delta)() }

  // Bump revision if any relation changed; update changed_at
  let mut changed_relation_ids : Array[CellId] = []
  for i, relation in self.relations {
    if relation.changed {
      changed_relation_ids.push(self.cell_id_for(CellRef::Relation(i)))
    }
  }
  if changed_relation_ids.length() == 0 { return }

  self.advance_revision(Durability::Low)
  for relation in self.relations {
    if relation.changed { relation.changed_at = self.revision }
  }

  // Relation → push boundary (if Phase 3 is present)
  if self.has_push_subscribers(changed_relation_ids) {
    self.push_propagate_from(changed_relation_ids)
  }
}
```

> **If Phase 3 is not yet implemented**, `has_push_subscribers` always returns `false` and `push_propagate_from` is never called. The fixpoint is still correct.

## Step 6: Update helpers for Relation/Rule arms

```moonbit
// get_subscribers — add:
Relation(idx) => self.relations[idx].subscribers.iter()
Rule(_)       => Iter::empty()   // rules are not subscribable

// get_subscribers_mut — add:
Relation(idx) => self.relations[idx].subscribers
Rule(_)       => abort("get_subscribers_mut: Rule has no subscribers")

// get_changed_at — add:
Relation(idx) => self.relations[idx].changed_at
Rule(_)       => self.revision   // not directly readable

// cell_id_for — add:
Relation(idx) => self.relations[idx].cell_id
Rule(idx)     => self.rules[idx].cell_id

// ensure_up_to_date — add:
Relation(_) => Ok(())    // freshness via fixpoint()
Rule(_)     => Ok(())    // not directly readable
```

## Step 7: Cross-boundary pull dependency tracking

When a `Memo` compute function calls `relation.iter()`, `track_read` is called with the Relation's `CellId`. This records the Relation as a dependency of the memo. When `fixpoint()` bumps `revision` and updates `Relation.changed_at`, subsequent `memo.get()` calls find the memo stale and recompute.

No special bridge code is needed. The unified `CellId` space and existing `track_read` + `pull_verify` handle it automatically.

Add `relation.iter()` to call `track_read` before returning:

```moonbit
pub fn Relation::iter[T : Eq + Hash](self) -> Iter[T] {
  self.rt.track_read(self.id.id)   // record dependency if inside a Memo compute
  self.current.val.iter()
}
```

## Tests

```moonbit
test "transitive closure: edge(a,b) → path derivation" {
  let rt = Runtime::new()
  let edge = Relation[String](rt)
  let path = Relation[String](rt)
  let _ = rt.new_rule(
    [edge.id().id],
    [path.id().id],
    fn() {
      // path(x,y) :- edge(x,y)
      // path(x,z) :- path(x,y), edge(y,z)
      // (implemented by iterating deltas and inserting derived tuples)
    }
  )
  edge.insert("a-b") |> ignore
  edge.insert("b-c") |> ignore
  rt.fixpoint()
  inspect(path.contains("a-b"), content="true")
  inspect(path.contains("a-c"), content="true")  // transitive
  inspect(path.contains("a-a"), content="false") // no self-loop
}

test "fixpoint convergence: terminates on monotone rules" {
  // add facts, run fixpoint, verify loop terminates and result is stable
}

test "incremental update: add new edge, re-run fixpoint" {
  // existing paths preserved; only new paths computed from new edge
}

test "pull memo reads relation result after fixpoint" {
  let rt = Runtime::new()
  let rel = Relation[Int](rt)
  let m = Memo(rt, fn() { rel.iter().fold(0, fn(acc, x) { acc + x }) })
  rel.insert(1) |> ignore
  rel.insert(2) |> ignore
  rt.fixpoint()
  inspect(m.get(), content="3")
  rel.insert(3) |> ignore
  rt.fixpoint()
  inspect(m.get(), content="6")
}

test "relation changed_at updated correctly" {
  let rt = Runtime::new()
  let rel = Relation[Int](rt)
  let rev_before = rt.revision()
  rel.insert(1) |> ignore
  rt.fixpoint()
  inspect(rt.revision() > rev_before, content="true")
}
```

## Definition of Done

- All Phase 1 + Phase 2 tests pass
- All Phase 4 tests listed above pass
- `moon check` has no type errors
- Transitive closure test produces correct results
- Pull memo depending on a Relation correctly recomputes after `fixpoint()`
- Fixpoint terminates on all monotone rule sets
