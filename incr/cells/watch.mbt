///|
/// A typed keep-alive handle for reading computed values from outside the
/// dependency graph.
///
/// Observer is NOT a cell -- it has no SoA slot, no CellRef variant, and
/// no subscriber set. It is a lightweight ref-counted handle that:
/// 1. Increments gc_root_counts for the target cell (keeps it alive during gc)
/// 2. Provides a typed getter for reading the cell's value
/// 3. Decrements gc_root_counts on dispose (allows gc to collect)
pub struct Observer[T] {
  priv runtime : Runtime
  priv target_id : CellId
  priv getter : () -> T
  priv mut disposed : Bool
} derive(Debug(ignore=[Runtime, Fn, CellId]))

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
/// Returns the current value of the observed cell.
///
/// For Memo and HybridMemo targets, this triggers pull verification
/// if the cell is stale. For Reactive targets, returns the eagerly
/// computed cached value.
pub fn[T] Observer::get(self : Observer[T]) -> T {
  guard !self.disposed else { abort("Observer: already disposed") }
  let value = (self.getter)()
  if self.runtime.has_pending_events() {
    self.runtime.drain_pending_events_if_idle()
  }
  value
}

///|
/// Releases this observer's keep-alive hold on the target cell.
///
/// Decrements gc_root_counts. When the last observer for a cell is
/// disposed (count reaches 0), calls on_unobserve via CellLifecycle
/// (no-op in Layer 4a; Layer 4b adds push suspension).
///
/// Idempotent: disposing an already-disposed observer is a no-op.
pub fn[T] Observer::dispose(self : Observer[T]) -> Unit {
  guard !self.disposed else { return }
  self.disposed = true
  self.runtime.remove_read_root(self.target_id)
}

///|
/// Returns true if this observer has been disposed.
pub fn[T] Observer::is_disposed(self : Observer[T]) -> Bool {
  self.disposed
}

///|
/// A typed keep-alive handle that reads `Result` values from outside the graph.
///
/// `Watch` has the same GC-rooting semantics as `Observer`, but preserves
/// read errors as values for target-facade read APIs.
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
/// Creates an observer for a Memo cell.
pub fn[T] Memo::observe(self : Memo[T]) -> Observer[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Memo::observe called on a disposed memo")
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
fn[T] Memo::watch_result(self : Memo[T]) -> Watch[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Memo::watch called on a disposed memo")
  }
  let rt = self.rt
  rt.add_read_root(self.cell_id)
  {
    runtime: rt,
    target_id: self.cell_id,
    getter: fn() { self.read_honest() },
    disposed: false,
  }
}

///|
/// Creates an observer for a HybridMemo cell.
pub fn[T : Eq] HybridMemo::observe(self : HybridMemo[T]) -> Observer[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("HybridMemo::observe called on a disposed hybrid memo")
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
fn[T : Eq] HybridMemo::watch_result(self : HybridMemo[T]) -> Watch[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("HybridMemo::watch called on a disposed hybrid memo")
  }
  let rt = self.rt
  rt.add_read_root(self.cell_id)
  {
    runtime: rt,
    target_id: self.cell_id,
    getter: fn() { self.read_honest() },
    disposed: false,
  }
}

///|
/// Creates an observer for a Reactive cell.
pub fn[T] Reactive::observe(self : Reactive[T]) -> Observer[T] {
  let cell_id = self.cell_id.id
  guard !self.rt.is_cell_disposed(cell_id) else {
    abort("Reactive::observe called on a disposed reactive")
  }
  let rt = self.rt
  rt.add_read_root(cell_id)
  {
    runtime: rt,
    target_id: cell_id,
    getter: fn() { self.read_permissive() },
    disposed: false,
  }
}

///|
fn[T] Reactive::watch_result(self : Reactive[T]) -> Watch[T] {
  let cell_id = self.cell_id.id
  guard !self.rt.is_cell_disposed(cell_id) else {
    abort("Reactive::watch called on a disposed reactive")
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
