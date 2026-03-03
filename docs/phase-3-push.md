# Phase 3: Push Reactive + Effect

**Reference**: `docs/incr-unified-design.md` §3.3–3.4, §4.2, §5 (Level Recomputation), §7.4–7.5, §10 Phase 3

## Goal

Add eager push-mode cells: `Reactive[T]` (derived, recomputed when upstream changes) and `Effect` (terminal, executes side effects). Push propagation uses a level-sorted priority queue to guarantee glitch-free recomputation in topological order.

## Starting State

Phase 2 is complete. Pull cells have subscriber links. `finish_tracking`, `get_subscribers`, `get_subscribers_mut` exist.

## Deliverables

| File | Action |
|------|--------|
| `cells/reactive.mbt` | **Create** — `PushReactiveData`, `ReactiveId[T]`, `Reactive[T]` |
| `cells/effect.mbt` | **Create** — `PushEffectData`, `EffectId`, `Effect` |
| `cells/propagate.mbt` | **Create** — `PushEntry`, `push_propagate_from`, `propagate_level_change`, `recompute_level`, `get_level` |
| `cells/cell_ref.mbt` | **Adapt** — add `PushReactive`, `PushEffect`, `Disposed` variants |
| `cells/runtime.mbt` | **Adapt** — add push arrays and free lists; update `commit_batch`, `get_subscribers`, `get_subscribers_mut`, `get_changed_at`, `cell_id_for`, `has_push_subscribers` |
| `moon.pkg` | **Adapt** — add `moonbitlang/core/priority_queue` dependency |

## Step 1: Extend `CellRef`

```moonbit
pub enum CellRef {
  PullSignal(index : Int)
  PullMemo(index : Int)
  PushReactive(index : Int)   // new
  PushEffect(index : Int)     // new
  Disposed                    // new: tombstone for disposed cells
  // Relation, Rule added in Phase 4
}
```

## Step 2: Add push data structs

```moonbit
struct PushReactiveData {
  cell_id : CellId
  label : String?
  compute : () -> Bool          // returns true if value changed
  mut sources : Array[CellId]   // cells this reactive reads
  subscribers : @hashset.HashSet[CellId]
  mut changed_at : Revision
  mut level : Int               // topological depth
  mut dirty : Bool
}

struct PushEffectData {
  cell_id : CellId
  label : String?
  execute : () -> Unit
  mut sources : Array[CellId]
  mut level : Int
  mut dirty : Bool
}
```

**Cycle-freedom**: Static cycles are impossible by construction — a cycle A→B→A would require `A.level > B.level` AND `B.level > A.level` simultaneously. `compute` returns `Bool`, not `Result[Bool, CycleError]`.

**No Durability field**: Push cells always propagate immediately. The `durability_last_changed` shortcut is pull-only and does not apply here.

## Step 3: Update Runtime struct

Add to Runtime:
```
├── push_reactives      : Array[PushReactiveData]
├── push_effects        : Array[PushEffectData]
├── free_push_reactives : Array[Int]    // recycled indices
└── free_push_effects   : Array[Int]    // recycled indices
```

## Step 4: Update `get_subscribers`, `get_subscribers_mut`, `get_changed_at`, `cell_id_for`

Add the new arms:

```moonbit
// get_subscribers — add:
PushReactive(idx) => self.push_reactives[idx].subscribers.iter()
PushEffect(_)     => Iter::empty()   // terminal; nothing subscribes to an effect
Disposed          => Iter::empty()

// get_subscribers_mut — add:
PushReactive(idx) => self.push_reactives[idx].subscribers
PushEffect(_)     => abort("get_subscribers_mut: PushEffect has no subscribers")
Disposed          => abort("get_subscribers_mut: cell has been disposed")

// get_changed_at — add:
PushReactive(idx) => self.push_reactives[idx].changed_at
PushEffect(_)     => self.revision   // effects have no changed_at; return current revision
Disposed          => abort("get_changed_at: cell has been disposed")

// cell_id_for — add:
PushReactive(idx) => self.push_reactives[idx].cell_id
PushEffect(idx)   => self.push_effects[idx].cell_id
Disposed          => abort("cell_id_for: called on a disposed cell")
```

## Step 5: Implement `PushEntry` and `push_propagate_from`

`@priority_queue.T[A]` is a **max-heap** (requires `A : Compare`). Negate level to get min-level-first ordering.

```moonbit
// In propagate.mbt:
priv struct PushEntry {
  neg_level : Int     // stored as -level
  cell_ref  : CellRef
}
impl Compare for PushEntry with compare(self, other) {
  self.neg_level.compare(other.neg_level)
}

fn Runtime::push_propagate_from(self, changed_sources : Array[CellId]) -> Unit {
  let update_queue : @priority_queue.T[PushEntry] = @priority_queue.new()

  fn enqueue_push_subscribers(source_id : CellId) -> Unit {
    for sub_id in self.get_subscribers(self.cell_index[source_id.id]) {
      match self.cell_index[sub_id.id] {
        PushReactive(i) => {
          if not(self.push_reactives[i].dirty) {
            self.push_reactives[i].dirty = true
            update_queue.push({ neg_level: -self.push_reactives[i].level,
                                cell_ref: CellRef::PushReactive(i) })
          }
        }
        PushEffect(i) => {
          if not(self.push_effects[i].dirty) {
            self.push_effects[i].dirty = true
            update_queue.push({ neg_level: -self.push_effects[i].level,
                                cell_ref: CellRef::PushEffect(i) })
          }
        }
        _ => ()
      }
    }
  }

  for changed_id in changed_sources { enqueue_push_subscribers(changed_id) }

  while not(update_queue.is_empty()) {
    let entry = update_queue.pop().unwrap()
    let queued_level = -entry.neg_level
    match entry.cell_ref {
      PushReactive(idx) => {
        let reactive = self.push_reactives[idx]
        if queued_level != reactive.level { continue }  // stale entry (lazy deletion)
        reactive.dirty = false
        let reactive_cell_id = self.cell_id_for(CellRef::PushReactive(idx))
        let old_sources = reactive.sources
        self.begin_tracking(reactive_cell_id)
        let changed = (reactive.compute)()
        let new_sources = self.end_tracking()
        self.finish_tracking(reactive_cell_id, old_sources, new_sources)
        reactive.sources = new_sources
        let new_level = self.recompute_level(reactive_cell_id, new_sources)
        if new_level != reactive.level {
          reactive.level = new_level
          self.propagate_level_change(reactive_cell_id, update_queue)
        }
        if changed {
          reactive.changed_at = self.revision
          enqueue_push_subscribers(reactive_cell_id)
        }
      }
      PushEffect(idx) => {
        let effect = self.push_effects[idx]
        if queued_level != effect.level { continue }
        effect.dirty = false
        let effect_cell_id = self.cell_id_for(CellRef::PushEffect(idx))
        let old_sources = effect.sources
        self.begin_tracking(effect_cell_id)
        (effect.execute)()
        let new_sources = self.end_tracking()
        self.finish_tracking(effect_cell_id, old_sources, new_sources)
        effect.sources = new_sources
        effect.level = self.recompute_level(effect_cell_id, new_sources)
      }
      _ => ()
    }
  }
}
```

## Step 6: Implement `propagate_level_change`

Called when a reactive's level changes; propagates the change to downstream push nodes. Uses lazy deletion — stale queue entries are skipped in the dequeue loop by checking `queued_level != node.level`.

```moonbit
fn Runtime::propagate_level_change(
  self,
  changed_cell : CellId,
  update_queue : @priority_queue.T[PushEntry],
) -> Unit {
  let queue = [changed_cell]
  while not(queue.is_empty()) {
    let parent = queue.pop()
    for sub_id in self.get_subscribers(self.cell_index[parent.id]) {
      match self.cell_index[sub_id.id] {
        PushReactive(i) => {
          let node = self.push_reactives[i]
          let new_level = self.recompute_level(sub_id, node.sources)
          if new_level != node.level {
            node.level = new_level
            if node.dirty {
              update_queue.push({ neg_level: -new_level, cell_ref: CellRef::PushReactive(i) })
            }
            queue.push(sub_id)
          }
        }
        PushEffect(i) => {
          let node = self.push_effects[i]
          let new_level = self.recompute_level(sub_id, node.sources)
          if new_level != node.level {
            node.level = new_level
            if node.dirty {
              update_queue.push({ neg_level: -new_level, cell_ref: CellRef::PushEffect(i) })
            }
          }
        }
        _ => ()
      }
    }
  }
}
```

## Step 7: Implement `recompute_level` and `get_level`

```moonbit
fn Runtime::recompute_level(self, _cell_id : CellId, sources : Array[CellId]) -> Int {
  let mut max_level = 0
  for s in sources {
    let l = self.get_level(s)
    if l > max_level { max_level = l }
  }
  max_level + 1
}

fn Runtime::get_level(self, cell_id : CellId) -> Int {
  match self.cell_index[cell_id.id] {
    PullSignal(_)     => 0
    PullMemo(_)       => 0   // pull cells are level-0 from push perspective
    PushReactive(idx) => self.push_reactives[idx].level
    _                 => 0
  }
}
```

## Step 8: Implement disposal

```moonbit
fn Runtime::dispose_reactive(self, cell_id : CellId) -> Unit {
  match self.cell_index[cell_id.id] {
    PushReactive(idx) => {
      let node = self.push_reactives[idx]
      // 1. Remove this cell from all sources' subscriber sets
      for src_id in node.sources {
        self.get_subscribers_mut(src_id).remove(cell_id)
      }
      // 2. Remove this cell from all subscribers' sources arrays
      for sub_id in node.subscribers {
        match self.cell_index[sub_id.id] {
          PushReactive(si) => {
            self.push_reactives[si].sources =
              self.push_reactives[si].sources.filter(fn(id) { id != cell_id })
          }
          PushEffect(si) => {
            self.push_effects[si].sources =
              self.push_effects[si].sources.filter(fn(id) { id != cell_id })
          }
          _ => ()
        }
      }
      // 3. Mark as disposed (tombstone)
      self.cell_index[cell_id.id] = Disposed
      // 4. Return index to free list for reuse
      self.free_push_reactives.push(idx)
    }
    _ => abort("dispose_reactive: cell is not a PushReactive")
  }
}
```

`dispose_effect` follows the same pattern (steps 1 and 3–4; effects have no subscribers so step 2 is skipped).

**Allocation with free list reuse**:
```moonbit
fn Runtime::new_reactive_id[T : Eq](self, compute_fn : () -> T) -> ReactiveId[T] {
  let reactive_ref : Ref[T?] = Ref(None)
  let compute : () -> Bool = fn() {
    let new_val = compute_fn()
    let changed = match reactive_ref.val { None => true; Some(prev) => prev != new_val }
    if changed { reactive_ref.val = Some(new_val) }
    changed
  }
  let idx = match self.free_push_reactives.pop() {
    Some(free_idx) => {
      // Reuse freed slot
      self.push_reactives[free_idx] = PushReactiveData { ... }
      self.cell_index[???] = PushReactive(free_idx)  // need to alloc new CellId
      free_idx
    }
    None => {
      let new_idx = self.push_reactives.length()
      let cell_id = self.alloc_cell_id(CellRef::PushReactive(new_idx))
      self.push_reactives.push(PushReactiveData {
        cell_id, label: None, compute,
        sources: [], subscribers: @hashset.new(),
        changed_at: self.revision, level: 1, dirty: false,
      })
      new_idx
    }
  }
  ReactiveId { id: self.push_reactives[idx].cell_id }
}
```

> **Note on free list reuse**: when reusing a freed index, a fresh `CellId` is still needed (the old one is disposed). Call `alloc_cell_id` with `PushReactive(free_idx)` to get the new CellId, then overwrite `push_reactives[free_idx]`.

## Step 9: Update `commit_batch`

Add push propagation call after revision bump. This requires updating `has_push_subscribers` to check for `PushReactive` and `PushEffect` subscribers:

```moonbit
fn Runtime::has_push_subscribers(self, cell_ids : Array[CellId]) -> Bool {
  for cell_id in cell_ids {
    for sub_id in self.get_subscribers(self.cell_index[cell_id.id]) {
      match self.cell_index[sub_id.id] {
        PushReactive(_) | PushEffect(_) => return true
        _ => ()
      }
    }
  }
  false
}
```

In `commit_batch`, after `advance_revision`:
```moonbit
if self.has_push_subscribers(changed_ids) {
  self.push_propagate_from(changed_ids)
}
```

## Step 10: User-facing structs

```moonbit
pub struct Reactive[T : Eq] {
  id         : ReactiveId[T]
  value_ref  : Ref[T?]       // None until first compute
  rt         : Runtime
}
pub fn Reactive[T : Eq](rt : Runtime, compute : () -> T) -> Reactive[T]
pub fn Reactive::get(self) -> T    // returns cached value; freshness guaranteed by push_propagate_from
pub fn Reactive::dispose(self) -> Unit

pub struct Effect { id : EffectId; rt : Runtime }
pub fn Effect(rt : Runtime, execute : () -> Unit) -> Effect
pub fn Effect::dispose(self) -> Unit
```

## Tests

```moonbit
test "basic reactive chain: Signal → Reactive → Effect" { ... }
test "glitch prevention: diamond dependency" {
  // a → b, a → c, b+c → d
  // d should see consistent (b,c) pair, never an intermediate state
}
test "early cutoff: downstream not recomputed when value unchanged" {
  // reactive returns same value; its subscribers should not be enqueued
}
test "dynamic dependency: reactive conditionally reads different signals" { ... }
test "effect ordering: effects execute after all reactives updated" { ... }
test "mixed pull/push: Memo reads a Reactive; Reactive reads a Signal" { ... }
test "dispose: disposed reactive is not reachable via subscriber walk" { ... }
test "dispose: sources' subscriber sets updated after dispose" { ... }
```

## Definition of Done

- All Phase 1 + Phase 2 tests pass
- All Phase 3 tests listed above pass
- `moon check` has no type errors (including `priority_queue` import in `moon.pkg`)
- A disposed reactive never appears in any subscriber walk
- Diamond dependency test confirms no glitch (Effect sees consistent intermediate state)
