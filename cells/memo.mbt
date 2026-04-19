///|
/// A derived computation with automatic dependency tracking and memoization.
///
/// Memos are the interior nodes of the dependency graph. They compute a value
/// from other signals and memos, cache the result, and only recompute when
/// their dependencies actually change.
///
/// # Key Features
///
/// - **Lazy evaluation**: The compute function is not called until `get()`.
/// - **Automatic tracking**: Dependencies are discovered by intercepting `get()` calls.
/// - **Memoization**: Results are cached; repeated `get()` calls return the cached value.
/// - **Backdating**: If a recomputation produces the same value, downstream memos skip work.
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime()
/// let a = Signal(rt, 10)
/// let b = Signal(rt, 20)
/// let sum = Memo(rt, () => a.get() + b.get())
///
/// inspect(rt.read(sum), content="30")  // Computes and caches
///
/// a.set(15)
/// inspect(rt.read(sum), content="35")  // Recomputes because `a` changed
/// ```
pub(all) struct Memo[T] {
  priv label : String?
  priv rt : Runtime
  priv cell_id : CellId
  priv compute : () -> T raise Failure
  priv backdate_eq : (T, T) -> Bool // captured at construction; replaces hardcoded a==b
  priv mut value : T?

  fn[T : Eq] new(
    rt : Runtime,
    compute : () -> T raise Failure,
    label? : String,
  ) -> Memo[T]
} derive(Debug(ignore=[Runtime, Fn, CellId]))

///|
// Shared SoA allocation + registration for all Memo constructors.
// Done here (not on Runtime) because the compute closure must capture the
// typed `memo` struct — a construction cycle that prevents moving this into
// a standalone Runtime method.
fn[T] Memo::_create(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
  backdate_eq : (T, T) -> Bool,
) -> Memo[T] {
  let memo_idx = rt.pull.free_memos.pop().unwrap_or(rt.pull.memos.length())
  let cell_id = rt.alloc_cell_id(PullMemo(memo_idx))
  let memo : Memo[T] = { label, rt, cell_id, compute, backdate_eq, value: None }
  let new_data : MemoData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
      push_reachable_count: 0,
    },
    compute: () => memo.recompute_inner(),
    verified_at: Revision::initial(),
    dependencies: [],
    in_progress: false,
    on_change: None,
    is_hybrid: false,
    accumulator_reads: @hashmap.new(),
    has_been_computed: false,
  }
  if memo_idx < rt.pull.memos.length() {
    rt.pull.memos[memo_idx] = new_data
  } else {
    rt.pull.memos.push(new_data)
  }
  let ops : &CellOps = rt.pull.memos[memo_idx]
  rt.core.cell_ops.push(ops)
  let lifecycle : &CellLifecycle = rt.pull.memos[memo_idx]
  rt.core.cell_lifecycle.push(lifecycle)
  memo
}

///|
/// Creates a new memo with the given compute function.
///
/// The compute function is called lazily on the first `get()` call, not
/// at creation time. Every `Signal::get()` or `Memo::get()` call inside
/// the compute function is automatically recorded as a dependency.
///
/// # Parameters
///
/// - `rt`: The runtime that will manage this memo
/// - `compute`: A function that computes the derived value
///
/// # Returns
///
/// A new memo. The compute function has not yet been called.
///
/// # Type Constraints
///
/// `T` must implement `Eq` for backdating: when the compute function returns
/// the same value as before, the memo's `changed_at` timestamp is preserved,
/// preventing unnecessary downstream recomputation.
///
/// For other backdate strategies use:
/// - `Memo::new_memo` — `T : BackdateEq`; compares `changed_at` revisions by default (O(1))
/// - `Memo::new_no_backdate` — no constraint on `T`; never backdates
pub fn[T : Eq] Memo::new(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
) -> Memo[T] {
  Memo::_create(rt, compute, label?, (a, b) => a == b)
}

///|
/// Creates a memo using `BackdateEq` for change detection.
/// `T` must implement `BackdateEq` (and its supertrait `HasChangedAt`).
/// The backdate check calls `BackdateEq::backdate_equal`, not structural `Eq`.
pub fn[T : BackdateEq] Memo::new_memo(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
) -> Memo[T] {
  Memo::_create(rt, compute, label?, (a, b) => a.backdate_equal(b))
}

///|
/// Creates a memo that never backdates: always marks as changed on recomputation.
/// Use when the cost of comparison exceeds the benefit, or when downstream memos
/// will always need to recompute anyway.
/// No trait constraint on `T`.
pub fn[T] Memo::new_no_backdate(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
) -> Memo[T] {
  Memo::_create(rt, compute, label?, (_, _) => false)
}

///|
/// Returns the memoized value, recomputing if necessary.
///
/// Must be called inside a tracked context (another memo's compute function).
/// Outside a compute function, use `rt.read(memo)` or `memo.observe()`.
///
/// If called inside another memo's compute function, this automatically
/// records a dependency.
///
/// # Returns
///
/// The current (possibly recomputed) value
///
/// # Panics
///
/// Aborts if called outside tracked context, or if a cycle is detected.
/// Use `get_result()` for error-returning cycle handling, or `rt.read()`
/// for outside-the-graph reads.
pub fn[T] Memo::get(self : Memo[T]) -> T {
  guard self.rt.core.tracking.stack.length() > 0 else {
    abort(
      "Memo::get() called outside tracked context. Use rt.read(memo) or memo.observe() to read from outside the graph.",
    )
  }
  match self.get_result() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Returns the memoized value as a Result, recomputing if necessary.
///
/// This is the error-returning version of `get()`. Use this method when you
/// want to handle cycles gracefully instead of aborting.
///
/// # Returns
///
/// `Ok(value)` with the current (possibly recomputed) value, or
/// `Err(CycleError)` if a cycle is detected
///
/// # Example
///
/// ```moonbit nocheck
/// match memo.get_result() {
///   Ok(value) => println("Got: " + value.to_string())
///   Err(err) => {
///     println("Cycle at " + err.cell().to_string())
///     println("Path: " + err.format_path(rt))
///   }
/// }
/// ```
pub fn[T] Memo::get_result(self : Memo[T]) -> Result[T, CycleError] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Memo::get called on a disposed memo")
  }
  self.rt.check_cross_runtime(self.rt.core.runtime_id, "Memo")
  self.get_result_inner() catch {
    e => abort("Memo compute raised: " + e.to_string())
  }
}

///|
/// Internal: the core verification logic, callable from both get_result()
/// and get_untracked(). Does NOT check tracking context.
fn[T] Memo::get_result_inner(
  self : Memo[T],
) -> Result[T, CycleError] raise Failure {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Memo::get called on a disposed memo")
  }
  // If this runtime's tracking stack is empty, any non-negative
  // `current_computing_runtime_id` is stale from a prior aborted
  // computation; repair it instead of treating it as a cross-runtime read.
  // This forgiving repair is required by panic-test call patterns that
  // bypass `get_result`'s outer strict check (e.g. `get_untracked`,
  // `MemoMap::get_or_create_memo`).
  let active_rt = current_computing_runtime_id.val
  if active_rt >= 0 {
    if self.rt.core.tracking.stack.is_empty() {
      current_computing_runtime_id.val = -1
    } else if active_rt != self.rt.core.runtime_id {
      current_computing_runtime_id.val = -1
      abort(
        "Cross-runtime dependency: Memo belongs to Runtime " +
        self.rt.core.runtime_id.to_string() +
        " but is read inside a computation on Runtime " +
        active_rt.to_string(),
      )
    }
  }
  if self.rt.core.phase is InFixpoint {
    abort(
      "Memo::get() cannot be called during fixpoint(); read relations directly or call get() after fixpoint() completes",
    )
  }
  // First computation: no cached value yet
  match self.value {
    None =>
      match self.force_recompute() {
        Ok(value) => {
          // Only record dependency on successful read to avoid poisoning
          // the dependency graph with failed cyclic edges
          self.rt.record_dependency(self.cell_id)
          Ok(value)
        }
        Err(e) => Err(e)
      }
    Some(cached) => {
      // Fast path: already verified this revision
      let cell = self.rt.get_memo_data(self.cell_id)
      if cell.verified_at >= self.rt.core.revision.current_revision {
        self.rt.record_dependency(self.cell_id)
        return Ok(cached)
      }
      // Check if any dependency changed since last verification.
      // Note: pull_verify may recompute this cell internally
      // (via compute closure) to determine if value actually changed.
      match self.rt.pull_verify(self.cell_id) {
        Ok(_) => {
          self.rt.record_dependency(self.cell_id)
          // Re-read self.value: pull_verify may have called
          // force_recompute, replacing the cached value with a new one.
          // The outer Some(cached) binding may be stale.
          match self.value {
            Some(v) => Ok(v)
            None =>
              abort(
                "unreachable: value is always Some after successful verification",
              )
          }
        }
        Err(e) => Err(e)
      }
    }
  }
}

///|
/// Package-private untracked read. Bypasses the tracked-context guard.
/// Used by Observer to read from outside the dependency graph.
fn[T] Memo::get_untracked(self : Memo[T]) -> T {
  let r = self.get_result_inner() catch {
    e => abort("Memo compute raised: " + e.to_string())
  }
  match r {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Returns the memoized value, or `fallback` if a cycle is detected.
///
/// This is a convenience wrapper around `get_result()` for call sites that
/// prefer a non-panicking, non-Result API.
pub fn[T] Memo::get_or(self : Memo[T], fallback : T) -> T {
  match self.get_result() {
    Ok(value) => value
    Err(_) => fallback
  }
}

///|
/// Returns the memoized value, or computes a fallback value from the cycle error.
///
/// This is a convenience wrapper around `get_result()` for graceful recovery.
pub fn[T] Memo::get_or_else(self : Memo[T], fallback : (CycleError) -> T) -> T {
  match self.get_result() {
    Ok(value) => value
    Err(e) => fallback(e)
  }
}

///|
/// Force recomputation: delegates to shared memo_force_recompute helper.
///
/// Returns `Ok(new_value)` on success, or `Err(CycleError)` if a cycle is detected.
fn[T] Memo::force_recompute(
  self : Memo[T],
) -> Result[T, CycleError] raise Failure {
  match
    self.rt.memo_force_recompute(
      self.cell_id,
      self.compute,
      self.value,
      self.backdate_eq,
    ) {
    Ok(new_value) => {
      self.value = Some(new_value)
      Ok(new_value)
    }
    Err(e) => Err(e)
  }
}

///|
/// Internal: recompute and return whether the value changed.
/// This is the closure stored in CellMeta for type-erased recomputation.
///
/// Returns `Ok(true)` if the value changed, `Ok(false)` if unchanged (backdated),
/// or `Err(CycleError)` if a cycle is detected.
fn[T] Memo::recompute_inner(
  self : Memo[T],
) -> Result[Bool, CycleError] raise Failure {
  let cell = self.rt.get_memo_data(self.cell_id)
  let old_changed_at = cell.meta.changed_at
  match self.force_recompute() {
    Ok(_) => {
      let changed = cell.meta.changed_at != old_changed_at
      if changed {
        match cell.on_change {
          Some(f) => f()
          None => ()
        }
      }
      Ok(changed)
    }
    Err(e) => Err(e)
  }
}

///|
/// Compute the durability of a derived cell from its dependencies.
/// A derived cell's durability is the minimum of its dependencies' durabilities.
fn compute_durability(rt : Runtime, deps : Array[CellId]) -> Durability {
  if deps.length() == 0 {
    return Low
  }
  let mut min_dur = Durability::High
  for dep_id in deps {
    let dur = rt.get_durability(dep_id)
    if dur < min_dur {
      min_dur = dur
    }
  }
  min_dur
}

///|
/// Shared force-recompute logic for all memo types (pull and hybrid).
///
/// Handles cycle detection, dependency tracking, subscriber link maintenance,
/// durability recomputation, and backdating.
///
/// # Parameters
///
/// - `cell_id`: The memo's CellId
/// - `compute_fn`: The typed compute function
/// - `old_value`: The previous cached value (None if first computation)
/// - `eq_fn`: Equality check for backdating
///
/// # Returns
///
/// `Ok(new_value)` on success, `Err(CycleError)` if a cycle is detected
fn[T] Runtime::memo_force_recompute(
  self : Runtime,
  cell_id : CellId,
  compute_fn : () -> T raise Failure,
  old_value : T?,
  eq_fn : (T, T) -> Bool,
) -> Result[T, CycleError] raise Failure {
  let cell = self.get_memo_data(cell_id)
  if cell.in_progress {
    return Err(
      CycleError::from_path(
        self,
        self.collect_tracking_path(),
        cell.meta.cell_id,
      ),
    )
  }
  cell.in_progress = true

  // BEFORE_CLOSURE: snapshot each accumulator slot that M contributed to
  // in its previous successful compute. Clone the set — prev_contributions
  // is iterated AFTER compute and must not reflect touched_accumulator_slots.
  let prev_contributions : Array[@incr_types.AccumulatorId] = match
    self.accumulator_contributions.get(cell_id) {
    Some(s) => {
      let arr : Array[@incr_types.AccumulatorId] = []
      for x in s {
        arr.push(x)
      }
      arr
    }
    None => []
  }
  for slot_id in prev_contributions {
    let slot = self.accumulator_slots[slot_id.id]
    if !slot.disposed {
      (slot.snapshot_and_clear)(cell_id)
    }
  }

  let old_deps = cell.dependencies
  self.push_tracking(cell_id)

  // Run user compute. On raise → ON_ABORT path.
  let new_value = compute_fn() catch {
    e => {
      // Extract the still-live top frame to see which slots got touched
      // during this aborted run.
      let touched : Array[@incr_types.AccumulatorId] = match
        self.top_active_query() {
        Some(q) => {
          let arr : Array[@incr_types.AccumulatorId] = []
          for x in q.touched_accumulator_slots {
            arr.push(x)
          }
          arr
        }
        None => []
      }
      // ON_ABORT.1: restore snapshots for every slot in prev_contributions.
      for slot_id in prev_contributions {
        let slot = self.accumulator_slots[slot_id.id]
        if !slot.disposed {
          (slot.restore_buffer)(cell_id)
        }
      }
      // ON_ABORT.2: for slots touched during this run but NOT in prev,
      // clear only the in-flight per_memo buffer. Do NOT use dispose_memo
      // here — it would also erase push_revised_at[M], rolling back a
      // prior successful run's revision marker and causing consumers
      // with a pre-existing stored read to miss invalidation.
      for slot_id in touched {
        // Contains-check: skip slots that were already restored.
        let mut in_prev = false
        for p in prev_contributions {
          if p == slot_id {
            in_prev = true
            break
          }
        }
        if in_prev {
          continue
        }
        let slot = self.accumulator_slots[slot_id.id]
        if !slot.disposed {
          (slot.clear_new_run_buffer)(cell_id)
        }
      }
      // Pop frame (discards staged deps + accumulator_reads).
      let _ = self.pop_tracking_full()
      cell.in_progress = false
      raise e
    }
  }

  // Normal path — pop the full frame to access accumulator state.
  let query = self.pop_tracking_full()
  let new_deps = query.dependencies
  let new_seen = query.seen
  let touched = query.touched_accumulator_slots
  let staged_reads = query.accumulator_reads

  // AFTER_CLOSURE: finalize each slot in prev ∪ touched (atomic diff +
  // bump + cleanup per slot), and rebuild accumulator_contributions from
  // slots that still have a buffer.
  let all_slots : @hashset.HashSet[@incr_types.AccumulatorId] = @hashset.new()
  for s in prev_contributions {
    all_slots.add(s)
  }
  for s in touched {
    all_slots.add(s)
  }
  let current_revision = self.core.revision.current_revision
  let new_contributions : @hashset.HashSet[@incr_types.AccumulatorId] = @hashset.new()
  for slot_id in all_slots {
    let slot = self.accumulator_slots[slot_id.id]
    if slot.disposed {
      continue
    }
    (slot.finalize_memo)(cell_id, current_revision)
    if (slot.has_buffer_for)(cell_id) {
      new_contributions.add(slot_id)
    }
  }

  // Commit staged_reads into MemoData.accumulator_reads (overwrite any
  // prior-run entries; a successful recompute is authoritative).
  cell.accumulator_reads.clear()
  for k, v in staged_reads {
    cell.accumulator_reads.set(k, v)
  }
  // Commit rebuilt contributions.
  if new_contributions.is_empty() {
    self.accumulator_contributions.remove(cell_id)
  } else {
    self.accumulator_contributions.set(cell_id, new_contributions)
  }

  // Existing epilogue — subscribers, durability, backdate, verified_at.
  let deps_changed = self.diff_and_update_subscribers(
    cell_id,
    old_deps,
    new_deps,
    new_seen~,
  )
  cell.dependencies = new_deps
  if deps_changed {
    cell.meta.durability = compute_durability(self, new_deps)
  }
  let value_changed = match old_value {
    None => true
    Some(old) => !eq_fn(old, new_value)
  }
  if value_changed {
    cell.meta.changed_at = self.core.revision.current_revision
  }
  cell.verified_at = self.core.revision.current_revision
  cell.has_been_computed = true
  cell.in_progress = false
  Ok(new_value)
}

///|
/// Returns the unique identifier for this memo.
///
/// The CellId can be used with `Runtime::cell_info()` to retrieve
/// metadata, or to compare cell identities.
///
/// # Returns
///
/// The cell identifier for this memo
pub fn[T] Memo::id(self : Memo[T]) -> CellId {
  self.cell_id
}

///|
/// Returns the list of cell IDs this memo currently depends on.
///
/// The dependency list is empty before the first computation and
/// updates each time the memo recomputes (for dynamic dependencies).
///
/// # Returns
///
/// A copy of the current dependency list. Returns empty array if
/// the memo has never been computed.
///
/// # Example
///
/// ```moonbit nocheck
/// let x = Signal(rt, 1)
/// let m = Memo(rt, () => x.get() * 2)
/// rt.read(m) |> ignore
/// inspect(m.dependencies().contains(x.id()), content="true")
/// ```
pub fn[T] Memo::dependencies(self : Memo[T]) -> Array[CellId] {
  self.rt.get_memo_data(self.cell_id).dependencies.copy()
}

///|
/// Returns the revision when this memo's value last changed.
///
/// This reflects backdating: if a recomputation produces the same
/// value, `changed_at` is preserved from the previous computation.
///
/// # Returns
///
/// The revision timestamp of the last actual value change
pub fn[T] Memo::changed_at(self : Memo[T]) -> Revision {
  self.rt.get_memo_data(self.cell_id).meta.changed_at
}

///|
/// Returns the revision when this memo was last verified up-to-date.
///
/// A memo is stale when `verified_at < current_revision`. Use this
/// to understand when a memo was last checked.
///
/// # Returns
///
/// The revision timestamp of the last verification
pub fn[T] Memo::verified_at(self : Memo[T]) -> Revision {
  self.rt.get_memo_data(self.cell_id).verified_at
}

///|
/// Registers a callback that fires whenever this memo's value changes.
///
/// The callback fires lazily — only during `get()` when recomputation
/// produces a new value that differs from the previous value. It does not
/// fire on the first computation (which establishes the initial value),
/// and does not fire if the memo backdates (recomputes to the same value).
/// Only one callback can be registered at a time; calling this again
/// replaces the previous callback.
///
/// # Parameters
///
/// - `f`: Called with the new value whenever this memo's value changes
pub fn[T] Memo::on_change(self : Memo[T], f : (T) -> Unit) -> Unit {
  self.rt.get_memo_data(self.cell_id).on_change = Some(() => {
    match self.value {
      Some(v) => f(v)
      None => ()
    }
  })
}

///|
/// Removes the `on_change` callback for this memo.
pub fn[T] Memo::clear_on_change(self : Memo[T]) -> Unit {
  self.rt.get_memo_data(self.cell_id).on_change = None
}

///|
/// Returns true if this memo has been disposed.
pub fn[T] Memo::is_disposed(self : Memo[T]) -> Bool {
  self.rt.is_cell_disposed(self.cell_id)
}

///|
/// Disposes this memo, releasing its resources and marking it as Disposed.
///
/// After disposal, calling `get()` will abort. Disposal is idempotent.
pub fn[T] Memo::dispose(self : Memo[T]) -> Unit {
  self.rt.dispose_cell(self.cell_id)
  self.value = None
}

///|
/// Returns true if the memo has a cached value and its verified_at matches
/// the runtime's current revision. Returns false if the memo has never been
/// computed (value is None), even at the initial revision.
pub fn[T] Memo::is_up_to_date(self : Memo[T]) -> Bool {
  match self.value {
    None => false
    Some(_) =>
      self.rt.get_memo_data(self.cell_id).verified_at ==
      self.rt.core.revision.current_revision
  }
}
