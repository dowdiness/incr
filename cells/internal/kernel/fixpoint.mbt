///|
/// Runs fixpoint evaluation over all registered rules until no new facts
/// are derived. Returns the array of changed relation cell IDs.
///
/// Algorithm (semi-naive evaluation):
/// 1. Snapshot each relation's materialized state for net-change checks
/// 2. Materialize each relation's current frontier `delta` into `current`
/// 3. Apply all rules — rule bodies read `delta` (frontier) and `current`,
///    and insert newly derived facts into staged deltas
/// 4. Promote staged deltas to next iteration's frontier (clears old
///    frontier)
/// 5. If no staged deltas were produced, stop; otherwise repeat
/// 6. Collect net-changed cell IDs — the caller (Runtime::fixpoint) calls
///    publish_cell_changes if any materialized state changed.
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
  for rel in datalog.relations {
    (rel.begin_fixpoint)()
  }
  for fr in datalog.functional_relations {
    (fr.begin_fixpoint)()
  }
  enter_phase(core, InFixpoint)
  for ;; {
    // Materialize the current frontier while keeping it readable via delta_iter.
    for rel in datalog.relations {
      (rel.drain_delta)()
    }
    for fr in datalog.functional_relations {
      (fr.drain_delta)()
    }
    // Apply all rules (skip disposed)
    for rule in datalog.rules {
      guard !is_cell_disposed(core, rule.meta.cell_id) else { continue }
      (rule.apply_delta)()
    }
    // Check convergence over staged deltas.
    let mut has_new_facts = false
    for rel in datalog.relations {
      if !(rel.is_staged_delta_empty)() {
        has_new_facts = true
      }
    }
    for fr in datalog.functional_relations {
      if !(fr.is_staged_delta_empty)() {
        has_new_facts = true
      }
    }
    // Next iteration frontier = this iteration's newly derived facts.
    for rel in datalog.relations {
      (rel.promote_staged_delta)()
    }
    for fr in datalog.functional_relations {
      (fr.promote_staged_delta)()
    }
    if !has_new_facts {
      break
    }
  }
  leave_phase(core)
  // Collect net changed cell IDs.
  let changed_ids : Array[CellId] = []
  for rel in datalog.relations {
    if (rel.finish_fixpoint_changed)() {
      changed_ids.push(rel.meta.cell_id)
    }
  }
  for fr in datalog.functional_relations {
    if (fr.finish_fixpoint_changed)() {
      changed_ids.push(fr.meta.cell_id)
    }
  }
  changed_ids
}
