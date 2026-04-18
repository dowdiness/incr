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
  let (new_sources, new_seen) = rt.end_tracking()
  rt.push.effects[effect_idx].sources = new_sources
  rt.push.effects[effect_idx].level = rt.recompute_level(cell_id, new_sources)
  rt.finish_tracking(cell_id, [], new_sources, new_seen)
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
