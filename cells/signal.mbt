///|
/// An input cell with an externally-set value.
///
/// Signals are the leaves of the dependency graph — values you control directly.
/// The `T: Eq` constraint enables same-value optimization: setting a signal to
/// its current value is a no-op (no revision bump, no downstream recomputation).
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime()
/// let count = Signal(rt, 0)
/// count.set(5)
/// inspect(count.get(), content="5")
/// ```
pub(all) struct Signal[T] {
  priv label : String?
  priv rt : Runtime
  priv cell_id : CellId
  priv mut value : T
  priv mut pending_value : T?
  priv durability : Durability

  fn[T] new(
    rt : Runtime,
    initial : T,
    durability? : Durability,
    label? : String,
  ) -> Signal[T]
} derive(Debug(ignore=[Runtime, CellId]))

///|
/// Creates a new signal with the given initial value.
///
/// # Parameters
///
/// - `rt`: The runtime that will manage this signal
/// - `initial`: The initial value of the signal
/// - `durability`: How often this signal is expected to change (default: `Low`)
/// - `label`: An optional human-readable name for debugging and cycle error output
///
/// # Returns
///
/// A new signal containing the initial value
///
/// # Example
///
/// ```moonbit nocheck
/// let count = Signal(rt, 0)
///
/// let config = Signal(rt, "prod", durability=High)
///
/// let named = Signal(rt, 0, label="count")
/// ```
pub fn[T] Signal::new(
  rt : Runtime,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> Signal[T] {
  let cell_id = rt.alloc_cell_id()
  let meta = CellMeta::new_input(cell_id, durability, label)
  rt.register_cell(meta)
  { label, rt, cell_id, value: initial, pending_value: None, durability }
}

///|
/// Returns the current value of the signal.
///
/// If called inside a memo's compute function, this automatically records
/// a dependency from the memo to this signal. When the signal changes,
/// the memo will know to reverify.
///
/// # Returns
///
/// The current value of the signal
pub fn[T] Signal::get(self : Signal[T]) -> T {
  self.rt.record_dependency(self.cell_id)
  self.value
}

///|
/// Returns the current value of the signal as a Result.
///
/// This method exists for API consistency with `Memo::get_result()`.
/// Since signals cannot have cycles (they are input cells with no dependencies),
/// this method always returns `Ok(value)`.
///
/// # Returns
///
/// `Ok(value)` with the current value of the signal
pub fn[T] Signal::get_result(self : Signal[T]) -> Result[T, CycleError] {
  Ok(self.get())
}

///|
/// Returns the unique identifier for this signal.
///
/// The CellId can be used with `Runtime::cell_info()` to retrieve
/// metadata, or to compare cell identities.
///
/// # Returns
///
/// The cell identifier for this signal
///
/// # Example
///
/// ```moonbit nocheck
/// let sig = Signal(rt, 42)
/// let id = sig.id()
/// match rt.cell_info(id) {
///   Some(info) => println("Signal changed at: " + info.changed_at.to_string())
///   None => ()
/// }
/// ```
pub fn[T] Signal::id(self : Signal[T]) -> CellId {
  self.cell_id
}

///|
/// Returns the durability level of this signal.
///
/// Durability indicates how often this signal is expected to change:
/// - `High`: Rarely changes (e.g., configuration)
/// - `Medium`: Moderately stable
/// - `Low`: Frequently changes (e.g., user input)
///
/// # Returns
///
/// The durability level set at construction time
pub fn[T] Signal::durability(self : Signal[T]) -> Durability {
  self.durability
}

///|
/// Sets the signal to a new value.
///
/// If the new value equals the current value (via `Eq`), this is a no-op:
/// no revision bump occurs, and downstream memos won't reverify.
///
/// During a batch (`Runtime::batch`), the write is deferred. At batch end,
/// only signals whose final value differs from the pre-batch value trigger
/// a revision bump. This enables revert detection.
///
/// # Parameters
///
/// - `new_value`: The new value to set
///
/// # Same-Value Optimization
///
/// ```moonbit nocheck
/// let s = Signal(rt, 5)
/// s.set(5)  // No-op: value unchanged, no revision bump
/// s.set(6)  // Bumps revision, memos depending on s will reverify
/// ```
pub fn[T : Eq] Signal::set(self : Signal[T], new_value : T) -> Unit {
  if self.rt.batch_depth > 0 {
    self.set_batch(new_value)
  } else {
    if self.value == new_value {
      return
    }
    self.set_unconditional(new_value)
  }
}

///|
/// Sets the signal to a new value, always bumping the revision.
///
/// Unlike `set`, this does not check for equality. Use this when you want
/// to force downstream memos to reverify even if the value is the same,
/// or when your type doesn't implement `Eq`.
///
/// During a batch, the value is stored as pending and committed at batch end.
///
/// # Parameters
///
/// - `new_value`: The new value to set
pub fn[T] Signal::set_unconditional(self : Signal[T], new_value : T) -> Unit {
  if self.rt.batch_depth > 0 {
    self.set_batch_unconditional(new_value)
  } else {
    self.value = new_value
    self.rt.bump_revision(self.durability)
    let meta = self.rt.mark_input_changed(self.cell_id)
    match meta.on_change {
      Some(f) => f()
      None => ()
    }
    self.rt.fire_on_change()
  }
}

///|
/// Store a pending value during a batch (with Eq check).
fn[T : Eq] Signal::set_batch(self : Signal[T], new_value : T) -> Unit {
  // Compare against current pending value (if any) or actual value
  let current = match self.pending_value {
    Some(pv) => pv
    None => self.value
  }
  if current == new_value {
    return
  }
  let previous_pending = self.pending_value
  let meta = self.rt.get_cell(self.cell_id)
  let was_registered = match meta.commit_pending {
    Some(_) => true
    None => false
  }
  self.rt.record_batch_rollback(self.cell_id, () => {
    self.pending_value = previous_pending
    if not(was_registered) {
      meta.commit_pending = None
      meta.rollback_pending = None
      self.rt.remove_batch_signal(self.cell_id)
    }
  })
  self.pending_value = Some(new_value)
  // Register commit closure if not already registered
  if meta.commit_pending is None {
    meta.commit_pending = Some(() => self.commit())
    meta.rollback_pending = Some(() => self.rollback_pending())
    self.rt.record_batch_signal(self.cell_id)
  }
  self.rt.bump_revision(self.durability)
}

///|
/// Store a pending value during a batch (unconditional).
fn[T] Signal::set_batch_unconditional(self : Signal[T], new_value : T) -> Unit {
  let previous_pending = self.pending_value
  let meta = self.rt.get_cell(self.cell_id)
  let was_registered = match meta.commit_pending {
    Some(_) => true
    None => false
  }
  self.rt.record_batch_rollback(self.cell_id, () => {
    self.pending_value = previous_pending
    if not(was_registered) {
      meta.commit_pending = None
      meta.rollback_pending = None
      self.rt.remove_batch_signal(self.cell_id)
    }
  })
  self.pending_value = Some(new_value)
  if meta.commit_pending is None {
    meta.commit_pending = Some(() => self.commit_unconditional())
    meta.rollback_pending = Some(() => self.rollback_pending())
    self.rt.record_batch_signal(self.cell_id)
  }
  self.rt.bump_revision(self.durability)
}

///|
/// Commit the pending value. Returns true if the value actually changed.
fn[T : Eq] Signal::commit(self : Signal[T]) -> Bool {
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
fn[T] Signal::commit_unconditional(self : Signal[T]) -> Bool {
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
/// Drop any pending batch value without committing it.
fn[T] Signal::rollback_pending(self : Signal[T]) -> Unit {
  self.pending_value = None
}

///|
/// Registers a callback that fires whenever this signal's value changes.
///
/// The callback receives the new value. It fires after the value is updated
/// but before `Runtime::fire_on_change()`. Only one callback can be
/// registered at a time; calling this again replaces the previous callback.
///
/// Note: When using `set_unconditional`, the callback fires even if the
/// new value equals the current value, since `set_unconditional` bypasses
/// the equality check.
///
/// # Parameters
///
/// - `f`: Called with the new value whenever this signal changes
pub fn[T] Signal::on_change(self : Signal[T], f : (T) -> Unit) -> Unit {
  let cell = self.rt.get_cell(self.cell_id)
  cell.on_change = Some(() => f(self.value))
}

///|
/// Removes the `on_change` callback for this signal.
pub fn[T] Signal::clear_on_change(self : Signal[T]) -> Unit {
  let cell = self.rt.get_cell(self.cell_id)
  cell.on_change = None
}

///|
/// Returns true. Signals are always up-to-date since they are input cells
/// with directly-set values.
pub fn[T] Signal::is_up_to_date(self : Signal[T]) -> Bool {
  ignore(self)
  true
}
