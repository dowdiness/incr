///|
/// Runs fixpoint evaluation over all registered rules until no new facts are derived.
///
/// Algorithm (semi-naive evaluation):
/// 1. Apply all rules — rule bodies read deltas and current sets, inserting new facts into deltas
/// 2. Check convergence: if no output relation has non-empty deltas, break
/// 3. Drain all relation deltas into their current sets
/// 4. Repeat from step 1
/// 5. Final drain to flush remaining deltas (including input-only relations on the first call)
/// 6. If any relation changed, advance revision and update changed_at
pub fn Runtime::fixpoint(self : Runtime) -> Unit {
  // Collect unique output-relation SoA indices for convergence checking
  let output_indices : @hashset.HashSet[Int] = @hashset.new()
  for rule in self.rules {
    for out_id in rule.output_relations {
      match self.cell_index[out_id.id] {
        Relation(idx) => output_indices.add(idx)
        _ => abort("fixpoint: output cell_id is not a Relation")
      }
    }
  }
  // Track which relation SoA indices changed during this fixpoint run
  let changed_set : @hashset.HashSet[Int] = @hashset.new()
  // Mark relations with pre-existing non-empty deltas
  for i = 0; i < self.relations.length(); i = i + 1 {
    if not((self.relations[i].is_delta_empty)()) {
      changed_set.add(i)
    }
  }
  // Fixpoint loop
  for {
    // Apply all rules
    for rule in self.rules {
      (rule.apply_delta)()
    }
    // Check convergence + mark changed in a single pass
    let mut has_new_facts = false
    for idx in output_indices {
      if not((self.relations[idx].is_delta_empty)()) {
        has_new_facts = true
        changed_set.add(idx)
      }
    }
    if not(has_new_facts) {
      break
    }
    // Drain all relation deltas into current
    for rel in self.relations {
      (rel.drain_delta)()
    }
  }
  // Final drain: flush remaining deltas (including input-only relations)
  // and collect changed cell IDs in a single pass
  let changed_ids : Array[CellId] = []
  for i = 0; i < self.relations.length(); i = i + 1 {
    if not((self.relations[i].is_delta_empty)()) {
      changed_set.add(i)
    }
    (self.relations[i].drain_delta)()
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
  }
}
