///|
fn Runtime::add_read_root(self : Runtime, id : CellId) -> Unit {
  let prev = self.add_gc_root(id)
  if prev == 0 {
    self.cell_lifecycle[id.id].on_observe(self, id)
  }
}

///|
fn Runtime::remove_read_root(self : Runtime, id : CellId) -> Unit {
  if self.is_cell_disposed(id) {
    self.core.gc_root_counts.remove(id)
    return
  }
  let remaining = self.remove_gc_root(id)
  if remaining == 0 {
    self.cell_lifecycle[id.id].on_unobserve(self, id)
  }
}

///|
/// A typed persistent read root for values read outside the graph.
///
/// A `Watch` keeps its target reachable across `Runtime::gc()` and preserves
/// read errors as values.
pub struct Watch[T] {
  priv runtime : Runtime
  priv target_id : CellId
  priv getter : () -> Result[T, ReadError]
  priv mut disposed : Bool
} derive(Debug(ignore=[Runtime, Fn, CellId]))

///|
/// Returns the current value or a mechanism error (cycle / disposed) from the
/// watched cell.
pub fn[T] Watch::read(self : Watch[T]) -> Result[T, ReadError] {
  guard !self.disposed else { abort("Watch: already disposed") }
  let value = (self.getter)()
  if self.runtime.has_pending_events() {
    self.runtime.drain_pending_events_if_idle()
  }
  value
}

///|
/// Returns the current value, aborting if a read error is detected.
pub fn[T] Watch::read_or_abort(self : Watch[T]) -> T {
  match self.read() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Releases this watch's keep-alive hold on the target cell.
///
/// Idempotent: disposing an already-disposed watch is a no-op.
pub fn[T] Watch::dispose(self : Watch[T]) -> Unit {
  guard !self.disposed else { return }
  self.disposed = true
  self.runtime.remove_read_root(self.target_id)
}

///|
/// Returns true if this watch has been disposed.
pub fn[T] Watch::is_disposed(self : Watch[T]) -> Bool {
  self.disposed
}

///|
fn[T] EagerDerived::watch_result(self : EagerDerived[T]) -> Watch[T] {
  let cell_id = self.cell_id.id
  guard !self.rt.is_cell_disposed(cell_id) else {
    abort("EagerDerived::watch called on a disposed eager derived cell")
  }
  let rt = self.rt
  rt.add_read_root(cell_id)
  {
    runtime: rt,
    target_id: cell_id,
    // EagerDerived has no cycle/raise channel (its compute is `() -> T`), but
    // the `Watch` contract is uniformly honest about disposal: a read after the
    // target is disposed returns `Err(Disposed(_))` rather than aborting.
    getter: fn() {
      if self.rt.is_cell_disposed(cell_id) {
        Err(ReadError::disposed(cell_id))
      } else {
        Ok(self.read_permissive())
      }
    },
    disposed: false,
  }
}
