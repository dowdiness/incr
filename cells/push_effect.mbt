///|
/// Internal SoA entry for a push-mode effect cell.
///
/// Terminal node for side effects (DOM updates, logging, etc.).
/// Never read by other cells. Recomputed eagerly when upstream changes.
priv struct PushEffectData {
  cell_id : CellId
  mut label : String?
  /// Side effect function to run on recompute.
  mut execute : () -> Unit
  /// Cells this effect reads (updated on recompute).
  mut sources : Array[CellId]
  /// Topological depth (max source level + 1).
  mut level : Int
  /// Set true by push propagation when an upstream cell changes.
  mut dirty : Bool
  /// Always-empty subscriber set (effects are terminal nodes; kept for CellOps uniformity).
  subscribers : @hashset.HashSet[CellId]
}

///|
impl CellOps for PushEffectData with cell_id(self) -> CellId {
  self.cell_id
}

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
/// Effects are terminal nodes — their subscriber set is always empty.
impl CellOps for PushEffectData with subscribers(self) -> @hashset.HashSet[
  CellId,
] {
  self.subscribers
}

///|
impl CellOps for PushEffectData with label(self) -> String? {
  self.label
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
/// Clears all mutable fields to release captured closures and graph edges.
/// Called by `Runtime::dispose_effect` after removing subscriber links.
fn PushEffectData::clear_slot(self : PushEffectData) -> Unit {
  self.execute = () => ()
  self.sources.clear()
  self.subscribers.clear()
  self.label = None
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
    cell_id,
    label: None,
    execute: f,
    sources: [],
    level: 1,
    dirty: false,
    subscribers: @hashset.new(),
  }
  if effect_idx < rt.push.effects.length() {
    rt.push.effects[effect_idx] = new_data
  } else {
    rt.push.effects.push(new_data)
  }
  let ops : &CellOps = rt.push.effects[effect_idx]
  rt.core.cell_ops.push(ops)
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
/// Removes this effect from the dependency graph.
pub fn Effect::dispose(self : Effect) -> Unit {
  self.rt.dispose_effect(self.cell_id)
}
