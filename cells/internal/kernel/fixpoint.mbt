///|
/// Runs fixpoint evaluation over all registered rules until no new facts
/// are derived. Returns the array of changed relation cell IDs.
///
/// Algorithm (semi-naive evaluation):
/// 1. Materialize each relation's current frontier `delta` into `current`
/// 2. Apply all rules — rule bodies read `delta` (frontier) and `current`,
///    and insert newly derived facts into staged deltas
/// 3. Record which relations produced staged deltas this iteration
/// 4. Promote staged deltas to next iteration's frontier (clears old
///    frontier)
/// 5. If no staged deltas were produced, stop; otherwise repeat
/// 6. Collect changed cell IDs — the caller (Runtime::fixpoint) calls
///    publish_cell_changes if any changed.
pub fn run_fixpoint(
  core : RuntimeCore,
  datalog : DatalogState,
) -> Array[CellId] {
  if core.phase is InFixpoint {
    abort("fixpoint: re-entrant fixpoint() is not supported")
  }
  if core.batch.depth > 0 {
    abort("fixpoint: cannot run fixpoint() inside a batch")
  }
  // Track which relation SoA indices changed during this fixpoint run
  let changed : Array[Bool] = []
  for rel in datalog.relations {
    changed.push(!(rel.is_delta_empty)())
  }
  let fr_changed : Array[Bool] = []
  for fr in datalog.functional_relations {
    fr_changed.push(!(fr.is_delta_empty)())
  }
  enter_phase(core, InFixpoint)
  for ;; {
    // Materialize the current frontier while keeping it readable via delta_iter.
    let mut ri = 0
    while ri < datalog.relations.length() {
      (datalog.relations[ri].drain_delta)()
      ri = ri + 1
    }
    let mut fi = 0
    while fi < datalog.functional_relations.length() {
      (datalog.functional_relations[fi].drain_delta)()
      fi = fi + 1
    }
    // Apply all rules (skip disposed)
    for rule in datalog.rules {
      guard !is_cell_disposed(core, rule.meta.cell_id) else { continue }
      (rule.apply_delta)()
    }
    // Rules may add relations during fixpoint; track any new entries.
    while changed.length() < datalog.relations.length() {
      changed.push(false)
    }
    while fr_changed.length() < datalog.functional_relations.length() {
      fr_changed.push(false)
    }
    // Check convergence over staged deltas + mark changed in a single pass
    let mut has_new_facts = false
    ri = 0
    while ri < datalog.relations.length() {
      if !(datalog.relations[ri].is_staged_delta_empty)() {
        has_new_facts = true
        changed[ri] = true
      }
      ri = ri + 1
    }
    fi = 0
    while fi < datalog.functional_relations.length() {
      if !(datalog.functional_relations[fi].is_staged_delta_empty)() {
        has_new_facts = true
        fr_changed[fi] = true
      }
      fi = fi + 1
    }
    // Next iteration frontier = this iteration's newly derived facts.
    ri = 0
    while ri < datalog.relations.length() {
      (datalog.relations[ri].promote_staged_delta)()
      ri = ri + 1
    }
    fi = 0
    while fi < datalog.functional_relations.length() {
      (datalog.functional_relations[fi].promote_staged_delta)()
      fi = fi + 1
    }
    if !has_new_facts {
      break
    }
  }
  leave_phase(core)
  // Collect changed cell IDs
  let changed_ids : Array[CellId] = []
  let mut ri = 0
  while ri < datalog.relations.length() {
    if changed[ri] {
      changed_ids.push(datalog.relations[ri].meta.cell_id)
    }
    ri = ri + 1
  }
  let mut fi = 0
  while fi < datalog.functional_relations.length() {
    if fr_changed[fi] {
      changed_ids.push(datalog.functional_relations[fi].meta.cell_id)
    }
    fi = fi + 1
  }
  changed_ids
}
