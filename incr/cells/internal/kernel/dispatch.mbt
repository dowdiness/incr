///|
/// Dispatch helpers: validate cells, look up metadata, manage subscriber
/// sets, and maintain push-reachable counts.
///
/// All functions here take kernel state references explicitly (no Runtime).
/// They are thin abstractions over `core.cell_index` + `core.cell_ops`
/// that cells/ wrappers delegate to.

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
/// Whether `cell_id` counts as a *live* subscriber — i.e. a subscriber whose
/// presence makes its dependency push-reachable. A push cell (Reactive/Effect)
/// is always live; a pull/hybrid memo is live iff it is itself push-reachable
/// (its own `push_reachable_count > 0`). Signals and datalog cells never make a
/// dependency push-reachable as subscribers (this mirrors the old
/// `push_contribution` returning 0 for those kinds).
pub fn is_live_subscriber(
  core : RuntimeCore,
  pull : PullState,
  cell_id : CellId,
) -> Bool {
  if cell_id.id < 0 || cell_id.id >= core.cell_index.length() {
    return false
  }
  match core.cell_index[cell_id.id] {
    PushReactive(_) | PushEffect(_) => true
    PullMemo(i) | HybridMemo(i) => pull.memos[i].meta.push_reachable_count > 0
    _ => false
  }
}

///|
/// Incrementally maintains `push_reachable_count` as the number of a cell's
/// DIRECT live subscribers (see `is_live_subscriber`). Applies `delta` to
/// `start`'s count and, whenever a cell's own live/not-live status flips across
/// the `count == 0` boundary, propagates a `+1`/`-1` to each of its upstream
/// pull/hybrid-memo dependencies — because the flip changes whether that cell is
/// itself a live subscriber of those dependencies. Propagation only follows
/// boundary crossings, so total work is O(cells touched), with no path
/// multiplicity (the diamond-arm-drop bug the deduped mass model had).
///
/// Upstream traversal goes through pull/hybrid memo `dependencies` only; all
/// other kinds are leaves, so signals and datalog cells keep their previous
/// reachability behavior.
///
/// Termination relies on the pull dependency graph being ACYCLIC (incr forbids
/// recorded dependency cycles). Each cell flips its live status at most once per
/// call and only then pushes its dependencies, so total work is O(edges) on a
/// DAG. A "seen" dedup is intentionally NOT used: a cell legitimately appears on
/// the worklist once per flipping subscriber (that multiplicity is exactly its
/// direct-live-subscriber count), so deduping would corrupt the count.
pub fn propagate_liveness(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  start : CellId,
  delta : Int,
) -> Unit {
  let stack : Array[(CellId, Int)] = [(start, delta)]
  for ;; {
    let (id, d) = match stack.pop() {
      Some(pair) => pair
      None => break
    }
    let was_live = is_live_subscriber(core, pull, id)
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
    let new_count = meta.push_reachable_count + d
    if new_count < 0 {
      abort(
        "propagate_liveness: count went negative for cell " +
        id.id.to_string() +
        " (delta=" +
        d.to_string() +
        ", was=" +
        meta.push_reachable_count.to_string() +
        ")",
      )
    }
    meta.push_reachable_count = new_count
    let now_live = is_live_subscriber(core, pull, id)
    if was_live != now_live {
      let sub_delta = if now_live { 1 } else { -1 }
      match core.cell_index[id.id] {
        PullMemo(i) | HybridMemo(i) =>
          for upstream in pull.memos[i].dependencies {
            stack.push((upstream, sub_delta))
          }
        _ => ()
      }
    }
  }
}

///|
/// Removes `subscriber` from the subscriber set of `dep`. If the subscriber was
/// live, `dep` loses one live subscriber, which may cascade upstream.
pub fn remove_subscriber(
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  dep : CellId,
  subscriber : CellId,
) -> Unit {
  validate_cell(core, dep, "remove_subscriber(dep)")
  let live = is_live_subscriber(core, pull, subscriber)
  let removed = core.cell_ops[dep.id].subscribers().remove_and_check(subscriber)
  if removed && live {
    propagate_liveness(core, pull, push, datalog, dep, -1)
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
  if is_live_subscriber(core, pull, subscriber) {
    propagate_liveness(core, pull, push, datalog, dep, 1)
  }
}

///|
/// Reconstructs a CellId from a cell_ops array index.
pub fn cell_id_at(core : RuntimeCore, i : Int) -> CellId {
  { runtime_id: core.runtime_id, id: i }
}
