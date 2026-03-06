///|
pub struct RelationId[T] {
  id : CellId
}

///|
struct RelationData {
  cell_id : CellId
  drain_delta : () -> Unit
  is_delta_empty : () -> Bool
  subscribers : @hashset.HashSet[CellId]
  mut changed_at : Revision
  label : String?
  durability : Durability
}

///|
impl CellOps for RelationData with cell_id(self) { self.cell_id }

///|
impl CellOps for RelationData with changed_at(self) { self.changed_at }

///|
impl CellOps for RelationData with set_changed_at(self, rev) {
  self.changed_at = rev
}

///|
impl CellOps for RelationData with subscribers(self) { self.subscribers }

///|
impl CellOps for RelationData with label(self) { self.label }

///|
impl CellOps for RelationData with durability(self) { self.durability }

///|
/// A Datalog relation: a set of tuples with delta tracking for fixpoint evaluation.
///
/// `Relation[T]` holds typed `current` and `delta` sets via `Ref`. The Runtime
/// sees only type-erased closures (`drain_delta`, `is_delta_empty`) on `RelationData`.
///
/// - `insert()` adds to delta (not current) — facts move to current on drain
/// - `contains()` checks current (the materialized post-drain set)
/// - `iter()` iterates current; records a dependency for pull verification
/// - `delta_iter()` iterates delta; used by rule bodies
pub(all) struct Relation[T] {
  priv rt : Runtime
  priv cell_id : CellId
  priv current : Ref[@hashset.HashSet[T]]
  priv delta : Ref[@hashset.HashSet[T]]

  fn[T : Hash + Eq] new(rt : Runtime, label? : String) -> Relation[T]
}

///|
pub fn[T : Hash + Eq] Relation::new(
  rt : Runtime,
  label? : String,
) -> Relation[T] {
  let idx = rt.relations.length()
  let cell_id = rt.alloc_cell_id(Relation(idx))
  let current : Ref[@hashset.HashSet[T]] = { val: @hashset.new() }
  let delta : Ref[@hashset.HashSet[T]] = { val: @hashset.new() }
  let data : RelationData = {
    cell_id,
    drain_delta: fn() {
      for item in delta.val {
        current.val.add(item)
      }
      delta.val.clear()
    },
    is_delta_empty: fn() { delta.val.is_empty() },
    subscribers: @hashset.new(),
    changed_at: Revision::initial(),
    label,
    durability: Low,
  }
  rt.relations.push(data)
  let ops : &CellOps = rt.relations[idx]
  rt.cell_ops.push(ops)
  { rt, cell_id, current, delta }
}

///|
/// Returns the CellId for this relation.
pub fn[T] Relation::id(self : Relation[T]) -> CellId {
  self.cell_id
}

///|
/// Inserts a fact into the delta set.
///
/// Returns `true` if the fact was newly added to the delta, `false` if it
/// already exists in either delta or current.
pub fn[T : Hash + Eq] Relation::insert(self : Relation[T], value : T) -> Bool {
  if self.current.val.contains(value) {
    return false
  }
  if self.delta.val.contains(value) {
    return false
  }
  self.delta.val.add(value)
  true
}

///|
/// Checks whether a fact exists in the current (materialized) set.
///
/// Facts in delta are NOT visible via `contains` until after `fixpoint()` drains them.
pub fn[T : Hash + Eq] Relation::contains(
  self : Relation[T],
  value : T,
) -> Bool {
  self.current.val.contains(value)
}

///|
/// Iterates over the current (materialized) set.
///
/// Records a dependency so pull memos that call `iter()` automatically
/// re-verify when the relation changes after a `fixpoint()`.
pub fn[T] Relation::iter(self : Relation[T]) -> Iter[T] {
  self.rt.record_dependency(self.cell_id)
  self.current.val.iter()
}

///|
/// Iterates over the delta set (new facts not yet drained to current).
///
/// Used by rule bodies to read only the new facts produced in the previous
/// fixpoint iteration.
pub fn[T] Relation::delta_iter(self : Relation[T]) -> Iter[T] {
  self.delta.val.iter()
}
