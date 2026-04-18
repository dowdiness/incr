///|
/// A Datalog relation: a set of tuples with delta tracking for fixpoint evaluation.
///
/// `Relation[T]` holds typed `current` and `delta` sets via `Ref`. The Runtime
/// sees only type-erased closures on `RelationData`.
///
/// - `insert()` adds to frontier delta outside fixpoint, and to staged delta during fixpoint
/// - `contains()` checks current (the materialized post-drain set)
/// - `iter()` iterates current; records a dependency for pull verification
/// - `delta_iter()` iterates delta; used by rule bodies
pub(all) struct Relation[T] {
  priv rt : Runtime
  priv cell_id : CellId
  priv current : Ref[@hashset.HashSet[T]]
  priv delta : Ref[@hashset.HashSet[T]]
  priv staged_delta : Ref[@hashset.HashSet[T]]

  fn[T : Hash + Eq] new(rt : Runtime, label? : String) -> Relation[T]
}

///|
pub fn[T : Hash + Eq] Relation::new(
  rt : Runtime,
  label? : String,
) -> Relation[T] {
  let idx = rt.datalog.relations.length()
  let cell_id = rt.alloc_cell_id(Relation(idx))
  let current : Ref[@hashset.HashSet[T]] = { val: @hashset.new() }
  let delta : Ref[@hashset.HashSet[T]] = { val: @hashset.new() }
  let staged_delta : Ref[@hashset.HashSet[T]] = { val: @hashset.new() }
  let data : RelationData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
      push_reachable_count: 0,
    },
    drain_delta: () => {
      for item in delta.val {
        current.val.add(item)
      }
    },
    is_delta_empty: () => delta.val.is_empty(),
    promote_staged_delta: () => {
      let previous_frontier = delta.val
      delta.val = staged_delta.val
      staged_delta.val = previous_frontier
      // Reuse the old frontier allocation as next iteration's staging buffer.
      staged_delta.val.clear()
    },
    is_staged_delta_empty: () => staged_delta.val.is_empty(),
  }
  rt.datalog.relations.push(data)
  let ops : &CellOps = rt.datalog.relations[idx]
  rt.core.cell_ops.push(ops)
  let lifecycle : &CellLifecycle = rt.datalog.relations[idx]
  rt.core.cell_lifecycle.push(lifecycle)
  { rt, cell_id, current, delta, staged_delta }
}

///|
/// Returns the CellId for this relation.
pub fn[T] Relation::id(self : Relation[T]) -> CellId {
  self.cell_id
}

///|
/// Inserts a fact into the delta set.
///
/// Outside `fixpoint()`, inserts go to the current frontier delta.
/// During `fixpoint()`, inserts go to the staged delta for the next iteration.
///
/// Returns `true` if the fact was newly added, `false` if it already exists.
pub fn[T : Hash + Eq] Relation::insert(self : Relation[T], value : T) -> Bool {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Relation::insert called on a disposed relation")
  }
  if self.current.val.contains(value) {
    return false
  }
  if self.delta.val.contains(value) {
    return false
  }
  if self.rt.core.phase is InFixpoint {
    if self.staged_delta.val.contains(value) {
      return false
    }
    self.staged_delta.val.add(value)
  } else {
    self.delta.val.add(value)
  }
  true
}

///|
/// Checks whether a fact exists in the current (materialized) set.
///
/// Facts in delta are NOT visible via `contains` until after `fixpoint()` drains them.
/// Like `iter()`, this records a dependency for pull verification.
pub fn[T : Hash + Eq] Relation::contains(self : Relation[T], value : T) -> Bool {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Relation::contains called on a disposed relation")
  }
  self.record_read_dependency()
  self.current.val.contains(value)
}

///|
/// Iterates over the current (materialized) set.
///
/// Records a dependency so pull memos that call `iter()` automatically
/// re-verify when the relation changes after a `fixpoint()`.
pub fn[T] Relation::iter(self : Relation[T]) -> Iter[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Relation::iter called on a disposed relation")
  }
  self.record_read_dependency()
  self.current.val.iter()
}

///|
/// Records dependency for relation reads and rejects cross-runtime reads while
/// a memo/reaction computation is active.
fn[T] Relation::record_read_dependency(self : Relation[T]) -> Unit {
  let active_rt = current_computing_runtime_id.val
  if active_rt >= 0 && active_rt != self.rt.core.runtime_id {
    current_computing_runtime_id.val = -1
    abort(
      "Cross-runtime dependency: Relation belongs to Runtime " +
      self.rt.core.runtime_id.to_string() +
      " but is read inside a computation on Runtime " +
      active_rt.to_string(),
    )
  }
  self.rt.record_dependency(self.cell_id)
}

///|
/// Disposes this relation, clearing its fact sets and marking it as Disposed.
pub fn[T] Relation::dispose(self : Relation[T]) -> Unit {
  self.rt.dispose_cell(self.cell_id)
  self.current.val.clear()
  self.delta.val.clear()
  self.staged_delta.val.clear()
}

///|
/// Returns true if this relation has been disposed.
pub fn[T] Relation::is_disposed(self : Relation[T]) -> Bool {
  self.rt.is_cell_disposed(self.cell_id)
}

///|
/// Iterates over the delta set (new facts not yet drained to current).
///
/// Used by rule bodies to read only the new facts produced in the previous
/// fixpoint iteration.
pub fn[T] Relation::delta_iter(self : Relation[T]) -> Iter[T] {
  self.delta.val.iter()
}
