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
  // Track which relation SoA indices changed during this fixpoint run
  let changed_set : @hashset.HashSet[Int] = @hashset.new()
  // Mark relations with pre-existing non-empty deltas
  for i = 0; i < self.relations.length(); i = i + 1 {
    if not((self.relations[i].is_delta_empty)()) {
      changed_set.add(i)
    }
  }
  self.in_fixpoint = true
  // Fixpoint loop
  for {
    // Materialize the current frontier while keeping it readable via delta_iter.
    for rel in self.relations {
      (rel.drain_delta)()
    }
    // Apply all rules
    for rule in self.rules {
      (rule.apply_delta)()
    }
    // Check convergence over staged deltas + mark changed in a single pass
    let mut has_new_facts = false
    for i = 0; i < self.relations.length(); i = i + 1 {
      if not((self.relations[i].is_staged_delta_empty)()) {
        has_new_facts = true
        changed_set.add(i)
      }
    }
    // Next iteration frontier = this iteration's newly derived facts
    // (and old frontier is cleared).
    for rel in self.relations {
      (rel.promote_staged_delta)()
    }
    if not(has_new_facts) {
      break
    }
  }
  self.in_fixpoint = false
  // Collect changed cell IDs
  let changed_ids : Array[CellId] = []
  for i = 0; i < self.relations.length(); i = i + 1 {
    if changed_set.contains(i) {
      changed_ids.push(self.relations[i].cell_id)
    }
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
