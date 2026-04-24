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
/// Returns the current value of the observed cell.
///
/// For Memo and HybridMemo targets, this triggers pull verification
/// if the cell is stale. For Reactive targets, returns the eagerly
/// computed cached value.
pub fn[T] Observer::get(self : Observer[T]) -> T {
  guard !self.disposed else { abort("Observer: already disposed") }
  (self.getter)()
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
  let rt = self.runtime
  let id = self.target_id
  // Skip on_unobserve if target was already manually disposed
  if rt.is_cell_disposed(id) {
    rt.core.gc_root_counts.remove(id)
    return
  }
  let remaining = rt.remove_gc_root(id)
  if remaining == 0 {
    rt.cell_lifecycle[id.id].on_unobserve(rt, id)
  }
}

///|
/// Returns true if this observer has been disposed.
pub fn[T] Observer::is_disposed(self : Observer[T]) -> Bool {
  self.disposed
}

///|
/// Creates an observer for a Memo cell.
pub fn[T] Memo::observe(self : Memo[T]) -> Observer[T] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Memo::observe called on a disposed memo")
  }
  let rt = self.rt
  let prev = rt.add_gc_root(self.cell_id)
  if prev == 0 {
    rt.cell_lifecycle[self.cell_id.id].on_observe(rt, self.cell_id)
  }
  {
    runtime: rt,
    target_id: self.cell_id,
    getter: fn() { self.get_untracked() },
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
  let prev = rt.add_gc_root(self.cell_id)
  if prev == 0 {
    rt.cell_lifecycle[self.cell_id.id].on_observe(rt, self.cell_id)
  }
  {
    runtime: rt,
    target_id: self.cell_id,
    getter: fn() { self.get_untracked() },
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
  let prev = rt.add_gc_root(cell_id)
  if prev == 0 {
    rt.cell_lifecycle[cell_id.id].on_observe(rt, cell_id)
  }
  {
    runtime: rt,
    target_id: cell_id,
    getter: fn() { self.get_untracked() },
    disposed: false,
  }
}

///|
/// One-shot observe: observe a memo, read its value, dispose the observer.
///
/// Convenience for cases where you need a single outside-the-graph read.
///
/// # Panics
///
/// Aborts if the memo has been disposed.
pub fn[T] Runtime::read(self : Runtime, memo : Memo[T]) -> T {
  ignore(self)
  let obs = memo.observe()
  let val = obs.get()
  obs.dispose()
  val
}

///|
/// One-shot observe for HybridMemo.
pub fn[T : Eq] Runtime::read_hybrid(self : Runtime, memo : HybridMemo[T]) -> T {
  ignore(self)
  let obs = memo.observe()
  let val = obs.get()
  obs.dispose()
  val
}

///|
/// One-shot observe for Reactive.
pub fn[T] Runtime::read_reactive(self : Runtime, reactive : Reactive[T]) -> T {
  ignore(self)
  let obs = reactive.observe()
  let val = obs.get()
  obs.dispose()
  val
}
