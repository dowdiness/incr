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
/// let rt = Runtime::new()
/// let count = Signal::new(rt, 0)
/// count.set(5)
/// inspect(count.get(), content="5")
/// ```
pub(all) struct Signal[T] {
  priv rt : Runtime
  priv cell_id : CellId
  priv mut value : T
  priv mut pending_value : T?
  priv durability : Durability
}

///|
/// Creates a new signal with the given initial value and `Low` durability.
///
/// This is the most common way to create signals. Use `new_with_durability`
/// if you need to specify a different durability level for optimization.
///
/// # Parameters
///
/// - `rt`: The runtime that will manage this signal
/// - `initial`: The initial value of the signal
///
/// # Returns
///
/// A new signal containing the initial value
pub fn[T] Signal::new(rt : Runtime, initial : T) -> Signal[T] {
  Signal::new_with_durability(rt, initial, Low)
}

///|
/// Creates a new signal with the given initial value and explicit durability.
///
/// Use this when you know how often the signal will change:
/// - `High` durability for rarely-changing values (e.g., configuration)
/// - `Medium` durability for moderately stable values
/// - `Low` durability for frequently-changing values (e.g., user input)
///
/// Higher durability enables optimization: memos that only depend on
/// high-durability signals skip verification when low-durability signals change.
///
/// # Parameters
///
/// - `rt`: The runtime that will manage this signal
/// - `initial`: The initial value of the signal
/// - `durability`: How often this signal is expected to change
///
/// # Returns
///
/// A new signal containing the initial value
pub fn[T] Signal::new_with_durability(
  rt : Runtime,
  initial : T,
  durability : Durability,
) -> Signal[T] {
  let cell_id = rt.alloc_cell_id()
  let meta = CellMeta::new_input(cell_id, durability)
  rt.register_cell(meta)
  { rt, cell_id, value: initial, pending_value: None, durability }
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
  self.rt.record_dependency(self.cell_id)
  Ok(self.value)
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
/// let sig = Signal::new(rt, 42)
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
/// let s = Signal::new(rt, 5)
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
    let meta = self.rt.get_cell(self.cell_id)
    meta.changed_at = self.rt.current_revision
    meta.verified_at = self.rt.current_revision
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
  self.pending_value = Some(new_value)
  // Register commit closure if not already registered
  let meta = self.rt.get_cell(self.cell_id)
  if meta.commit_pending is None {
    meta.commit_pending = Some(fn() { self.commit() })
    self.rt.record_batch_signal(self.cell_id)
  }
  self.rt.bump_revision(self.durability)
}

///|
/// Store a pending value during a batch (unconditional).
fn[T] Signal::set_batch_unconditional(self : Signal[T], new_value : T) -> Unit {
  self.pending_value = Some(new_value)
  let meta = self.rt.get_cell(self.cell_id)
  if meta.commit_pending is None {
    meta.commit_pending = Some(fn() { self.commit_unconditional() })
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
