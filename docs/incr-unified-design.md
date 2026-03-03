# incr Unified Reactive Runtime — Design Specification

## 1. Overview

This document specifies a redesign of the `incr` library to support three propagation modes (Pull, Push, Hybrid) within a single Runtime, using a **SoA (Struct of Arrays) + per-kind struct** architecture.

### Goals

- **Pull mode** (current): Salsa-style demand-driven computation for compilers / language servers
- **Push mode** (new): SolidJS-style eager propagation for UI frameworks
- **Hybrid mode** (new): Push dirty flags + lazy pull verification
- **Datalog support** (new): Push-based Relation/Rule/Fixpoint primitives for bottom-up evaluation
- **Zero unnecessary memory**: Each cell kind carries only its required fields
- **Minimal dispatch overhead**: Intra-kind operations use direct array access; cross-kind operations use a single `CellRef` match

### Non-Goals

- This design does NOT replace an external ECS framework. `incr` and ECS remain independent libraries that can be connected via a thin bridge layer.
- This design does NOT implement a full Datalog engine. It provides the reactive primitives (Relation, Rule, Fixpoint) on which a Datalog engine can be built.

### Repository

- <https://github.com/dowdiness/incr>

---

## 2. Architecture

### 2.1 SoA Storage

Each cell kind is stored in its own typed array. A central `CellRef` enum maps a unified `CellId` to a specific kind + index.

```
Runtime
├── runtime_id     : Int                        // unique ID for cross-runtime safety
├── pull_signals   : Array[PullSignalData[?]]   // type-erased internally
├── pull_memos     : Array[PullMemoData[?]]
├── push_reactives : Array[PushReactiveData[?]]
├── push_effects   : Array[PushEffectData]
├── relations      : Array[RelationData[?]]
├── rules          : Array[RuleData]
├── cell_index     : Array[CellRef]             // CellId.id → CellRef
├── revision       : Revision
├── tracking_stack : Array[ActiveQuery]         // automatic dependency tracking
├── next_cell_id   : Int                        // monotonic cell ID allocator (existing)
├── durability_last_changed : FixedArray[Revision]  // per-durability revision (existing)
├── on_change      : (() -> Unit)?              // global change callback (existing)
├── batch_depth    : Int                        // nested batch tracking (existing)
├── batch_frames   : Array[BatchFrame]          // nested batch rollback log (existing)
├── batch_pending_signals : Array[CellId]       // signals with pending values (existing)
├── batch_max_durability : Durability           // max durability of pending signals (existing)
├── free_push_reactives  : Array[Int]           // recycled PushReactive indices (Phase 3)
└── free_push_effects    : Array[Int]           // recycled PushEffect indices (Phase 3)
```

### 2.2 CellRef Dispatch

```moonbit
pub enum CellRef {
  PullSignal(index : Int)
  PullMemo(index : Int)
  PushReactive(index : Int)
  PushEffect(index : Int)
  Relation(index : Int)
  Rule(index : Int)
  Disposed  // tombstone for disposed cells (Phase 3)
}
```

Cross-kind operations (dependency recording, subscriber notification) go through a single `match` on `CellRef`. Intra-kind operations (pull verification walk, push level-sorted propagation, Datalog fixpoint loop) operate directly on the typed arrays with no match overhead.

### 2.3 External Handles (Newtype Pattern)

Users interact with type-safe newtype handles. These prevent misuse at compile time.

```moonbit
pub struct SignalId[T] { id : CellId }
pub struct MemoId[T] { id : CellId }
pub struct ReactiveId[T] { id : CellId }
pub struct EffectId { id : CellId }
pub struct RelationId[T] { id : CellId }
pub struct RuleId { id : CellId }
```

`CellId` retains its existing `{ runtime_id : Int, id : Int }` structure for cross-runtime safety. The `id` field is the index into `Runtime.cell_index`.

---

## 3. Cell Kind Definitions

### 3.1 Pull Signal

Input cell for demand-driven computation. Stores a value. No compute function.

```moonbit
struct PullSignalData {
  // -- value is NOT stored here; the typed Ref[T] lives in the
  //    Signal[T] handle held by user code (same as current design).
  //    The Runtime only stores the type-erased metadata below. --
  cell_id : CellId                         // reverse lookup: index → CellId
  label : String?                          // debugging / cycle error output
  mut changed_at : Revision
  mut durability : Durability
  subscribers : @hashset.HashSet[CellId]   // reverse links
  mut on_change : (() -> Unit)?            // per-cell change callback
}
```

**Note on type erasure**: The actual value of type `T` lives in a `Ref[T]` captured by the `Signal[T]` handle (matching the current implementation). `PullSignalData` stores only the metadata the Runtime needs: `changed_at` for verification, `subscribers` for push-dirty propagation, and `on_change` for callbacks. The typed API (`SignalId[T]`) ensures callers always get/set the correct type.

### 3.2 Pull Memo

Derived cell for demand-driven computation. Lazily recomputed on read.

```moonbit
struct PullMemoData {
  cell_id : CellId                          // reverse lookup: index → CellId
  label : String?                           // debugging / cycle error output
  compute : () -> Result[Bool, CycleError]  // recomputes; Ok(true) if value changed
  mut changed_at : Revision
  mut verified_at : Revision
  mut durability : Durability
  mut dependencies : Array[CellId]  // cells this memo reads
  subscribers : @hashset.HashSet[CellId]   // reverse links
  mut in_progress : Bool            // cycle detection flag
  mut on_change : (() -> Unit)?     // per-cell change callback
}
```

`compute` is a type-erased closure that:
1. Runs the user's function
2. Compares the result with the cached value
3. Updates the cached value if different
4. Returns `true` if the value changed (for early cutoff / backdating)

### 3.3 Push Reactive

Derived cell for eager computation. Recomputed immediately when upstream changes.

```moonbit
struct PushReactiveData {
  cell_id : CellId              // reverse lookup: index → CellId
  label : String?               // debugging
  compute : () -> Bool          // same semantics as PullMemoData.compute
  mut sources : Array[CellId]   // cells this reactive reads (updated on recompute)
  subscribers : @hashset.HashSet[CellId]   // cells that depend on this reactive
  mut changed_at : Revision     // last revision where value actually changed
  mut level : Int               // topological depth (recalculated when sources change)
  mut dirty : Bool              // marked during propagation
}
```

`level` is a cached topological depth. If a reactive's `sources` change, level updates must be propagated to downstream push nodes even when the reactive's value is unchanged.

**Cycle-freedom guarantee**: Static dependency cycles are impossible by construction. If reactive A reads reactive B, level assignment requires `A.level ≥ B.level + 1`. A cycle A → B → A would require `A.level > B.level` *and* `B.level > A.level` simultaneously — a contradiction. `compute` therefore returns `Bool` rather than `Result[Bool, CycleError]`; no runtime cycle detection is needed for the static case.

**Dynamic dependency caveat**: With dynamic deps, a user could construct a cycle at runtime (e.g. reactive A conditionally reads B, B conditionally reads A). This manifests as non-terminating level propagation and is a user error, not defended against — matching the behavior of SolidJS and similar reactive libraries.

### 3.4 Push Effect

Terminal node for side effects (DOM updates, logging, etc.). Never read by other cells.

```moonbit
struct PushEffectData {
  cell_id : CellId              // reverse lookup: index → CellId
  label : String?               // debugging
  execute : () -> Unit          // side effect function
  mut sources : Array[CellId]   // cells this effect reads (updated on recompute)
  mut level : Int               // recalculated when sources change
  mut dirty : Bool
}
```

### 3.5 Relation (Datalog)

Set of tuples with delta tracking for semi-naive evaluation.

```moonbit
struct RelationData {
  cell_id : CellId              // reverse lookup: index → CellId
  // type-erased; actual HashSet[T] lives in closures
  insert : (Unit) -> Bool       // insert tuple; returns true if new
  drain_delta : () -> Unit      // move delta to processing buffer
  is_delta_empty : () -> Bool   // check if delta is empty
  subscribers : @hashset.HashSet[CellId]   // downstream Rules and/or push cells
  mut changed_at : Revision     // for pull-side dependency tracking
  mut changed : Bool            // set true when new tuples inserted during fixpoint
}
```

### 3.6 Rule (Datalog)

Datalog rule that reads deltas from input Relations and inserts derived tuples into output Relations.

```moonbit
struct RuleData {
  cell_id : CellId              // reverse lookup: index → CellId
  label : String?               // debugging
  apply_delta : () -> Unit      // read input deltas, insert into output Relations
  input_relations : Array[CellId]
  output_relations : Array[CellId]
}
```

---

## 4. Propagation Algorithms

### 4.1 Pull Verification (existing, adapted)

Triggered by `MemoId[T]::get()`. Walks the dependency chain bottom-up to verify freshness.

```moonbit
// VerifyFrame tracks progress through one memo's dependency list.
struct VerifyFrame {
  cell_id   : CellId
  memo_idx  : Int         // index into self.pull_memos
  mut dep_cursor : Int    // next dependency index to inspect
  mut changed    : Bool   // true if any dep changed vs this memo's verified_at
}

fn Runtime::pull_verify(self, cell_id : CellId) -> Result[Unit, CycleError] {
  match self.cell_index[cell_id.id] {
    PullSignal(_) => Ok(())  // always fresh
    PullMemo(root_idx) => {
      let root = self.pull_memos[root_idx]
      if root.verified_at >= self.revision { return Ok(()) }
      if root.in_progress {
        return Err(CycleError::from_path(self.collect_in_progress_path(), cell_id))
      }

      // Explicit stack: avoids call-stack overflow on deep dependency graphs.
      // in_progress is set on push and cleared on pop, so a nested pull_verify
      // call triggered from inside compute() can still detect cycles.
      let stack : Array[VerifyFrame] = []
      root.in_progress = true
      stack.push({ cell_id, memo_idx: root_idx, dep_cursor: 0, changed: false })

      let mut err : CycleError? = None

      while not(stack.is_empty()) && err == None {
        let top = stack.length() - 1
        let memo = self.pull_memos[stack[top].memo_idx]

        if stack[top].dep_cursor < memo.dependencies.length() {
          // Advance cursor and inspect the next dependency.
          let dep_id = memo.dependencies[stack[top].dep_cursor]
          stack[top].dep_cursor += 1

          match self.cell_index[dep_id.id] {
            PullMemo(dep_idx) => {
              let dep = self.pull_memos[dep_idx]
              if dep.verified_at < self.revision {
                // Dep needs verification; push a new frame.
                if dep.in_progress {
                  err = Some(CycleError::from_path(
                    self.collect_in_progress_path(), dep_id))
                } else {
                  dep.in_progress = true
                  stack.push({ cell_id: dep_id, memo_idx: dep_idx,
                                dep_cursor: 0, changed: false })
                }
              } else {
                // Already verified this revision; check if its value changed.
                if dep.changed_at > memo.verified_at {
                  stack[top].changed = true
                }
              }
            }
            _ => {
              // PullSignal, PushReactive, Relation: check changed_at directly.
              if self.get_changed_at(dep_id) > memo.verified_at {
                stack[top].changed = true
              }
            }
          }

        } else {
          // All deps inspected; finalize this memo.
          let frame = stack.pop().unwrap()
          memo.in_progress = false

          if frame.changed {
            match (memo.compute)() {
              Ok(_) => ()   // recompute done; may backdate memo.changed_at
              Err(e) => { err = Some(e) }
            }
          }
          memo.verified_at = self.revision

          // Tell the parent frame whether this memo's value changed.
          if not(stack.is_empty()) {
            let parent_top = stack.length() - 1
            let parent_verified_at =
              self.pull_memos[stack[parent_top].memo_idx].verified_at
            if memo.changed_at > parent_verified_at {
              stack[parent_top].changed = true
            }
          }
        }
      }

      // Error path: clear in_progress for any frames still on the stack.
      for frame in stack {
        self.pull_memos[frame.memo_idx].in_progress = false
      }

      match err {
        Some(e) => Err(e)
        None => Ok(())
      }
    }
    _ => Ok(())  // push cells are handled by push_propagate_from
  }
}
```

### 4.2 Push Propagation (new)

Triggered by `Runtime::commit_batch()` (changed signals) and `Runtime::fixpoint()` (changed relations).

```moonbit
// Queue entry for level-sorted push propagation.
// @priority_queue.T[A] is a max-heap (requires A : Compare).
// Negating the level makes the lowest level sort highest, giving min-level-first order.
priv struct PushEntry {
  neg_level : Int     // stored as -level; highest neg_level = lowest actual level
  cell_ref  : CellRef
}
impl Compare for PushEntry with compare(self, other) {
  self.neg_level.compare(other.neg_level)
}
```

```
fn Runtime::push_propagate_from(self, changed_sources : Array[CellId]) -> Unit {
  // Frontier queue seeded by changed source cells in this transaction.
  // Dirty flags are marked eagerly; recomputation is deferred and processed
  // in topological (level-ascending) order to prevent glitches.
  // Early cutoff applies per-node: if a reactive recomputes to the same
  // value, its subscribers are not enqueued.
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
        _ => ()  // PullMemo/Rule: lazy or explicit pathways
      }
    }
  }

  for changed_id in changed_sources {
    enqueue_push_subscribers(changed_id)
  }

  // @priority_queue.T is a max-heap; PushEntry negates the level so the
  // lowest level is dequeued first. Stale entries from propagate_level_change
  // are detected by comparing the decoded queued_level against node.level.
  while not(update_queue.is_empty()) {
    let entry = update_queue.pop().unwrap()
    let queued_level = -entry.neg_level
    match entry.cell_ref {
      PushReactive(idx) => {
        let reactive = self.push_reactives[idx]
        // Skip stale entries: a level change may have re-queued this node
        // at a lower level; the old higher-level entry is now outdated.
        if queued_level != reactive.level { continue }
        reactive.dirty = false
        // Track dependencies during recompute (for dynamic deps)
        let reactive_cell_id = self.cell_id_for(CellRef::PushReactive(idx))
        let old_sources = reactive.sources
        self.begin_tracking(reactive_cell_id)
        let changed = (reactive.compute)()  // recompute
        let new_sources = self.end_tracking()
        // Update subscriber links and recalculate level if sources changed
        self.finish_tracking(reactive_cell_id, old_sources, new_sources)
        reactive.sources = new_sources
        let new_level = self.recompute_level(reactive_cell_id, new_sources)
        if new_level != reactive.level {
          reactive.level = new_level
          // Maintain topological invariant for descendants, even if
          // this reactive's value is unchanged.
          self.propagate_level_change(reactive_cell_id, update_queue)
        }
        if changed {
          reactive.changed_at = self.revision
          enqueue_push_subscribers(reactive_cell_id)
        }
      }
      PushEffect(idx) => {
        let effect = self.push_effects[idx]
        if queued_level != effect.level { continue }  // stale entry
        effect.dirty = false
        // Track dependencies during execute (for dynamic deps)
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

```
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
            // If already queued/dirty, push a new entry at the updated level.
            // The dequeue loop skips the old stale entry by comparing
            // queued_level against node.level (lazy deletion pattern).
            if node.dirty {
              update_queue.push({ neg_level: -new_level,
                                  cell_ref: CellRef::PushReactive(i) })
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
              update_queue.push({ neg_level: -new_level,
                                  cell_ref: CellRef::PushEffect(i) })
            }
          }
        }
        _ => ()
      }
    }
  }
}
```

### 4.3 Datalog Fixpoint (new)

Triggered explicitly by `Runtime::fixpoint()`.

```
fn Runtime::fixpoint(self) -> Unit {
  // Phase 0: mark relations that have pending external inserts as changed.
  // These facts were inserted before fixpoint() was called; they don't
  // drive convergence but do need their changed_at updated at the end.
  for relation in self.relations { relation.changed = false }
  for relation in self.relations {
    if not((relation.is_delta_empty)()) { relation.changed = true }
  }

  // Precompute unique output-relation indices (relations written to by rules).
  // Only these can grow during fixpoint; checking input-only relations would
  // cause a spurious extra iteration because their external deltas are still
  // undrained at the start of the loop.
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
    // Apply all Rules: read current deltas, insert derived tuples.
    for rule in self.rules { (rule.apply_delta)() }

    // Convergence check: only output relations count.
    // Input-only relations may still have undrained external deltas here;
    // including them would cause a spurious extra iteration.
    let mut any_derived = false
    for idx in output_rel_indices {
      if not((self.relations[idx].is_delta_empty)()) {
        any_derived = true
        self.relations[idx].changed = true
      }
    }
    if not(any_derived) { break }

    // Advance epoch: drain ALL deltas (including input-only) so the next
    // iteration processes only newly-derived facts.
    for relation in self.relations { (relation.drain_delta)() }
  }

  // Final drain: flush any deltas that remain after convergence
  // (input-only relations that triggered no further derivations,
  // or the last round's output deltas that ended the loop).
  for relation in self.relations { (relation.drain_delta)() }

  // Bump revision once if any relation changed during this fixpoint.
  let mut changed_relation_ids = []
  for i, relation in self.relations {
    if relation.changed {
      changed_relation_ids.push(self.cell_id_for(CellRef::Relation(i)))
    }
  }
  if changed_relation_ids.length() == 0 {
    return
  }

  self.advance_revision(Durability::Low)
  // Update changed_at ONLY for relations that actually changed (early cutoff)
  for relation in self.relations {
    if relation.changed {
      relation.changed_at = self.revision
    }
  }
  // Relation -> push boundary: schedule push dependents if any.
  if self.has_push_subscribers(changed_relation_ids) {
    self.push_propagate_from(changed_relation_ids)
  }
}
```

### 4.4 Cross-Kind Boundary: ensure_up_to_date

The unified entry point for reading any cell's value.

```
fn Runtime::ensure_up_to_date(self, cell_id : CellId) -> Result[Unit, CycleError] {
  match self.cell_index[cell_id.id] {
    PullSignal(_)    => Ok(())                        // always fresh
    PullMemo(_)      => self.pull_verify(cell_id) // lazy verification
    PushReactive(_)  => Ok(())                    // freshness via push_propagate_from
    PushEffect(_)    => Ok(())                    // terminal, not readable
    Relation(_)      => Ok(())                    // freshness via fixpoint
    Rule(_)          => Ok(())                    // not directly readable
  }
}
```

`get_changed_at(cell_id)` must include `PushReactive.changed_at` and `Relation.changed_at`, so pull memos can depend on push and Datalog outputs using the same verification rule.

`cell_id_for` is the reverse of `cell_index`: given a typed array index, return the owning `CellId`. Each data struct stores its `cell_id` at allocation time (set in `alloc_cell_id` before the struct is pushed to the array), making this a direct field read:

```moonbit
fn Runtime::cell_id_for(self, cell_ref : CellRef) -> CellId {
  match cell_ref {
    PullSignal(idx)   => self.pull_signals[idx].cell_id
    PullMemo(idx)     => self.pull_memos[idx].cell_id
    PushReactive(idx) => self.push_reactives[idx].cell_id
    PushEffect(idx)   => self.push_effects[idx].cell_id
    Relation(idx)     => self.relations[idx].cell_id
    Rule(idx)         => self.rules[idx].cell_id
    Disposed          => abort("cell_id_for: called on a disposed cell")
  }
}
```

**Allocation order**: `cell_id` must be known before the struct literal is constructed. In `alloc_cell_id(cell_ref)`, the runtime first appends a placeholder to `cell_index` (yielding the `id`), then constructs the `CellId { runtime_id, id }` and returns it. The data struct is built with this `CellId` and then pushed to the per-kind array in the same step.

---

## 5. Automatic Dependency Tracking

The existing `ActiveQuery` / tracking stack mechanism is shared across all modes. When any cell's compute function calls `get()` on another cell, the dependency is recorded.

```moonbit
fn Runtime::track_read(self, source_id : CellId) -> Unit {
  // Record that the currently-computing cell depends on source_id
  match self.tracking_stack.last() {
    Some(active_query) => active_query.record(source_id)
    None => ()  // reading outside a compute context; no tracking
  }
}
```

Two helpers bracket each compute call. The names avoid collision with push-mode terminology ("push" / "pop" are reserved for the propagation queue):

```moonbit
fn Runtime::begin_tracking(self, cell_id : CellId) -> Unit {
  // Push a fresh dependency-collection frame onto the tracking stack.
  self.tracking_stack.push(ActiveQuery::new(cell_id))
}

fn Runtime::end_tracking(self) -> Array[CellId] {
  // Pop the frame and return the collected dependencies as an array.
  // deps_array() converts the HashSet[CellId] to Array[CellId].
  self.tracking_stack.pop().unwrap().deps_array()
}
```

After a compute function finishes, the Runtime diffs old vs new dependencies and updates subscriber links accordingly:

```moonbit
fn Runtime::finish_tracking(self, cell_id : CellId, old_deps : Array[CellId], new_deps : Array[CellId]) -> Unit {
  // O(|old_deps| + |new_deps|) HashSet-based diff.
  // Build membership sets for fast lookup.
  let new_set : @hashset.HashSet[CellId] = @hashset.from_iter(new_deps.iter())
  let old_set : @hashset.HashSet[CellId] = @hashset.from_iter(old_deps.iter())

  // Remove self from deps that are no longer read.
  for dep in old_deps {
    if not(new_set.contains(dep)) {
      self.get_subscribers_mut(dep).remove(cell_id)
    }
  }

  // Add self to newly read deps.
  for dep in new_deps {
    if not(old_set.contains(dep)) {
      self.get_subscribers_mut(dep).insert(cell_id)
    }
  }
}
```

`get_subscribers_mut(dep)` dispatches on `cell_index[dep.id]` and returns a mutable reference to the appropriate kind's `subscribers` field.

### Level Recomputation (Push cells only)

When a PushReactive's sources change (detected by `finish_tracking` after each recomputation), its level must be recalculated. Since push cells support dynamic dependencies (conditionally reading different sources), level recomputation happens after every recompute that changes the source set:

```
fn Runtime::recompute_level(self, cell_id : CellId, sources : Array[CellId]) -> Int {
  let mut max_level = 0
  for s in sources {
    let l = self.get_level(s)
    if l > max_level { max_level = l }
  }
  max_level + 1
}

fn Runtime::get_level(self, cell_id : CellId) -> Int {
  match self.cell_index[cell_id.id] {
    PullSignal(_)      => 0
    PullMemo(_)        => 0   // pull cells are level 0 from push perspective
    PushReactive(idx)  => self.push_reactives[idx].level
    Relation(_)        => 0   // relations are input-level from push perspective
    _                  => 0
  }
}
```

**Dynamic dependency handling**: When a PushReactive's sources change after recomputation, the Runtime recalculates its level and then propagates any level deltas to downstream push nodes (`propagate_level_change`). This preserves the topological scheduling invariant even when the reactive's value is unchanged, while still avoiding unsafe global unmarking.

---

## 6. Batch Updates

Multiple `set` calls are buffered within a batch. Propagation happens on commit.

```moonbit
fn Runtime::batch(self, f : () -> Unit raise?) -> Unit raise? {
  self.batch_depth = self.batch_depth + 1
  self.batch_frames.push(BatchFrame::new())
  try {
    f!()
  } catch {
    e => {
      // Rollback: undo signal writes in reverse order (matches current impl)
      self.rollback_current_batch_frame()
      self.batch_depth = self.batch_depth - 1
      raise e
    }
  }
  self.complete_batch_frame_success()
  self.batch_depth = self.batch_depth - 1
  if self.batch_depth == 0 {
    self.commit_batch()
  }
}

fn Runtime::commit_batch(self) -> Unit {
  // Two-phase commit (matches current impl):
  // Phase 1: commit each signal's pending value, collect which changed
  // Phase 2: single revision bump if any changed
  let changed_ids = self.commit_pending_signals()
  if changed_ids.length() > 0 {
    self.advance_revision(self.batch_max_durability)
    // Push propagation runs if ANY changed signal has push subscribers.
    // This handles the pull→push boundary: a PullSignal change propagates
    // dirty flags through its subscribers to reach PushReactive/PushEffect
    // nodes, even though the signal itself is a pull cell.
    if self.has_push_subscribers(changed_ids) {
      self.push_propagate_from(changed_ids)
    }
    // Fire per-cell on_change callbacks, then global on_change
    self.fire_cell_callbacks(changed_ids)
    self.fire_on_change()
  }
  self.batch_pending_signals.clear()
  self.batch_max_durability = Low
}
```

For pull-only usage, `commit_batch` simply bumps the revision (no eager propagation). The `has_push_subscribers(changed_ids)` check walks subscriber links of changed signals — if all subscribers are PullMemo cells, push propagation is skipped.

Push reactives that changed during `push_propagate_from` stamp `PushReactive.changed_at = self.revision`. This is required so pull memos can safely depend on push reactives (`PullMemo <- PushReactive`) via `get_changed_at`.

Nested batches are supported: inner batch success merges undo entries into the parent frame; inner batch failure rolls back only the inner frame. This matches the current `BatchFrame`/`BatchUndo` infrastructure.

---

## 7. Public API Surface

### Relationship to Current API

The current implementation exposes `Signal[T]` and `Memo[T]` structs with constructor syntax (`Signal(rt, value)`) and methods (`signal.get()`). These user-facing structs are **preserved** — they continue to hold the typed value (`Ref[T]` / `T?`) and provide the ergonomic method API.

Internally, each `Signal[T]` / `Memo[T]` contains a `CellId` that maps to a `PullSignalData` / `PullMemoData` in the Runtime's SoA arrays. The newtype handles (`SignalId[T]`, `MemoId[T]`) are an internal implementation detail used by the Runtime for dispatch; they are **not** the primary user-facing API.

For new push cells, the API follows the same pattern: `Reactive[T]` struct with `reactive.get()` method, internally backed by `ReactiveId[T]` + `PushReactiveData`.

### 7.1 Runtime

```moonbit
pub fn Runtime::new(on_change? : () -> Unit) -> Runtime

// Batch (with rollback on error, matching current impl)
pub fn Runtime::batch(self, f : () -> Unit raise?) -> Unit raise?
pub fn Runtime::batch_result(self, f : () -> Unit raise?) -> Result[Unit, Error]

// Datalog
pub fn Runtime::fixpoint(self) -> Unit

// Introspection (future)
pub fn Runtime::revision(self) -> Revision

// Callbacks (matches current implementation)
pub fn Runtime::set_on_change(self, f : () -> Unit) -> Unit
pub fn Runtime::clear_on_change(self) -> Unit
```

### 7.2 Pull Signal

```moonbit
// Primary user-facing API (preserved)
pub fn Signal[T : Eq](rt : Runtime, value : T) -> Signal[T]
pub fn Signal::get(self) -> T
pub fn Signal::get_result(self) -> Result[T, CycleError]  // new
pub fn Signal::set(self, value : T) -> Unit

// Runtime-level ID API (internal/advanced)
fn Runtime::new_signal_id[T : Eq](self, value : T) -> SignalId[T]
fn Runtime::signal_get[T : Eq](self, id : SignalId[T]) -> T
fn Runtime::signal_set[T : Eq](self, id : SignalId[T], value : T) -> Unit
```

### 7.3 Pull Memo

```moonbit
// Primary user-facing API (preserved)
pub fn Memo[T : Eq](rt : Runtime, compute : () -> T) -> Memo[T]
pub fn Memo::get(self) -> T
pub fn Memo::get_result(self) -> Result[T, CycleError]
pub fn Memo::get_or(self, fallback : T) -> T
pub fn Memo::get_or_else(self, fallback : (CycleError) -> T) -> T

// Runtime-level ID API (internal/advanced)
fn Runtime::new_memo_id[T : Eq](self, compute : () -> T) -> MemoId[T]
fn Runtime::memo_get[T : Eq](self, id : MemoId[T]) -> T
```

### 7.4 Push Reactive

```moonbit
pub fn Reactive[T : Eq](rt : Runtime, compute : () -> T) -> Reactive[T]
pub fn Reactive::get(self) -> T
pub fn Reactive::dispose(self) -> Unit
```

### 7.5 Push Effect

```moonbit
pub fn Effect(rt : Runtime, execute : () -> Unit) -> Effect
pub fn Effect::dispose(self) -> Unit
```

### 7.6 Relation (Datalog)

```moonbit
pub fn Runtime::new_relation[T : Eq + Hash](self) -> RelationId[T]
pub fn Runtime::relation_insert[T : Eq + Hash](self, id : RelationId[T], tuple : T) -> Bool
pub fn Runtime::relation_contains[T : Eq + Hash](self, id : RelationId[T], tuple : T) -> Bool
pub fn Runtime::relation_iter[T : Eq + Hash](self, id : RelationId[T]) -> Iter[T]
```

### 7.7 Rule (Datalog)

```moonbit
pub fn Runtime::new_rule(
  self,
  inputs : Array[CellId],    // type-erased: callers pass relation.id
  outputs : Array[CellId],   // type-erased: callers pass relation.id
  apply : () -> Unit,
) -> RuleId
```

**Note**: MoonBit does not support wildcard type parameters (`RelationId[_]`). The `new_rule` API accepts raw `CellId` values extracted from typed `RelationId[T]` handles. The Runtime validates that each CellId refers to a `Relation` variant at registration time.

---

## 8. Type Erasure Strategy

MoonBit does not have trait objects or existential types. Values of different types cannot be stored in the same array directly. The solution is **closure-based type erasure**, which the current `incr` already uses.

### Creation-time Capture

```moonbit
fn Runtime::new_signal_id[T : Eq](self, initial : T) -> SignalId[T] {
  // The value lives in a mutable Ref, owned by the Signal[T] handle.
  // PullSignalData stores only type-erased metadata (same pattern as
  // the current implementation where CellMeta is type-erased).

  // Allocate the CellId first so it can be stored in the data struct.
  // idx is computed before push, so CellRef::PullSignal(idx) is already
  // the correct final value when passed to alloc_cell_id.
  let idx = self.pull_signals.length()
  let cell_id = self.alloc_cell_id(CellRef::PullSignal(idx))
  let data = PullSignalData {
    cell_id,
    label: None,
    changed_at: self.revision,
    durability: Durability::Low,
    subscribers: @hashset.new(),
    on_change: None,
  }
  self.pull_signals.push(data)
  SignalId { id: cell_id }
}
pub fn Signal[T : Eq](rt : Runtime, initial : T) -> Signal[T] {
  let id = rt.new_signal_id(initial)
  let value_ref = Ref(initial)
  Signal { id, value_ref, rt }
}
```

The external `SignalId[T]` preserves type information. The typed `Ref[T]` lives in the `Signal[T]` handle held by user code (matching the current implementation). Internally, the Runtime only deals with `CellId` (untyped) and `PullSignalData` (type-erased metadata).

---

## 9. The Pull→Push→Pull Sandwich (Datalog Integration)

This architecture naturally supports the sandwich pattern where different propagation modes connect within the same Runtime.

```
Pull Zone:
  Signal[String] ──get()──▶ Memo[AST] ──get()──▶ Memo[CompiledRules]
      │                                              │
      │            (pull: lazy verification)          │
      ▼                                              ▼
Datalog Zone:                           Memo writes into Relations
  Relation[Tuple] ◀── relation_insert ───────────────┘
      │
      │  fixpoint() loop:
      │    Rule reads Relation deltas
      │    Rule inserts derived tuples into output Relations
      │    Repeat until no new tuples
      ▼
  Relation[Tuple] (materialized results)
      │
Pull Zone:                              Memo reads from Relations
      │
      ▼
  Memo[QueryResult] ──get()──▶ reads Relation.changed_at
                               (pull dependency tracking works
                                because Relation has changed_at)
```

### Cross-boundary dependency tracking

When a PullMemo's compute function calls `relation_iter()` on a Relation, the Runtime:
1. Records the Relation's CellId as a dependency of the Memo (via `track_read`)
2. When `fixpoint()` derives new tuples, it bumps `Runtime.revision` once and updates `Relation.changed_at` for changed relations, so subsequent `memo_get()` calls will see the dependency change and trigger recomputation

No special bridge code is needed. The unified `CellId` space and `track_read` mechanism handle it.

---

## 10. Implementation Plan

### Phase 1: Refactor Cell Storage to SoA

**Prerequisite**: Existing tests must continue to pass.

1. Replace the current single cell array with separate `pull_signals` and `pull_memos` arrays
2. Introduce `CellRef` enum and `cell_index` mapping
3. Introduce `SignalId[T]` and `MemoId[T]` newtype handles
4. Adapt `maybe_changed_after` to work with `CellRef` dispatch
5. All existing tests should pass with no behavior change

### Phase 2: Subscriber Links (adapt existing)

**Prerequisite**: Phase 1 complete.

**Note**: The current implementation already has `subscribers : @hashset.HashSet[CellId]` on `CellMeta` and subscriber maintenance in memo dep diffing. This phase adapts that existing infrastructure to the new SoA layout.

1. Migrate existing subscriber tracking from unified `CellMeta.subscribers` to per-kind `PullSignalData.subscribers` and `PullMemoData.subscribers`
2. Adapt `finish_tracking` to work with `CellRef` dispatch for bidirectional edge maintenance
3. (Optional) Implement GC using subscriber links to detect unreachable cells
4. Existing pull behavior unchanged; subscriber links are populated but not yet used for push

### Phase 3: Push Reactive + Effect

**Prerequisite**: Phase 2 complete.

1. Add `push_reactives` and `push_effects` arrays, `PushReactive` and `PushEffect` variants to `CellRef`
2. Implement `push_propagate_from` (frontier scheduling + level-sorted recomputation)
3. Implement `new_reactive`, `reactive_get`, `new_effect`, `dispose_effect`, `dispose_reactive`
4. Implement automatic level computation (with dynamic dependency support)
5. Implement disposal with the following mechanics:
   - Add a `Disposed` variant to `CellRef` (tombstone sentinel in `cell_index`)
   - Add per-kind free lists to Runtime: `free_push_reactives : Array[Int]`, `free_push_effects : Array[Int]`
   - On `dispose(cell_id)`:
     1. Walk `node.sources`: for each source, remove this `cell_id` from `source.subscribers`
     2. Walk `node.subscribers`: for each subscriber, remove this `cell_id` from `subscriber.sources` (so the subscriber's next level recomputation is correct)
     3. Set `cell_index[cell_id.id] = Disposed` (prevents stale reads; future `CellRef` lookups on this id are safe no-ops)
     4. Push the freed array index onto the appropriate free list
   - On `new_reactive()` / `new_effect()`: pop from the free list before appending to the array (index reuse is safe because step 3 ensures no subscriber links point to the freed slot)
   - **GC note**: subscriber-link cleanup on dispose is O(|sources| + |subscribers|). For bulk GC, iterate `cell_index` looking for cells whose `subscribers` set is empty and whose handle has been dropped; dispose them in reverse topological order
6. Integrate with `batch` / `commit_batch` (including pull→push cross-boundary notification)

**Tests**:
- Basic reactive chain: Signal → Reactive → Reactive → Effect
- Glitch prevention: diamond dependency produces correct intermediate values
- Early cutoff: downstream not recomputed when value unchanged
- Dynamic dependency: Reactive that conditionally reads different Signals
- Effect ordering: Effects execute after all Reactives are updated
- Mixed pull/push: Memo reads a Reactive; Reactive reads a Signal shared with a Memo

### Phase 4: Relation + Rule + Fixpoint

**Prerequisite**: Phase 2 complete (subscriber links). Phase 3 is independent.

1. Add `relations` and `rules` arrays, `Relation` and `Rule` variants to `CellRef`
2. Implement `RelationData` with delta tracking
3. Implement `fixpoint` loop
4. Implement cross-boundary dependency tracking (Relation.changed_at for pull Memos)

**Tests**:
- Transitive closure: `edge(a,b), path(x,y) :- edge(x,y). path(x,z) :- path(x,y), edge(y,z).`
- Fixpoint convergence: verify loop terminates
- Incremental update: add new edge, re-run fixpoint, verify only new paths computed
- Pull→Push→Pull: Memo reads Relation result; Relation changes; Memo recomputes

### Phase 5: Hybrid Mode (Push-Dirty + Pull-Verify)

**Prerequisite**: Phase 2 + Phase 3 complete.

1. Add `HybridMemo` variant that has both `verified_at` and `dirty` flag
2. On input change: push dirty flags through subscriber links
3. On `get()`: if not dirty, return cached (skip verification walk); if dirty, pull-verify
4. This is an optimization of pull, not a new cell kind

**Known design gap**: `commit_batch` currently calls `enqueue_push_subscribers` which only enqueues `PushReactive` and `PushEffect` nodes. A `HybridMemo` subscribed to a `PullSignal` would never receive a dirty flag under this logic, making the optimization ineffective for pull→hybrid boundaries. Before implementing Phase 5, the dirty-propagation path in `commit_batch` must be extended to cover `HybridMemo` nodes — either by adding a `HybridMemo` case to `enqueue_push_subscribers`, or by running a separate dirty-marking pass over pull-signal subscribers. The right approach depends on whether hybrid memos participate in the level-sorted push queue or use a simpler flat dirty set.

---

## 11. Testing Strategy

### Unit Tests per Cell Kind

Each cell kind should have isolated tests verifying its core behavior independent of other kinds.

### Integration Tests for Cross-Kind Boundaries

Specifically test:
1. PullMemo reading from PushReactive
2. PullMemo reading from Relation (after fixpoint)
3. PushReactive reading from PullSignal
4. Effect triggered by Relation change (via PushReactive bridge)

### Property-Based Tests

- **Glitch freedom**: For any computation graph in push mode, no Effect observes an inconsistent intermediate state
- **Convergence**: `fixpoint()` always terminates for monotone Rules
- **Consistency**: Pull and Push modes produce identical results for the same computation graph
- **Early cutoff**: If a cell's value doesn't change, no downstream cell is recomputed

---

## 12. File Structure

Follows the existing flat layout within `cells/` (MoonBit maps directories to packages, so subdirectories would require separate `moon.pkg` configs and cross-package visibility). Files are organized by responsibility using naming conventions.

```
incr/
├── types/
│   ├── cell_id.mbt           # CellId (existing)
│   ├── revision.mbt          # Revision, Durability (existing)
│   └── moon.pkg
│
├── cells/
│   ├── cell_ref.mbt          # CellRef enum (new)
│   ├── runtime.mbt           # Runtime struct, batch, revision management (adapted)
│   ├── tracking.mbt          # ActiveQuery, dependency tracking (adapted)
│   ├── signal.mbt            # PullSignalData, Signal[T] (adapted)
│   ├── memo.mbt              # PullMemoData, Memo[T] (adapted)
│   ├── verify.mbt            # pull_verify / maybe_changed_after (adapted)
│   ├── reactive.mbt          # PushReactiveData, ReactiveId[T] (new)
│   ├── effect.mbt            # PushEffectData, EffectId (new)
│   ├── propagate.mbt         # push_propagate_from, level computation (new)  [needs moonbitlang/core/priority_queue in moon.pkg]
│   ├── relation.mbt          # RelationData, RelationId[T] (new)
│   ├── rule.mbt              # RuleData, RuleId (new)
│   ├── fixpoint.mbt          # fixpoint loop (new)
│   ├── cycle.mbt             # CycleError (existing)
│   ├── memo_map.mbt          # MemoMap (existing)
│   ├── tracked_cell.mbt      # TrackedCell (existing)
│   ├── *_test.mbt            # black-box tests per feature
│   ├── *_wbtest.mbt          # white-box tests for internals
│   └── moon.pkg
│
├── tests/
│   ├── integration_test.mbt  # cross-kind boundary tests (new)
│   └── moon.pkg
│
├── incr.mbt                  # re-exports (adapted)
├── traits.mbt                # Database, Readable, Trackable (adapted)
└── moon.pkg
```

---

## 13. Key Design Decisions and Rationale

| Decision | Rationale |
|---|---|
| SoA (separate arrays per kind) over single enum array | Eliminates unused field memory; enables direct array access for intra-kind hot paths |
| Newtype handles (`SignalId[T]`) over raw `CellId` | Compile-time prevention of misuse (e.g., calling `signal_set` on a MemoId) |
| Closure-based type erasure | MoonBit lacks trait objects; closures capture the typed `Ref[T]` at creation time |
| Single `CellRef` enum for cross-kind dispatch | Minimal overhead (one match); avoids trait object / vtable cost |
| Subscriber links on all cell kinds | Enables GC, push-dirty propagation, and cross-boundary notification uniformly |
| Relation.changed_at for pull integration | Allows PullMemo to depend on Relation results without special bridge code |
| Level-sorted push propagation | Prevents glitches (inconsistent intermediate states) without global topological sort |
| No cycle detection in push mode | Static cycles are impossible by construction (level assignment is a proof); dynamic-dependency cycles are a user error, matching SolidJS. Adding detection would cost a `HashSet` allocation per propagation pass, complicate error propagation from `Signal::set`, and weaken the "impossible by construction" guarantee to "detected at runtime". If a future use case requires it (user-authored formulas, plugin systems), it can be added as a separate `PushReactiveChecked` mode without changing the existing hot path. |
| Cycle detection via `in_progress` flag | Carried over from current implementation; prevents infinite loops in pull verification |
| Per-cell and global `on_change` callbacks | Carried over from current implementation; enables UI re-render hooks |
| `CellId` retains `runtime_id` | Cross-runtime safety; prevents cells from different Runtimes being incorrectly queried |
| `MemoMap` and `TrackedCell` unchanged | These are higher-level wrappers that internally create `Memo`/`Signal` cells; they work with the SoA refactor without modification |
| incr and ECS as independent libraries | Avoids coupling incr's hot-path performance to ECS query overhead; bridge layer connects them when needed |
