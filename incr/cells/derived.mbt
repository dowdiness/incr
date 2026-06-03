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
/// let observer = sum.observe()
///
/// inspect(observer.get(), content="30")  // Computes and caches
///
/// a.set(15)
/// inspect(observer.get(), content="35")  // Recomputes because `a` changed
/// observer.dispose()
/// ```
pub(all) struct Memo[T] {
  priv label : String?
  priv rt : Runtime
  priv cell_id : CellId
  priv compute : () -> T raise Failure
  priv is_static : Bool
  priv backdate_eq : (T, T) -> Bool // captured at construction; replaces hardcoded a==b
  priv mut value : T?
} derive(Debug(ignore=[Runtime, Fn, CellId]))

///|
/// Constructor-syntax alias of `Memo::new`. Enables `Memo(rt, compute)` /
/// `Memo(rt, compute, label="...")` call sites.
pub fn[T : Eq] Memo::Memo(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
) -> Memo[T] {
  Memo::new(rt, compute, label?)
}

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
  let memo : Memo[T] = {
    label,
    rt,
    cell_id,
    compute,
    is_static: false,
    backdate_eq,
    value: None,
  }
  let new_data : MemoData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.HashSet([]),
      push_reachable_count: 0,
    },
    compute: () => memo.recompute_inner(),
    verified_at: Revision::initial(),
    dependencies: [],
    in_progress: false,
    on_change: None,
    is_hybrid: false,
    accumulator_reads: @hashmap.HashMap([]),
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
  rt.cell_lifecycle.push(lifecycle)
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
/// Outside a compute function, use the target facade `Derived::read()`,
/// `Derived::read_or_abort()`, or `Derived::watch()`.
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
/// Use `get_result()` for error-returning cycle handling, or the target facade
/// read/watch methods for outside-the-graph reads.
pub fn[T] Memo::get(self : Memo[T]) -> T {
  match self.get_strict_result() {
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
  self.read_result()
}

///|
/// Package-private strict honest read. Requires an active tracked context;
/// reports mechanism failures (cycle / disposed) as `ReadError`.
fn[T] Memo::get_strict_honest(self : Memo[T]) -> Result[T, ReadError] {
  guard self.rt.core.tracking.stack.length() > 0 else {
    abort(
      "Memo::get() called outside tracked context. Use Derived::read(), Derived::read_or_abort(), or Derived::watch() to read from outside the graph.",
    )
  }
  self.read_honest()
}

///|
/// Package-private honest permissive read — the single source of truth for the
/// read channel. A disposed read returns `Err(Disposed(_))` (not an abort); a
/// cycle returns `Err(Cycle(_))`. A compute `raise Failure` is a *defect* and
/// still aborts. Reports `Disposed` only for *this* cell; a disposed transitive
/// dependency surfaced during verification still aborts inside `pull_verify`.
/// Records a dependency when tracked (only on a successful read).
fn[T] Memo::read_honest(self : Memo[T]) -> Result[T, ReadError] {
  self.read_honest_impl(record_dependency=true)
}

///|
fn[T] Memo::read_honest_impl(
  self : Memo[T],
  record_dependency~ : Bool,
) -> Result[T, ReadError] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    return Err(ReadError::disposed(self.cell_id))
  }
  self.rt.check_cross_runtime(self.rt.core.runtime_id, "Memo")
  let result = self.get_result_inner_impl(record_dependency~) catch {
    e => {
      self.rt.drain_pending_events_direct()
      abort("Memo compute raised: " + e.to_string())
    }
  }
  if self.rt.has_pending_events() {
    self.rt.drain_pending_events_if_idle()
  }
  match result {
    Ok(v) => Ok(v)
    Err(e) => Err(ReadError::cycle(e))
  }
}

///|
/// Package-private strict Result read. Requires an active tracked context.
/// Compatibility projection of `get_strict_honest` onto `CycleError`.
fn[T] Memo::get_strict_result(self : Memo[T]) -> Result[T, CycleError] {
  guard self.rt.core.tracking.stack.length() > 0 else {
    abort(
      "Memo::get() called outside tracked context. Use Derived::read(), Derived::read_or_abort(), or Derived::watch() to read from outside the graph.",
    )
  }
  self.read_result()
}

///|
/// Package-private permissive Result read. Records a dependency when tracked.
/// Compatibility projection of `read_honest` onto `CycleError`: a disposed read
/// aborts (preserving the legacy contract), a cycle is `Err(CycleError)`.
fn[T] Memo::read_result(self : Memo[T]) -> Result[T, CycleError] {
  match self.read_honest() {
    Ok(v) => Ok(v)
    Err(ReadError::Cycle(e)) => Err(e)
    Err(ReadError::Disposed(_)) => abort("Memo::get called on a disposed memo")
  }
}

///|
/// Internal: the core verification logic shared by Result and aborting reads.
/// Does NOT check tracking context.
fn[T] Memo::get_result_inner(
  self : Memo[T],
) -> Result[T, CycleError] raise Failure {
  self.get_result_inner_impl(record_dependency=true)
}

///|
fn[T] Memo::get_result_inner_impl(
  self : Memo[T],
  record_dependency~ : Bool,
) -> Result[T, CycleError] raise Failure {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Memo::get called on a disposed memo")
  }
  // If this runtime's tracking stack is empty, any active
  // `current_computing_runtime_id` is stale from a prior aborted
  // computation; repair it instead of treating it as a cross-runtime read.
  // This forgiving repair is required by panic-test call patterns that
  // bypass `get_result`'s outer strict check (e.g. `read_permissive`,
  // `MemoMap::get_or_create_memo`).
  if @kernel.get_current_computing_runtime_id() is Some(active_rt) {
    if self.rt.core.tracking.stack.is_empty() {
      @kernel.set_current_computing_runtime_id(None)
    } else if active_rt != self.rt.core.runtime_id {
      @kernel.set_current_computing_runtime_id(None)
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
          if record_dependency {
            self.rt.record_dependency(self.cell_id)
          }
          Ok(value)
        }
        Err(e) => Err(e)
      }
    Some(cached) => {
      // Fast path: already verified this revision
      let cell = self.rt.get_memo_data(self.cell_id)
      if cell.verified_at >= self.rt.core.revision.current_revision {
        if record_dependency {
          self.rt.record_dependency(self.cell_id)
        }
        return Ok(cached)
      }
      // Check if any dependency changed since last verification.
      // Note: pull_verify may recompute this cell internally
      // (via compute closure) to determine if value actually changed.
      match self.rt.pull_verify(self.cell_id) {
        Ok(_) => {
          if record_dependency {
            self.rt.record_dependency(self.cell_id)
          }
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
/// Package-private permissive read. Bypasses the tracked-context guard.
/// Records a dependency when a tracking frame is active.
#alias(get_untracked, deprecated="Use Memo::read_permissive instead")
fn[T] Memo::read_permissive(self : Memo[T]) -> T {
  let r = self.get_result_inner() catch {
    e => {
      self.rt.drain_pending_events_direct()
      abort("Memo compute raised: " + e.to_string())
    }
  }
  let value = match r {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
  value
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
/// Force recomputation: delegates to the dynamic or static memo recompute helper.
///
/// Returns `Ok(new_value)` on success, or `Err(CycleError)` if a cycle is detected.
fn[T] Memo::force_recompute(
  self : Memo[T],
) -> Result[T, CycleError] raise Failure {
  let result = if self.is_static {
    self.rt.static_memo_force_recompute(
      self.cell_id,
      self.compute,
      self.value,
      self.backdate_eq,
    )
  } else {
    self.rt.memo_force_recompute(
      self.cell_id,
      self.compute,
      self.value,
      self.backdate_eq,
    )
  }
  match result {
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
          Some(f) => @kernel.run_callback(self.rt.core, f)
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
      @kernel.construct_cycle_error(
        self.core,
        @kernel.collect_tracking_path(self.core),
        cell.meta.cell_id,
      ),
    )
  }
  cell.in_progress = true
  // MemoCommitPhase: before_recompute — fires before tracking is pushed.
  self.dispatch_before_recompute_hooks(cell_id)
  let old_deps = cell.dependencies
  @kernel.push_tracking(self.core, cell_id)
  let new_value = compute_fn() catch {
    e => {
      // MemoCommitPhase: after_abort — fires in catch arm, before pop.
      self.dispatch_after_abort_hooks(cell_id, e)
      // Pop frame (discards staged deps).
      let _ = @kernel.pop_tracking_full(self.core)
      cell.in_progress = false
      raise e
    }
  }

  // Normal path — pop the full frame to get dep + seen sets for the epilogue.
  let query = @kernel.pop_tracking_full(self.core)
  let new_deps = query.dependencies
  let new_seen = query.seen

  // Existing epilogue — subscribers, durability, backdate, verified_at.
  let deps_changed = @kernel.diff_and_update_subscribers(
    self.core,
    self.pull,
    self.push,
    self.datalog,
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
  // MemoCommitPhase: after_success — fires AFTER the cell-level epilogue
  // so changed_at / verified_at / has_been_computed are observable
  // (backdating detectable via cell.meta.changed_at < cell.verified_at).
  self.dispatch_after_success_hooks(cell_id)
  Ok(new_value)
}

///|
fn[T] Runtime::static_memo_force_recompute(
  self : Runtime,
  cell_id : CellId,
  compute_fn : () -> T raise Failure,
  old_value : T?,
  eq_fn : (T, T) -> Bool,
) -> Result[T, CycleError] raise Failure {
  let cell = self.get_memo_data(cell_id)
  if cell.in_progress {
    return Err(
      @kernel.construct_cycle_error(
        self.core,
        @kernel.collect_in_progress_path(self.pull),
        cell.meta.cell_id,
      ),
    )
  }
  cell.in_progress = true
  self.dispatch_before_recompute_hooks(cell_id)
  self.enter_static_recompute()
  let new_value = compute_fn() catch {
    e => {
      self.leave_static_recompute()
      self.dispatch_after_abort_hooks(cell_id, e)
      cell.in_progress = false
      raise e
    }
  }
  self.leave_static_recompute()
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
  self.dispatch_after_success_hooks(cell_id)
  Ok(new_value)
}

///|
fn[T] Memo::read_declared_fixed_dep_or_abort(
  self : Memo[T],
  dependent : CellId,
) -> T raise Failure {
  guard self.rt.validate_cell_soft(dependent) else {
    fail("static Derived fixed-source read from a different runtime")
  }
  let dependent_data = self.rt.get_memo_data(dependent)
  guard dependent_data.in_progress else {
    fail("static Derived fixed-source read outside dependent recompute")
  }
  guard dependent_data.dependencies.contains(self.cell_id) else {
    fail("static Derived fixed-source read without a declared dependency")
  }
  match self.read_honest_impl(record_dependency=false) {
    Ok(value) => {
      @kernel.set_current_computing_runtime_id(Some(self.rt.core.runtime_id))
      value
    }
    Err(e) => abort(e.format_path())
  }
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
/// let observer = m.observe()
/// observer.get() |> ignore
/// observer.dispose()
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
