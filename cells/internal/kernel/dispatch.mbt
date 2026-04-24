///|
/// Dispatch helpers: validate cells, look up metadata, manage subscriber
/// sets, and maintain push-reachable counts.
///
/// All functions here take kernel state references explicitly (no Runtime).
/// They are thin abstractions over `core.cell_index` + `core.cell_ops`
/// that cells/ wrappers delegate to. Moved from cells/runtime.mbt in R1
/// Stage 3a.

///|
/// Validates that a CellId belongs to this runtime and is within bounds.
/// Aborts with a descriptive message on failure.
pub fn validate_cell(core : RuntimeCore, id : CellId, caller : String) -> Unit {
  if id.runtime_id != core.runtime_id {
    abort("Cell belongs to a different Runtime")
  }
  if id.id < 0 || id.id >= core.cell_ops.length() {
    abort(caller + ": cell_id out of bounds: " + id.id.to_string())
  }
}

///|
/// Returns true if the CellId belongs to this runtime and is within bounds.
/// Non-aborting variant for methods that return None/[] on invalid input.
pub fn validate_cell_soft(core : RuntimeCore, id : CellId) -> Bool {
  id.runtime_id == core.runtime_id &&
  id.id >= 0 &&
  id.id < core.cell_ops.length()
}

///|
/// Returns true if a cell has been disposed or its id is out of bounds.
pub fn is_cell_disposed(core : RuntimeCore, cell_id : CellId) -> Bool {
  let id = cell_id.id
  id < 0 || id >= core.cell_index.length() || core.cell_index[id] is Disposed
}

///|
/// Returns the `changed_at` revision for any cell, dispatching via cell_index.
pub fn get_changed_at(core : RuntimeCore, id : CellId) -> Revision {
  validate_cell(core, id, "get_changed_at")
  core.cell_ops[id.id].changed_at()
}

///|
/// Returns the `durability` for any cell, dispatching via cell_index.
pub fn get_durability(core : RuntimeCore, id : CellId) -> Durability {
  validate_cell(core, id, "get_durability")
  core.cell_ops[id.id].durability()
}

///|
/// Returns the CellId stored in the given SoA entry (reverse lookup).
pub fn cell_id_for(
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  cell_ref : CellRef,
) -> CellId {
  match cell_ref {
    PullSignal(idx) => pull.signals[idx].meta.cell_id
    PullMemo(idx) => pull.memos[idx].meta.cell_id
    PushReactive(idx) => push.reactives[idx].meta.cell_id
    PushEffect(idx) => push.effects[idx].meta.cell_id
    HybridMemo(idx) => pull.memos[idx].meta.cell_id
    Disposed => abort("cell_id_for: cell has been disposed")
    Relation(idx) => datalog.relations[idx].meta.cell_id
    FunctionalRelation(idx) => datalog.functional_relations[idx].meta.cell_id
    Rule(idx) => datalog.rules[idx].meta.cell_id
  }
}

///|
/// Returns an iterator over the subscriber IDs for the given cell.
pub fn get_subscribers(core : RuntimeCore, cell_id : CellId) -> Iter[CellId] {
  validate_cell(core, cell_id, "get_subscribers")
  core.cell_ops[cell_id.id].subscribers().iter()
}

///|
/// Returns the push-reachable contribution of `sub_id` as a subscriber.
pub fn push_contribution(
  core : RuntimeCore,
  pull : PullState,
  sub_id : CellId,
) -> Int {
  if sub_id.id < 0 || sub_id.id >= core.cell_index.length() {
    return 0
  }
  match core.cell_index[sub_id.id] {
    PushReactive(_) | PushEffect(_) => 1
    PullMemo(i) | HybridMemo(i) => pull.memos[i].meta.push_reachable_count
    _ => 0
  }
}

///|
/// Collects all cells reachable upstream of `sources` through the pull
/// dependency graph.
pub fn collect_reachable_cells(
  core : RuntimeCore,
  pull : PullState,
  sources : Array[CellId],
) -> @hashset.HashSet[CellId] {
  let result : @hashset.HashSet[CellId] = @hashset.new()
  let worklist : Array[CellId] = []
  for id in sources {
    worklist.push(id)
  }
  let mut wi = 0
  while wi < worklist.length() {
    let id = worklist[wi]
    wi += 1
    if result.contains(id) {
      continue
    }
    if id.id < 0 || id.id >= core.cell_index.length() {
      continue
    }
    match core.cell_index[id.id] {
      Disposed => ()
      PullSignal(_) => result.add(id)
      PushReactive(_) | Relation(_) | FunctionalRelation(_) | Rule(_) =>
        result.add(id)
      PullMemo(i) | HybridMemo(i) => {
        result.add(id)
        for dep in pull.memos[i].dependencies {
          worklist.push(dep)
        }
      }
      PushEffect(_) => ()
    }
  }
  result
}

///|
/// Adjusts `push_reachable_count` by `delta` on every cell reachable upstream
/// of `sources` (including the sources themselves).
pub fn adjust_push_reachable(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  sources : Array[CellId],
  delta : Int,
) -> Unit {
  let cells = collect_reachable_cells(core, pull, sources)
  for id in cells {
    // CellMeta is heap-allocated — extracting it gives a mutable reference.
    let meta = match core.cell_index[id.id] {
      PullSignal(i) => pull.signals[i].meta
      PullMemo(i) | HybridMemo(i) => pull.memos[i].meta
      PushReactive(i) => push.reactives[i].meta
      PushEffect(i) => push.effects[i].meta
      Relation(i) => datalog.relations[i].meta
      FunctionalRelation(i) => datalog.functional_relations[i].meta
      Rule(i) => datalog.rules[i].meta
      Disposed => continue
    }
    let new_count = meta.push_reachable_count + delta
    if new_count < 0 {
      abort(
        "adjust_push_reachable: count went negative for cell " +
        id.id.to_string() +
        " (delta=" +
        delta.to_string() +
        ", was=" +
        meta.push_reachable_count.to_string() +
        ")",
      )
    }
    meta.push_reachable_count = new_count
  }
}

///|
/// Removes `subscriber` from the subscriber set of `dep` and decrements the
/// subscriber's push contribution from upstream cells.
pub fn remove_subscriber(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  validate_cell(core, dep, "remove_subscriber(dep)")
  let contribution = push_contribution(core, pull, subscriber)
  let removed = core.cell_ops[dep.id].subscribers().remove_and_check(subscriber)
  if removed && contribution > 0 {
    adjust_push_reachable(core, pull, push, datalog, [dep], -contribution)
  }
}

///|
/// Adds `subscriber` to the subscriber set of `dep` and propagates the
/// subscriber's push contribution upstream through the pull dep graph.
pub fn add_subscriber(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  validate_cell(core, dep, "add_subscriber(dep)")
  let subs = core.cell_ops[dep.id].subscribers()
  if subs.contains(subscriber) {
    return
  }
  subs.add(subscriber)
  let contribution = push_contribution(core, pull, subscriber)
  if contribution > 0 {
    adjust_push_reachable(core, pull, push, datalog, [dep], contribution)
  }
}

///|
/// Reconstructs a CellId from a cell_ops array index.
pub fn cell_id_at(core : RuntimeCore, i : Int) -> CellId {
  { runtime_id: core.runtime_id, id: i }
}
