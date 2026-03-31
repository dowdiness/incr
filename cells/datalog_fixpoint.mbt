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
  if self.core.in_fixpoint {
    abort("fixpoint: re-entrant fixpoint() is not supported")
  }
  if self.core.batch_depth > 0 {
    abort("fixpoint: cannot run fixpoint() inside a batch")
  }
  // Track which relation SoA indices changed during this fixpoint run
  let changed : Array[Bool] = []
  // Mark relations with pre-existing non-empty deltas
  for rel in self.datalog.relations {
    changed.push(!(rel.is_delta_empty)())
  }
  // Track which functional relation SoA indices changed during this fixpoint run
  let fr_changed : Array[Bool] = []
  for fr in self.datalog.functional_relations {
    fr_changed.push(!(fr.is_delta_empty)())
  }
  self.core.in_fixpoint = true
  // Fixpoint loop
  for ;; {
    // Materialize the current frontier while keeping it readable via delta_iter.
    let mut ri = 0
    while ri < self.datalog.relations.length() {
      (self.datalog.relations[ri].drain_delta)()
      ri = ri + 1
    }
    let mut fi = 0
    while fi < self.datalog.functional_relations.length() {
      (self.datalog.functional_relations[fi].drain_delta)()
      fi = fi + 1
    }
    // Apply all rules
    for rule in self.datalog.rules {
      (rule.apply_delta)()
    }
    // Rules may add relations during fixpoint; track any new entries.
    while changed.length() < self.datalog.relations.length() {
      changed.push(false)
    }
    while fr_changed.length() < self.datalog.functional_relations.length() {
      fr_changed.push(false)
    }
    // Check convergence over staged deltas + mark changed in a single pass
    let mut has_new_facts = false
    ri = 0
    while ri < self.datalog.relations.length() {
      if !(self.datalog.relations[ri].is_staged_delta_empty)() {
        has_new_facts = true
        changed[ri] = true
      }
      ri = ri + 1
    }
    fi = 0
    while fi < self.datalog.functional_relations.length() {
      if !(self.datalog.functional_relations[fi].is_staged_delta_empty)() {
        has_new_facts = true
        fr_changed[fi] = true
      }
      fi = fi + 1
    }
    // Next iteration frontier = this iteration's newly derived facts
    // (and old frontier is cleared).
    ri = 0
    while ri < self.datalog.relations.length() {
      (self.datalog.relations[ri].promote_staged_delta)()
      ri = ri + 1
    }
    fi = 0
    while fi < self.datalog.functional_relations.length() {
      (self.datalog.functional_relations[fi].promote_staged_delta)()
      fi = fi + 1
    }
    if !has_new_facts {
      break
    }
  }
  self.core.in_fixpoint = false
  // Collect changed cell IDs
  let changed_ids : Array[CellId] = []
  let mut ri = 0
  while ri < self.datalog.relations.length() {
    if changed[ri] {
      changed_ids.push(self.datalog.relations[ri].meta.cell_id)
    }
    ri = ri + 1
  }
  let mut fi = 0
  while fi < self.datalog.functional_relations.length() {
    if fr_changed[fi] {
      changed_ids.push(self.datalog.functional_relations[fi].meta.cell_id)
    }
    fi = fi + 1
  }
  if changed_ids.length() > 0 {
    self.publish_cell_changes(changed_ids, Low)
  }
}
