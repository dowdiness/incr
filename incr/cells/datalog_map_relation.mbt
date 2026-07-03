///|
/// A Datalog functional relation: a key-value map with delta tracking for
/// fixpoint evaluation.
///
/// Unlike `Relation[T]` (a HashSet), `MapRelation[K, V]` uses
/// `@hashmap.HashMap[K, V]` and supports replacing values for existing keys.
///
/// Three layers:
/// - `current`      — materialized post-drain (readable via `get()`/`iter()`)
/// - `delta`        — frontier for current fixpoint iteration
/// - `staged_delta` — staging buffer during fixpoint
///
/// - `insert()` adds to frontier delta outside fixpoint, staged delta during fixpoint
/// - `get()` reads current (the materialized post-drain map)
/// - `iter()` iterates current; records a dependency for pull verification
/// - `delta_iter()` iterates delta; used by rule bodies
pub(all) struct MapRelation[K, V] {
  priv rt : Runtime
  priv cell_id : CellId
  priv current : Ref[@hashmap.HashMap[K, V]]
  priv delta : Ref[@hashmap.HashMap[K, V]]
  priv staged_delta : Ref[@hashmap.HashMap[K, V]]
  priv merge : ((V, V) -> V)?
  priv original_values : Ref[@hashmap.HashMap[K, V?]]
  priv changed_keys : Ref[@hashset.HashSet[K]]
}

///|
/// Creates a relation-shaped map input.
pub fn[K : Hash + Eq, V] MapRelation::MapRelation(
  rt : Runtime,
  merge? : (V, V) -> V,
  label? : String,
) -> MapRelation[K, V] {
  let idx = rt.datalog.functional_relations.length()
  let cell_id = rt.alloc_cell_id(FunctionalRelation(idx))
  let current : Ref[@hashmap.HashMap[K, V]] = { val: @hashmap.HashMap([]) }
  let delta : Ref[@hashmap.HashMap[K, V]] = { val: @hashmap.HashMap([]) }
  let staged_delta : Ref[@hashmap.HashMap[K, V]] = { val: @hashmap.HashMap([]) }
  let original_values : Ref[@hashmap.HashMap[K, V?]] = {
    val: @hashmap.HashMap([]),
  }
  let changed_keys : Ref[@hashset.HashSet[K]] = { val: @hashset.HashSet([]) }
  let data : FunctionalRelationData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.HashSet([]),
      push_reachable_count: 0,
    },
    drain_delta: () => delta.val.each(fn(k, v) { current.val.set(k, v) }),
    is_delta_empty: () => delta.val.is_empty(),
    promote_staged_delta: () => {
      let previous_frontier = delta.val
      delta.val = staged_delta.val
      staged_delta.val = previous_frontier
      staged_delta.val.clear()
    },
    is_staged_delta_empty: () => staged_delta.val.is_empty(),
    begin_fixpoint: () => (),
    finish_fixpoint_changed: () => {
      let changed = !changed_keys.val.is_empty()
      original_values.val.clear()
      changed_keys.val.clear()
      changed
    },
  }
  rt.datalog.functional_relations.push(data)
  let ops : &CellOps = rt.datalog.functional_relations[idx]
  rt.core.cell_ops.push(ops)
  let lifecycle : &CellLifecycle = rt.datalog.functional_relations[idx]
  rt.cell_lifecycle.push(lifecycle)
  {
    rt,
    cell_id,
    current,
    delta,
    staged_delta,
    merge,
    original_values,
    changed_keys,
  }
}

///|
/// Returns the CellId for this map relation.
pub fn[K, V] MapRelation::id(self : MapRelation[K, V]) -> CellId {
  self.cell_id
}

///|
/// Resolves the effective value for a key across layers.
///
/// During fixpoint: staged_delta > delta > current
/// Outside fixpoint: delta > current
fn[K : Hash + Eq, V] MapRelation::effective_value(
  self : MapRelation[K, V],
  key : K,
) -> V? {
  if self.rt.core.phase is InFixpoint {
    match self.staged_delta.val.get(key) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  match self.delta.val.get(key) {
    Some(v) => Some(v)
    None => self.current.val.get(key)
  }
}

///|
fn[K : Hash + Eq, V : Eq] MapRelation::record_net_change(
  self : MapRelation[K, V],
  key : K,
  resolved : V,
) -> Unit {
  let original = match self.original_values.val.get(key) {
    Some(v) => v
    None => {
      let v = self.current.val.get(key)
      self.original_values.val.set(key, v)
      v
    }
  }
  match original {
    Some(v) =>
      if resolved == v {
        self.changed_keys.val.remove(key)
      } else {
        self.changed_keys.val.add(key)
      }
    None => self.changed_keys.val.add(key)
  }
}

///|
/// Inserts a key-value pair into the delta set.
///
/// Outside `fixpoint()`, inserts go to the current frontier delta.
/// During `fixpoint()`, inserts go to the staged delta for the next iteration.
///
/// If a merge function is provided, it is applied when the key already has an
/// effective value: `merge(old, new)`. If the merged result equals the old
/// effective value, the insert is a no-op.
///
/// Returns `true` if the effective value changed, `false` if it was a no-op.
pub fn[K : Hash + Eq, V : Eq] MapRelation::insert(
  self : MapRelation[K, V],
  key : K,
  value : V,
) -> Bool {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("MapRelation::insert called on a disposed map relation")
  }
  let effective = self.effective_value(key)
  let resolved = match self.merge {
    Some(merge_fn) =>
      match effective {
        Some(old) => {
          let merged = merge_fn(old, value)
          if merged == old {
            return false
          }
          merged
        }
        None => value
      }
    None =>
      match effective {
        Some(old) => if old == value { return false } else { value }
        None => value
      }
  }
  self.record_net_change(key, resolved)
  if self.rt.core.phase is InFixpoint {
    self.staged_delta.val.set(key, resolved)
  } else {
    self.delta.val.set(key, resolved)
  }
  true
}

///|
/// Looks up a key in the current (materialized) map.
///
/// Values in delta are NOT visible via `get` until after `fixpoint()` drains them.
/// Like `iter()`, this records a dependency for pull verification.
pub fn[K : Hash + Eq, V] MapRelation::get(
  self : MapRelation[K, V],
  key : K,
) -> V? {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("MapRelation::get called on a disposed map relation")
  }
  self.record_read_dependency()
  self.current.val.get(key)
}

///|
/// Iterates over the current (materialized) map as (key, value) pairs.
///
/// Records a dependency so pull memos that call `iter()` automatically
/// re-verify when the map relation changes after a `fixpoint()`.
pub fn[K, V] MapRelation::iter(self : MapRelation[K, V]) -> Iter[(K, V)] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("MapRelation::iter called on a disposed map relation")
  }
  self.record_read_dependency()
  self.current.val.iter()
}

///|
/// Records dependency for map relation reads and rejects cross-runtime
/// reads while a memo/reaction computation is active.
fn[K, V] MapRelation::record_read_dependency(self : MapRelation[K, V]) -> Unit {
  self.rt.check_cross_runtime(self.rt.core.runtime_id, "MapRelation")
  self.rt.record_dependency(self.cell_id)
}

///|
/// Disposes this map relation, clearing its maps and marking it as
/// Disposed.
pub fn[K, V] MapRelation::dispose(self : MapRelation[K, V]) -> Unit {
  self.rt.dispose_cell(self.cell_id)
  self.current.val.clear()
  self.delta.val.clear()
  self.staged_delta.val.clear()
  self.original_values.val.clear()
  self.changed_keys.val.clear()
}

///|
/// Returns true if this map relation has been disposed.
pub fn[K, V] MapRelation::is_disposed(self : MapRelation[K, V]) -> Bool {
  self.rt.is_cell_disposed(self.cell_id)
}

///|
/// Iterates over the delta set (new/updated entries not yet drained to current).
///
/// Used by rule bodies to read only the new entries produced in the previous
/// fixpoint iteration.
pub fn[K, V] MapRelation::delta_iter(self : MapRelation[K, V]) -> Iter[(K, V)] {
  self.delta.val.iter()
}
