///|
/// Central state for the incremental computation framework.
pub(all) struct Runtime {
  mut current_revision : Revision
  cells : Array[CellMeta?]
  mut next_cell_id : Int
  tracking_stack : Array[ActiveQuery]
  /// Per-durability: the last revision at which an input of that durability changed.
  durability_last_changed : FixedArray[Revision]
  /// Batch state: nesting depth for batch operations.
  mut batch_depth : Int
  /// Signals with pending changes during a batch.
  batch_pending_signals : Array[CellId]
  /// Maximum durability level seen during a batch.
  mut batch_max_durability : Durability
}

///|
pub fn Runtime::new() -> Runtime {
  {
    current_revision: Revision::initial(),
    cells: [],
    next_cell_id: 0,
    tracking_stack: [],
    durability_last_changed: FixedArray::make(durability_count, Revision::initial()),
    batch_depth: 0,
    batch_pending_signals: [],
    batch_max_durability: Low,
  }
}

///|
/// Allocate a new CellId and register its metadata.
pub fn Runtime::register_cell(self : Runtime, meta : CellMeta) -> Unit {
  let id = meta.id.id
  // Grow array if needed
  while self.cells.length() <= id {
    self.cells.push(None)
  }
  self.cells[id] = Some(meta)
}

///|
/// Allocate a fresh CellId.
pub fn Runtime::alloc_cell_id(self : Runtime) -> CellId {
  let id = self.next_cell_id
  self.next_cell_id = id + 1
  { id, }
}

///|
/// Get cell metadata by id. Aborts if not found.
pub fn Runtime::get_cell(self : Runtime, id : CellId) -> CellMeta {
  if id.id < self.cells.length() {
    match self.cells[id.id] {
      Some(meta) => meta
      None => abort("Cell not found: " + id.to_string())
    }
  } else {
    abort("Cell not found: " + id.to_string())
  }
}

///|
/// Bump the global revision and record the durability level that changed.
/// During a batch, defers the actual bump until the batch ends.
pub fn Runtime::bump_revision(self : Runtime, durability : Durability) -> Unit {
  if self.batch_depth > 0 {
    // Track the maximum durability seen during this batch
    if durability.index() > self.batch_max_durability.index() {
      self.batch_max_durability = durability
    }
    return
  }
  self.current_revision = self.current_revision.next()
  // Update this durability level and all lower durability levels
  let dur_idx = durability.index()
  for i = 0; i <= dur_idx; i = i + 1 {
    self.durability_last_changed[i] = self.current_revision
  }
}

///|
/// Execute a closure within a batch. Multiple Signal::set calls inside the
/// closure share a single revision bump. Batches can be nested; only the
/// outermost batch commits.
pub fn Runtime::batch(self : Runtime, f : () -> Unit) -> Unit {
  self.batch_depth = self.batch_depth + 1
  f()
  self.batch_depth = self.batch_depth - 1
  if self.batch_depth == 0 {
    self.commit_batch()
  }
}

///|
/// Commit pending batch changes using two-phase values.
/// Phase 1: commit each signal's pending value, collecting which actually changed.
/// Phase 2: if any changed, single revision bump and metadata update.
fn Runtime::commit_batch(self : Runtime) -> Unit {
  if self.batch_pending_signals.length() == 0 {
    // Nothing changed during the batch, reset state
    self.batch_max_durability = Low
    return
  }
  // Phase 1: commit pending values and collect which actually changed
  let changed_ids : Array[CellId] = []
  for i = 0; i < self.batch_pending_signals.length(); i = i + 1 {
    let meta = self.get_cell(self.batch_pending_signals[i])
    match meta.commit_pending {
      Some(commit_fn) => {
        if commit_fn() {
          changed_ids.push(self.batch_pending_signals[i])
        }
        meta.commit_pending = None
      }
      None => ()
    }
  }
  // Reset pending list by clearing directly
  self.batch_pending_signals.clear()
  // Phase 2: if any value actually changed, do a single revision bump
  if changed_ids.length() > 0 {
    let durability = self.batch_max_durability
    self.current_revision = self.current_revision.next()
    let dur_idx = durability.index()
    for i = 0; i <= dur_idx; i = i + 1 {
      self.durability_last_changed[i] = self.current_revision
    }
    // Sweep changed signals
    let rev = self.current_revision
    for i = 0; i < changed_ids.length(); i = i + 1 {
      let meta = self.get_cell(changed_ids[i])
      meta.changed_at = rev
      meta.verified_at = rev
    }
  }
  self.batch_max_durability = Low
}

///|
/// Record a signal as pending during a batch.
pub fn Runtime::record_batch_signal(self : Runtime, cell_id : CellId) -> Unit {
  self.batch_pending_signals.push(cell_id)
}

///|
/// Record a dependency from the current active computation to the given cell.
pub fn Runtime::record_dependency(self : Runtime, dep : CellId) -> Unit {
  let len = self.tracking_stack.length()
  if len > 0 {
    self.tracking_stack[len - 1].record(dep)
  }
}

///|
/// Push a new tracking frame for a memo computation.
pub fn Runtime::push_tracking(self : Runtime, cell_id : CellId) -> Unit {
  self.tracking_stack.push(ActiveQuery::new(cell_id))
}

///|
/// Pop the tracking frame and return the collected dependencies.
pub fn Runtime::pop_tracking(self : Runtime) -> Array[CellId] {
  match self.tracking_stack.pop() {
    Some(query) => query.dependencies
    None => abort("Tracking stack underflow")
  }
}
