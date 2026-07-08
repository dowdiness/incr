///|
/// An input cell with an externally-set value.
///
/// Inputs are the leaves of the dependency graph — values you control directly.
/// The `T: Eq` constraint enables same-value optimization: setting an input to
/// its current value is a no-op (no revision bump, no downstream recomputation).
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime()
/// let count = Input(rt, 0)
/// count.set(5)
/// inspect(count.get(), content="5")
/// ```
pub(all) struct Input[T] {
  priv label : String?
  priv rt : Runtime
  priv cell_id : CellId
  priv mut value : T
  priv mut pending_value : T?
  priv durability : Durability
} derive(Debug(ignore=[Runtime, CellId]))

///|
/// Creates a new input with the given initial value. Enables `Input(rt, value)`
/// / `Input(rt, value, label="...", durability=High)` call sites.
///
/// # Parameters
///
/// - `rt`: The runtime that will manage this input
/// - `initial`: The initial value of the input
/// - `durability`: How often this input is expected to change (default: `Low`)
/// - `label`: An optional human-readable name for debugging and cycle error output
///
/// # Returns
///
/// A new input containing the initial value
///
/// # Example
///
/// ```moonbit nocheck
/// let count = Input(rt, 0)
///
/// let config = Input(rt, "prod", durability=High)
///
/// let named = Input(rt, 0, label="count")
/// ```
pub fn[T] Input::Input(
  rt : Runtime,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> Input[T] {
  let (cell_id, _) = rt.install_cell(
    rt.pull.free_inputs,
    rt.pull.inputs,
    idx => PullInput(idx),
    cell_id => {
      meta: {
        cell_id,
        label,
        changed_at: Revision::initial(),
        durability,
        subscribers: @hashset.HashSet([]),
        push_reachable_count: 0,
      },
      on_change: None,
      commit_pending: None,
    },
  )
  { label, rt, cell_id, value: initial, pending_value: None, durability }
}

///|
/// Deprecated alias of the `Input::Input` constructor.
#deprecated("Use the constructor form `Input(rt, initial)` (`Input::Input`) instead.")
pub fn[T] Input::new(
  rt : Runtime,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> Input[T] {
  Input(rt, initial, durability~, label?)
}

///|
/// Returns the current value of the input.
///
/// If called inside a derived's compute function, this automatically records
/// a dependency from the derived to this input. When the input changes,
/// the derived will know to reverify.
///
/// # Returns
///
/// The current value of the input
pub fn[T] Input::get(self : Input[T]) -> T {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Input::get called on a disposed input")
  }
  self.rt.check_cross_runtime(self.rt.core.runtime_id, "Input")
  self.rt.record_dependency(self.cell_id)
  let value = self.value
  if self.rt.has_pending_events() {
    self.rt.drain_pending_events_if_idle()
  }
  value
}

///|
/// Returns the current value of the input without recording a dependency.
///
/// Use `peek()` to read an input's value from outside the dependency graph
/// (e.g., in event handlers, logging, or tests). Unlike `get()`, this never
/// records a dependency even when called inside a compute function.
///
/// # Returns
///
/// The current value of the input
pub fn[T] Input::peek(self : Input[T]) -> T {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Input::peek called on a disposed input")
  }
  self.value
}

///|
/// Returns the current value of the input as a Result.
///
/// Unlike `get()` which aborts on disposal, this method returns
/// `Err(Disposed(cell_id))` when the input has been disposed. Cycle errors
/// cannot occur for inputs (they have no dependencies), so the `Cycle` variant
/// of `ReadError` is structurally unreachable — but accepting it through the
/// shared `ReadError` type keeps the channel uniform across all cell types.
///
/// # Returns
///
/// `Ok(value)` with the current value of the input, or
/// `Err(ReadError::Disposed(id))` if the input has been disposed
pub fn[T] Input::get_result(self : Input[T]) -> Result[T, ReadError] {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    return Err(ReadError::disposed(self.cell_id))
  }
  self.rt.check_cross_runtime(self.rt.core.runtime_id, "Input")
  self.rt.record_dependency(self.cell_id)
  let value = self.value
  if self.rt.has_pending_events() {
    self.rt.drain_pending_events_if_idle()
  }
  Ok(value)
}

///|
/// Returns the unique identifier for this input.
///
/// The CellId can be used with `Runtime::cell_info()` to retrieve
/// metadata, or to compare cell identities.
///
/// # Returns
///
/// The cell identifier for this input
///
/// # Example
///
/// ```moonbit nocheck
/// let inp = Input(rt, 42)
/// let id = inp.id()
/// match rt.cell_info(id) {
///   Some(info) => println("Input changed at: " + info.changed_at.to_string())
///   None => ()
/// }
/// ```
pub fn[T] Input::id(self : Input[T]) -> CellId {
  self.cell_id
}

///|
/// Returns the durability level of this input.
///
/// Durability indicates how often this input is expected to change:
/// - `High`: Rarely changes (e.g., configuration)
/// - `Medium`: Moderately stable
/// - `Low`: Frequently changes (e.g., user input)
///
/// # Returns
///
/// The durability level set at construction time
pub fn[T] Input::durability(self : Input[T]) -> Durability {
  self.durability
}

///|
/// Sets the input to a new value.
///
/// If the new value equals the current value (via `Eq`), this is a no-op:
/// no revision bump occurs, and downstream deriveds won't reverify.
///
/// During a batch (`Runtime::batch`), the write is deferred. At batch end,
/// only inputs whose final value differs from the pre-batch value trigger
/// a revision bump. This enables revert detection.
///
/// # Parameters
///
/// - `new_value`: The new value to set
///
/// # Same-Value Optimization
///
/// ```moonbit nocheck
/// let s = Input(rt, 5)
/// s.set(5)  // No-op: value unchanged, no revision bump
/// s.set(6)  // Bumps revision, deriveds depending on s will reverify
/// ```
pub fn[T : Eq] Input::set(self : Input[T], new_value : T) -> Unit {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Input::set called on a disposed input")
  }
  if self.rt.core.batch.depth > 0 {
    self.set_batch(new_value)
  } else {
    if self.value == new_value {
      if self.rt.has_pending_events() {
        self.rt.drain_pending_events_if_idle()
      }
      return
    }
    self.force_set(new_value)
  }
}

///|
/// Sets the input to a new value, always bumping the revision.
///
/// Unlike `set`, this does not check for equality. Use this when you want
/// to force downstream deriveds to reverify even if the value is the same,
/// or when your type doesn't implement `Eq`.
///
/// During a batch, the value is stored as pending and committed at batch end.
///
/// # Parameters
///
/// - `new_value`: The new value to set
pub fn[T] Input::force_set(self : Input[T], new_value : T) -> Unit {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("Input::force_set called on a disposed input")
  }
  // Guard against reentrant propagation: force_set calls propagate_changes,
  // which must not be called while a reactive compute is in progress (tracking
  // stack non-empty). This catches both pull-mode derived computes and push-mode
  // eager-derived computes. on_change callbacks run after propagation returns,
  // so the stack is empty there — this guard correctly allows them.
  let label_str = match self.label {
    Some(s) => "\"" + s + "\""
    None => "<unlabeled>"
  }
  guard self.rt.core.tracking.stack.length() == 0 else {
    // Clear the cross-runtime sentinel before aborting so subsequent
    // tests don't see a stale active-computation id from this runtime.
    @kernel.set_current_computing_runtime_id(None)
    self.rt.core.tracking.stack.clear()
    abort(
      "Input::force_set(" +
      label_str +
      ") called inside a reactive " +
      "compute context. Input writes must happen outside the reactive " +
      "graph \u{2014} use a `mut` local variable instead.",
    )
  }
  // Cross-engine contexts (fixpoint rule bodies, GC) hold no tracking frame,
  // so the stack guard above cannot see them, and the enter_phase guard in
  // push propagation only fires post-mutation — never at all in a push-free
  // graph. Any non-Idle phase means a propagation is in flight; abort before
  // mutating (#375). Legal batch writes always run at Idle (commit_batch
  // raises batch.depth around callbacks only after propagation returns).
  guard self.rt.core.phase is Idle else {
    abort(
      "Input::force_set(" +
      label_str +
      ") called during the " +
      self.rt.core.phase.to_string() +
      " phase. Input writes must happen while the runtime is idle \u{2014} " +
      "move the write outside the propagation (e.g. after fixpoint()/gc() " +
      "returns).",
    )
  }
  if self.rt.core.batch.depth > 0 {
    self.set_batch_force(new_value)
  } else {
    self.value = new_value
    // Snapshot callback before propagation — same invariant as commit_batch:
    // push propagation must not affect which handler fires.
    let cb = self.rt.get_pull_input(self.cell_id).on_change
    self.rt.propagate_changes([self.cell_id], self.durability)
    match cb {
      Some(f) => @kernel.run_callback(self.rt.core, f)
      None => ()
    }
    self.rt.fire_on_change()
    if self.rt.has_pending_events() {
      self.rt.drain_pending_events_if_idle()
    }
  }
}

///|
/// Store a pending value during a batch (with Eq check).
fn[T : Eq] Input::set_batch(self : Input[T], new_value : T) -> Unit {
  // Compare against current pending value (if any) or actual value
  let current = match self.pending_value {
    Some(pv) => pv
    None => self.value
  }
  if current == new_value {
    return
  }
  let previous_pending = self.pending_value
  let sig_data = self.rt.get_pull_input(self.cell_id)
  let was_registered = match sig_data.commit_pending {
    Some(_) => true
    None => false
  }
  self.rt.record_batch_rollback(self.cell_id, () => {
    self.pending_value = previous_pending
    if !was_registered {
      sig_data.commit_pending = None
      self.rt.remove_batch_input(self.cell_id)
    }
  })
  self.pending_value = Some(new_value)
  // Register commit closure if not already registered
  if sig_data.commit_pending is None {
    sig_data.commit_pending = Some(() => self.commit())
    let sig_committable : &Committable = sig_data
    self.rt.record_batch_input(sig_committable)
  }
  self.rt.bump_revision(self.durability)
}

///|
/// Store a pending value during a batch (unconditional).
fn[T] Input::set_batch_force(self : Input[T], new_value : T) -> Unit {
  let previous_pending = self.pending_value
  let sig_data = self.rt.get_pull_input(self.cell_id)
  let was_registered = match sig_data.commit_pending {
    Some(_) => true
    None => false
  }
  self.rt.record_batch_rollback(self.cell_id, () => {
    self.pending_value = previous_pending
    if !was_registered {
      sig_data.commit_pending = None
      self.rt.remove_batch_input(self.cell_id)
    }
  })
  self.pending_value = Some(new_value)
  if sig_data.commit_pending is None {
    sig_data.commit_pending = Some(() => self.commit_force())
    let sig_committable : &Committable = sig_data
    self.rt.record_batch_input(sig_committable)
  }
  self.rt.bump_revision(self.durability)
}

///|
/// Commit the pending value. Returns true if the value actually changed.
fn[T : Eq] Input::commit(self : Input[T]) -> Bool {
  match self.pending_value {
    None => false
    Some(pv) => {
      let changed = self.value != pv
      if changed {
        self.value = pv
      }
      self.pending_value = None
      changed
    }
  }
}

///|
/// Commit the pending value unconditionally. Always returns true if there
/// is a pending value (no equality check).
fn[T] Input::commit_force(self : Input[T]) -> Bool {
  match self.pending_value {
    None => false
    Some(pv) => {
      self.value = pv
      self.pending_value = None
      true
    }
  }
}

///|
/// Registers a callback that fires whenever this input's value changes.
///
/// The callback receives the new value. It fires after the value is updated
/// but before `Runtime::fire_on_change()`. Only one callback can be
/// registered at a time; calling this again replaces the previous callback.
///
/// Note: When using `force_set`, the callback fires even if the
/// new value equals the current value, since `force_set` bypasses
/// the equality check.
///
/// # Parameters
///
/// - `f`: Called with the new value whenever this input changes
pub fn[T] Input::on_change(self : Input[T], f : (T) -> Unit) -> Unit {
  self.rt.get_pull_input(self.cell_id).on_change = Some(() => f(self.value))
}

///|
/// Removes the `on_change` callback for this input.
pub fn[T] Input::clear_on_change(self : Input[T]) -> Unit {
  self.rt.get_pull_input(self.cell_id).on_change = None
}

///|
/// Disposes this input, releasing its resources and marking it as Disposed.
///
/// After disposal, calling `get()` or `set()` will abort. Disposal is
/// idempotent — calling it multiple times is a no-op.
pub fn[T] Input::dispose(self : Input[T]) -> Unit {
  self.rt.dispose_cell(self.cell_id)
}

///|
/// Returns true if this input has been disposed.
pub fn[T] Input::is_disposed(self : Input[T]) -> Bool {
  self.rt.is_cell_disposed(self.cell_id)
}

///|
/// Returns true. Inputs are always up-to-date since they are input cells
/// with directly-set values.
pub fn[T] Input::is_up_to_date(self : Input[T]) -> Bool {
  ignore(self)
  true
}

///|
/// Returns true. Inputs are directly-set cells and are always fresh.
pub fn[T] Input::is_fresh(self : Input[T]) -> Bool {
  self.is_up_to_date()
}

///|
/// Creates a new `Derived[V]` by combining this input with another input.
/// Uses equality-based backdating. Aborts if inputs belong to different runtimes.
pub fn[T, U, V : Eq] Input::derived2(
  self : Input[T],
  other : Input[U],
  f : (T, U) -> V,
  label? : String,
) -> Derived[V] {
  guard self.cell_id.runtime_id == other.cell_id.runtime_id else {
    abort("Input::derived2: inputs belong to different runtimes")
  }
  Derived(self.rt, () => f(self.get(), other.get()), label?)
}

///|
/// Creates a new `Derived[V]` by combining this input with another input,
/// without equality-based backdating. Accepts output types that do not implement `Eq`.
pub fn[T, U, V] Input::derived2_no_backdate(
  self : Input[T],
  other : Input[U],
  f : (T, U) -> V,
  label? : String,
) -> Derived[V] {
  guard self.cell_id.runtime_id == other.cell_id.runtime_id else {
    abort("Input::derived2_no_backdate: inputs belong to different runtimes")
  }
  Derived::_create(self.rt, () => f(self.get(), other.get()), label?, (_, _) => {
    false
  })
}

///|
/// Creates a new `Derived[W]` by combining this input with two other inputs.
/// Uses equality-based backdating. Aborts if inputs belong to different runtimes.
pub fn[T, U, V, W : Eq] Input::derived3(
  self : Input[T],
  second : Input[U],
  third : Input[V],
  f : (T, U, V) -> W,
  label? : String,
) -> Derived[W] {
  guard self.cell_id.runtime_id == second.cell_id.runtime_id else {
    abort("Input::derived3: inputs belong to different runtimes")
  }
  guard self.cell_id.runtime_id == third.cell_id.runtime_id else {
    abort("Input::derived3: inputs belong to different runtimes")
  }
  Derived(self.rt, () => f(self.get(), second.get(), third.get()), label?)
}

///|
/// Creates a new `Derived[W]` by combining this input with two other inputs,
/// without equality-based backdating. Accepts output types that do not implement `Eq`.
pub fn[T, U, V, W] Input::derived3_no_backdate(
  self : Input[T],
  second : Input[U],
  third : Input[V],
  f : (T, U, V) -> W,
  label? : String,
) -> Derived[W] {
  guard self.cell_id.runtime_id == second.cell_id.runtime_id else {
    abort("Input::derived3_no_backdate: inputs belong to different runtimes")
  }
  guard self.cell_id.runtime_id == third.cell_id.runtime_id else {
    abort("Input::derived3_no_backdate: inputs belong to different runtimes")
  }
  Derived::_create(
    self.rt,
    () => f(self.get(), second.get(), third.get()),
    label?,
    (_, _) => false,
  )
}

///|
/// Creates a new `Derived[U]` from this input by applying `f` to the current
/// value on each read. Uses equality-based backdating: when recomputation
/// produces a value equal to the previous output, downstream dependents skip
/// recomputation.
///
/// Equivalent to `scope.derived(() => f(input.get()))` but without the scope
/// parameter — the input already holds a runtime reference.
pub fn[T, U : Eq] Input::derived(
  self : Input[T],
  f : (T) -> U,
  label? : String,
) -> Derived[U] {
  Derived(self.rt, () => f(self.get()), label?)
}

///|
/// Creates a new `Derived[U]` from this input by applying `f` to the current
/// value on each read, without equality-based backdating. Each recomputation
/// advances the changed-at revision unconditionally, even when the output
/// equals the previous value. Accepts output types that do not implement `Eq`.
///
/// Equivalent to `scope.derived_no_backdate(() => f(input.get()))` but without
/// the scope parameter — the input already holds a runtime reference.
pub fn[T, U] Input::derived_no_backdate(
  self : Input[T],
  f : (T) -> U,
  label? : String,
) -> Derived[U] {
  Derived::_create(self.rt, () => f(self.get()), label?, (_, _) => false)
}
