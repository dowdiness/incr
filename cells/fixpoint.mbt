///|
/// Runs fixpoint evaluation over all registered rules until no new facts are derived.
///
/// Algorithm (semi-naive evaluation):
/// 1. Materialize each relation's current frontier `delta` into `current`
/// 2. Apply all rules — rule bodies read `delta` (frontier) and `current`, and
///    insert newly derived facts into staged deltas
/// 3. Record which relations produced staged deltas this iteration
/// 4. Promote staged deltas to next iteration's frontier (clears old frontier)
/// 5. If no staged deltas were produced, stop; otherwise repeat
/// 6. If any relation changed, advance revision and update changed_at
pub fn Runtime::fixpoint(self : Runtime) -> Unit {
  if self.in_fixpoint {
    abort("fixpoint: re-entrant fixpoint() is not supported")
  }
  if self.batch_depth > 0 {
    abort("fixpoint: cannot run fixpoint() inside a batch")
  }
  // Track which relation SoA indices changed during this fixpoint run
  let changed : Array[Bool] = []
  // Mark relations with pre-existing non-empty deltas
  for rel in self.relations {
    changed.push(not((rel.is_delta_empty)()))
  }
  self.in_fixpoint = true
  // Fixpoint loop
  for {
    // Materialize the current frontier while keeping it readable via delta_iter.
    let mut ri = 0
    while ri < self.relations.length() {
      (self.relations[ri].drain_delta)()
      ri = ri + 1
    }
    // Apply all rules
    for rule in self.rules {
      (rule.apply_delta)()
    }
    // Rules may add relations during fixpoint; track any new entries.
    while changed.length() < self.relations.length() {
      changed.push(false)
    }
    // Check convergence over staged deltas + mark changed in a single pass
    let mut has_new_facts = false
    ri = 0
    while ri < self.relations.length() {
      if not((self.relations[ri].is_staged_delta_empty)()) {
        has_new_facts = true
        changed[ri] = true
      }
      ri = ri + 1
    }
    // Next iteration frontier = this iteration's newly derived facts
    // (and old frontier is cleared).
    ri = 0
    while ri < self.relations.length() {
      (self.relations[ri].promote_staged_delta)()
      ri = ri + 1
    }
    if not(has_new_facts) {
      break
    }
  }
  self.in_fixpoint = false
  // Collect changed cell IDs
  let changed_ids : Array[CellId] = []
  let mut ri = 0
  while ri < self.relations.length() {
    if changed[ri] {
      changed_ids.push(self.relations[ri].cell_id)
    }
    ri = ri + 1
  }
  if changed_ids.length() > 0 {
    self.advance_revision(Low)
    for id in changed_ids {
      self.cell_ops[id.id].set_changed_at(self.current_revision)
    }
    if self.push_node_count > 0 {
      self.push_propagate_from(changed_ids)
    }
    self.fire_on_change()
  }
}
