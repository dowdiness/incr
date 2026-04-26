///|
/// Mark-and-sweep garbage collection on the dependency graph.
///
/// Dispose callback injection: `gc` and `gc_sweep` take a `dispose_fn :
/// (CellId) -> Unit` parameter because the per-kind dispose dispatch lives
/// on Runtime (through `CellLifecycle::dispose_cell(Runtime, ...)`).
/// Retyping the trait to take `RuntimeCore` is out of R1 scope.

///|
/// Increments the observer reference count for a cell.
/// Returns the previous count (0 means this is the first observer).
pub fn add_gc_root(core : RuntimeCore, id : CellId) -> Int {
  match core.gc_root_counts.get(id) {
    Some(n) => {
      core.gc_root_counts.set(id, n + 1)
      n
    }
    None => {
      core.gc_root_counts.set(id, 1)
      0
    }
  }
}

///|
/// Decrements the observer reference count for a cell.
/// Removes the entry when count reaches 0. Returns remaining count.
pub fn remove_gc_root(core : RuntimeCore, id : CellId) -> Int {
  match core.gc_root_counts.get(id) {
    Some(n) if n > 1 => {
      core.gc_root_counts.set(id, n - 1)
      n - 1
    }
    Some(_) => {
      core.gc_root_counts.remove(id)
      0
    }
    None => 0
  }
}

///|
/// Collects all GC roots: explicitly observed cells + implicit roots (Effects).
pub fn collect_gc_roots(core : RuntimeCore) -> Array[CellId] {
  let roots : Array[CellId] = []
  for id, _ in core.gc_root_counts {
    roots.push(id)
  }
  // Implicit roots: live cells with gc_role == Root (Effects)
  for i = 0; i < core.cell_ops.length(); i = i + 1 {
    match core.cell_index[i] {
      Disposed => continue
      _ => ()
    }
    if core.cell_ops[i].gc_role() is Root {
      roots.push(cell_id_at(core, i))
    }
  }
  roots
}

///|
/// Marks all cells reachable from `roots` via gc_dependencies BFS.
pub fn mark_reachable(
  core : RuntimeCore,
  roots : Array[CellId],
) -> @hashset.HashSet[CellId] {
  let reachable : @hashset.HashSet[CellId] = @hashset.new()
  let worklist : Array[CellId] = Array::from_iter(roots.iter())
  let mut wi = 0
  while wi < worklist.length() {
    let id = worklist[wi]
    wi += 1
    if reachable.contains(id) {
      continue
    }
    match core.cell_index[id.id] {
      Disposed => continue
      _ => ()
    }
    reachable.add(id)
    for dep in core.cell_ops[id.id].gc_dependencies() {
      worklist.push(dep)
    }
  }
  reachable
}

///|
/// Sweep phase: dispose Interior cells not in the reachable set.
pub fn gc_sweep(core : RuntimeCore, dispose_fn : (CellId) -> Unit) -> Unit {
  let roots = collect_gc_roots(core)
  let reachable = mark_reachable(core, roots)
  for i = 0; i < core.cell_ops.length(); i = i + 1 {
    match core.cell_index[i] {
      Disposed => continue
      _ => ()
    }
    if core.cell_ops[i].gc_role() is Interior {
      let id = cell_id_at(core, i)
      if !reachable.contains(id) {
        dispose_fn(id)
      }
    }
  }
}

///|
/// Runs mark-and-sweep garbage collection on the dependency graph.
///
/// `dispose_fn` closes over `Runtime::dispose_cell` at the call-site in
/// cells/runtime.mbt so per-kind CellLifecycle dispatch remains reachable.
pub fn gc(core : RuntimeCore, dispose_fn : (CellId) -> Unit) -> Unit {
  guard core.tracking.stack.is_empty() else {
    // Clean up global state before aborting so panic tests don't
    // contaminate subsequent tests via current_computing_runtime_id.
    core.tracking.stack.clear()
    set_current_computing_runtime_id(-1)
    abort("gc: cannot run during active computation")
  }
  guard core.batch.depth == 0 else { abort("gc: cannot run during batch") }
  guard core.phase is Idle else {
    abort("gc: cannot run during " + core.phase.to_string())
  }
  enter_phase(core, GarbageCollecting)
  gc_sweep(core, dispose_fn)
  leave_phase(core)
}
