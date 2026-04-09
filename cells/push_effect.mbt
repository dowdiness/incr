///|
/// Internal SoA entry for a push-mode effect cell.
///
/// Terminal node for side effects (DOM updates, logging, etc.).
/// Never read by other cells. Recomputed eagerly when upstream changes.
priv struct PushEffectData {
  meta : CellMeta
  /// Side effect function to run on recompute.
  mut execute : () -> Unit
  /// Cells this effect reads (updated on recompute).
  mut sources : Array[CellId]
  /// Topological depth (max source level + 1).
  mut level : Int
  /// Set true by push propagation when an upstream cell changes.
  mut dirty : Bool
}

///|
impl HasCellMeta for PushEffectData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for push-effect cells — defaults via HasCellMeta,
/// with sentinel overrides for changed_at, set_changed_at, durability, and level.
impl CellOps for PushEffectData

///|
/// Effects have no changed_at semantics (they are terminal and never read).
/// Returns Revision::initial() as a sentinel.
impl CellOps for PushEffectData with changed_at(self) -> Revision {
  ignore(self)
  Revision::initial()
}

///|
impl CellOps for PushEffectData with set_changed_at(self, _rev : Revision) -> Unit {
  ignore(self)
}

///|
/// Push effects have no Durability. Returns `Low` as a sentinel.
impl CellOps for PushEffectData with durability(self) -> Durability {
  ignore(self)
  Low
}

///|
impl CellOps for PushEffectData with level(self) -> Int {
  self.level
}

///|
impl CellOps for PushEffectData with gc_role(_self) -> GcRole {
  Root
}

///|
impl CellOps for PushEffectData with gc_dependencies(self) -> Array[CellId] {
  self.sources
}

///|
impl CellLifecycle for PushEffectData with dispose_cell(self, rt, cell_id) -> Unit {
  match rt.core.cell_index[cell_id.id] {
    PushEffect(idx) => {
      for dep in self.sources {
        rt.remove_subscriber(dep, cell_id)
      }
      rt.core.cell_index[cell_id.id] = Disposed
      self.clear_slot()
      rt.push.free_effects.push(idx)
      rt.push.node_count = rt.push.node_count - 1
    }
    _ => ()
  }
}

///|
/// Clears all mutable fields to release captured closures and graph edges.
/// Called by the CellLifecycle dispose impl after removing subscriber links.
fn PushEffectData::clear_slot(self : PushEffectData) -> Unit {
  self.execute = () => ()
  self.sources.clear()
  self.meta.subscribers.clear()
  self.meta.label = None
  self.level = 0
  self.dirty = false
}

///|
/// User-facing push-mode effect.
///
/// Runs the provided function immediately on creation to establish
/// dependencies, then re-runs whenever any dependency changes.
pub struct Effect {
  priv cell_id : CellId
  priv rt : Runtime
}

///|
/// Creates a new push-mode effect.
///
/// `f` is invoked immediately to establish dependencies and run the initial
/// side effect. It is re-run by push propagation whenever any dependency changes.
pub fn Effect::new(rt : Runtime, f : () -> Unit) -> Effect {
  // Reuse a freed slot if available, otherwise append a new one.
  let effect_idx = match rt.push.free_effects.pop() {
    Some(idx) => idx
    None => rt.push.effects.length()
  }
  let cell_id = rt.alloc_cell_id(PushEffect(effect_idx))
  rt.push.node_count = rt.push.node_count + 1
  let new_data : PushEffectData = {
    meta: {
      cell_id,
      label: None,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
      push_reachable_count: 0,
    },
    execute: f,
    sources: [],
    level: 1,
    dirty: false,
  }
  if effect_idx < rt.push.effects.length() {
    rt.push.effects[effect_idx] = new_data
  } else {
    rt.push.effects.push(new_data)
  }
  let ops : &CellOps = rt.push.effects[effect_idx]
  rt.core.cell_ops.push(ops)
  let lifecycle : &CellLifecycle = rt.push.effects[effect_idx]
  rt.core.cell_lifecycle.push(lifecycle)
  let effect : Effect = { cell_id, rt }
  // Run immediately to establish dependencies and execute the initial side effect.
  rt.begin_tracking(cell_id)
  f()
  let new_sources = rt.end_tracking()
  rt.push.effects[effect_idx].sources = new_sources
  rt.push.effects[effect_idx].level = rt.recompute_level(cell_id, new_sources)
  rt.finish_tracking(cell_id, [], new_sources)
  effect
}

///|
/// Returns true if this effect has been disposed.
pub fn Effect::is_disposed(self : Effect) -> Bool {
  self.rt.is_cell_disposed(self.cell_id)
}

///|
/// Returns the unique identifier for this effect cell.
pub fn Effect::id(self : Effect) -> CellId {
  self.cell_id
}

///|
/// Removes this effect from the dependency graph.
pub fn Effect::dispose(self : Effect) -> Unit {
  self.rt.dispose_cell(self.cell_id)
}
