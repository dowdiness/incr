///|
/// Central state for the incremental computation framework.
pub(all) struct Runtime {
  mut current_revision : Revision
  cells : @hashmap.HashMap[CellId, CellMeta]
  mut next_cell_id : Int
  tracking_stack : Array[ActiveQuery]
  /// Per-durability: the last revision at which an input of that durability changed.
  durability_last_changed : FixedArray[Revision]
}

///|
pub fn Runtime::new() -> Runtime {
  {
    current_revision: Revision::initial(),
    cells: @hashmap.new(),
    next_cell_id: 0,
    tracking_stack: [],
    durability_last_changed: FixedArray::make(durability_count, Revision::initial()),
  }
}

///|
/// Allocate a new CellId and register its metadata.
pub fn Runtime::register_cell(self : Runtime, meta : CellMeta) -> Unit {
  self.cells.set(meta.id, meta)
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
  match self.cells.get(id) {
    Some(meta) => meta
    None => abort("Cell not found: " + id.to_string())
  }
}

///|
/// Bump the global revision and record the durability level that changed.
pub fn Runtime::bump_revision(self : Runtime, durability : Durability) -> Unit {
  self.current_revision = self.current_revision.next()
  // Update this durability level and all lower durability levels
  let dur_idx = durability.index()
  for i = 0; i <= dur_idx; i = i + 1 {
    self.durability_last_changed[i] = self.current_revision
  }
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
