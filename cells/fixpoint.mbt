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
fn Runtime::fixpoint(self : Runtime) -> Unit {
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
  // Track which relations had any facts inserted
  let changed_ids : Array[CellId] = []
  // Mark relations with non-empty deltas as changed
  for rel in self.relations {
    if not((rel.is_delta_empty)()) {
      rel.changed = true
    }
  }
  // Fixpoint loop
  for {
    // Apply all rules
    for rule in self.rules {
      (rule.apply_delta)()
    }
    // Check convergence: are any output-relation deltas non-empty?
    let mut has_new_facts = false
    for idx in output_indices {
      if not((self.relations[idx].is_delta_empty)()) {
        has_new_facts = true
        break
      }
    }
    if not(has_new_facts) {
      break
    }
    // Mark output relations with non-empty deltas as changed
    for idx in output_indices {
      if not((self.relations[idx].is_delta_empty)()) {
        self.relations[idx].changed = true
      }
    }
    // Drain all relation deltas into current
    for rel in self.relations {
      (rel.drain_delta)()
    }
  }
  // Final drain: flush remaining deltas (including input-only relations)
  for rel in self.relations {
    if not((rel.is_delta_empty)()) {
      rel.changed = true
    }
    (rel.drain_delta)()
  }
  // Advance revision if any relation changed
  for rel in self.relations {
    if rel.changed {
      changed_ids.push(rel.cell_id)
      rel.changed = false
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
