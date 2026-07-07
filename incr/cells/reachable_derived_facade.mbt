///|
pub(all) struct ReachableDerived[T] {
  priv label : String?
  priv rt : Runtime
  priv cell_id : CellId
  priv compute : () -> T raise Failure
  priv mut value : T?
} derive(Debug(ignore=[Runtime, Fn, CellId]))

///|
/// Creates a reachable lazy derived value.
pub fn[T : Eq] ReachableDerived::ReachableDerived(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
) -> ReachableDerived[T] {
  ReachableDerived::_create(rt, compute, label?)
}

///|
/// Strict graph read. Requires an active tracked context.
pub fn[T : Eq] ReachableDerived::get(
  self : ReachableDerived[T],
) -> Result[T, ReadError] {
  self.get_strict_honest()
}

///|
/// Strict graph read that aborts on invalid context or any read error.
pub fn[T : Eq] ReachableDerived::get_or_abort(self : ReachableDerived[T]) -> T {
  match self.get() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Permissive read. Works outside the graph and records a dependency if tracked.
pub fn[T : Eq] ReachableDerived::read(
  self : ReachableDerived[T],
) -> Result[T, ReadError] {
  self.read_honest()
}

///|
/// Permissive read that aborts on any read error.
pub fn[T : Eq] ReachableDerived::read_or_abort(self : ReachableDerived[T]) -> T {
  match self.read() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Creates a long-lived outside-graph reader that returns read errors.
pub fn[T : Eq] ReachableDerived::watch(self : ReachableDerived[T]) -> Watch[T] {
  self.watch_result()
}

///|
/// Returns whether this reachable derived value is verified at the current revision.
pub fn[T] ReachableDerived::is_fresh(self : ReachableDerived[T]) -> Bool {
  self.is_up_to_date()
}

///|
/// Returns the unique cell identifier for this reachable derived value.
/// Stable across reads — useful for graph-shape probes (gc anchoring, edge
/// inspection) where a cell needs an identity independent of its value.
pub fn[T] ReachableDerived::id(self : ReachableDerived[T]) -> CellId {
  self.cell_id
}

///|
/// Acquires an `Observer` that roots this reachable derived cell against
/// gc. The caller must `dispose()` the returned observer when done.
pub fn[T : Eq] ReachableDerived::observe(
  self : ReachableDerived[T],
) -> Observer[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort(
      "ReachableDerived::observe called on a disposed reachable derived cell",
    )
  }
  let rt = self.rt
  rt.add_read_root(self.cell_id)
  {
    runtime: rt,
    target_id: self.cell_id,
    getter: fn() { self.read_permissive() },
    disposed: false,
  }
}

///|

///|
/// Disposes this reachable derived value, freeing associated resources. After
/// disposal, reads abort with `Disposed`.
pub fn[T] ReachableDerived::dispose(self : ReachableDerived[T]) -> Unit {
  self.rt.dispose_cell(self.cell_id)
  self.value = None
}

///|
/// Returns true if this reachable derived cell has been disposed.
pub fn[T] ReachableDerived::is_disposed(self : ReachableDerived[T]) -> Bool {
  self.rt.is_cell_disposed(self.cell_id)
}

///|
/// Creates a long-lived outside-graph reader for this eager derived value.
pub fn[T] EagerDerived::watch(self : EagerDerived[T]) -> Watch[T] {
  self.watch_result()
}
