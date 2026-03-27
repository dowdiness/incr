///|
struct FunctionalRelationData {
  meta : CellMeta
  drain_delta : () -> Unit
  is_delta_empty : () -> Bool
  promote_staged_delta : () -> Unit
  is_staged_delta_empty : () -> Bool
}

///|
impl HasCellMeta for FunctionalRelationData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for functional relation cells — all defaults via HasCellMeta.
impl CellOps for FunctionalRelationData

///|
/// A Datalog functional relation: a key-value map with delta tracking for
/// fixpoint evaluation.
///
/// Unlike `Relation[T]` (a HashSet), `FunctionalRelation[K, V]` uses
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
pub(all) struct FunctionalRelation[K, V] {
  priv rt : Runtime
  priv cell_id : CellId
  priv current : Ref[@hashmap.HashMap[K, V]]
  priv delta : Ref[@hashmap.HashMap[K, V]]
  priv staged_delta : Ref[@hashmap.HashMap[K, V]]
  priv merge : ((V, V) -> V)?

  fn[K : Hash + Eq, V] new(
    rt : Runtime,
    merge? : (V, V) -> V,
    label? : String,
  ) -> FunctionalRelation[K, V]
}

///|
pub fn[K : Hash + Eq, V] FunctionalRelation::new(
  rt : Runtime,
  merge? : (V, V) -> V,
  label? : String,
) -> FunctionalRelation[K, V] {
  let idx = rt.datalog.functional_relations.length()
  let cell_id = rt.alloc_cell_id(FunctionalRelation(idx))
  let current : Ref[@hashmap.HashMap[K, V]] = { val: @hashmap.new() }
  let delta : Ref[@hashmap.HashMap[K, V]] = { val: @hashmap.new() }
  let staged_delta : Ref[@hashmap.HashMap[K, V]] = { val: @hashmap.new() }
  let data : FunctionalRelationData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
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
  }
  rt.datalog.functional_relations.push(data)
  let ops : &CellOps = rt.datalog.functional_relations[idx]
  rt.core.cell_ops.push(ops)
  { rt, cell_id, current, delta, staged_delta, merge }
}

///|
/// Returns the CellId for this functional relation.
pub fn[K, V] FunctionalRelation::id(self : FunctionalRelation[K, V]) -> CellId {
  self.cell_id
}

///|
/// Resolves the effective value for a key across layers.
///
/// During fixpoint: staged_delta > delta > current
/// Outside fixpoint: delta > current
fn[K : Hash + Eq, V] FunctionalRelation::effective_value(
  self : FunctionalRelation[K, V],
  key : K,
) -> V? {
  if self.rt.core.in_fixpoint {
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
pub fn[K : Hash + Eq, V : Eq] FunctionalRelation::insert(
  self : FunctionalRelation[K, V],
  key : K,
  value : V,
) -> Bool {
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
  if self.rt.core.in_fixpoint {
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
pub fn[K : Hash + Eq, V] FunctionalRelation::get(
  self : FunctionalRelation[K, V],
  key : K,
) -> V? {
  self.record_read_dependency()
  self.current.val.get(key)
}

///|
/// Iterates over the current (materialized) map as (key, value) pairs.
///
/// Records a dependency so pull memos that call `iter()` automatically
/// re-verify when the functional relation changes after a `fixpoint()`.
pub fn[K, V] FunctionalRelation::iter(
  self : FunctionalRelation[K, V],
) -> Iter[(K, V)] {
  self.record_read_dependency()
  self.current.val.iter()
}

///|
/// Records dependency for functional relation reads and rejects cross-runtime
/// reads while a memo/reaction computation is active.
fn[K, V] FunctionalRelation::record_read_dependency(
  self : FunctionalRelation[K, V],
) -> Unit {
  let active_rt = current_computing_runtime_id.val
  if active_rt >= 0 && active_rt != self.rt.core.runtime_id {
    current_computing_runtime_id.val = -1
    abort(
      "Cross-runtime dependency: FunctionalRelation belongs to Runtime " +
      self.rt.core.runtime_id.to_string() +
      " but is read inside a computation on Runtime " +
      active_rt.to_string(),
    )
  }
  self.rt.record_dependency(self.cell_id)
}

///|
/// Iterates over the delta set (new/updated entries not yet drained to current).
///
/// Used by rule bodies to read only the new entries produced in the previous
/// fixpoint iteration.
pub fn[K, V] FunctionalRelation::delta_iter(
  self : FunctionalRelation[K, V],
) -> Iter[(K, V)] {
  self.delta.val.iter()
}
