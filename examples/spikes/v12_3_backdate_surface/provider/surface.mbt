///|
/// PROTOTYPE: placeholder effect only; V12.10 owns the real ReadError shape.
pub suberror ProbeReadError {
  Unused
}

///|
/// PROTOTYPE: callable target read authority.
pub type View[T] = () -> T raise ProbeReadError

///|
/// PROTOTYPE: current-engine-backed creation shell.
pub struct Store {
  priv runtime : @incr.Runtime
}

///|
pub fn Store::Store() -> Store {
  { runtime: @incr.Runtime() }
}

///|
fn[T] evaluate_probe_compute(compute : () -> T raise ProbeReadError) -> T {
  compute() catch {
    _ => abort("unexpected prototype compute failure")
  }
}

///|
fn[T] probe_view(cell : @incr.Derived[T]) -> View[T] {
  () => cell.read_or_abort()
}

///|
/// Common path: structural equality suppresses downstream propagation.
pub fn[T : Eq] Store::derived(
  self : Store,
  compute : () -> T raise ProbeReadError,
  label? : String,
) -> View[T] {
  let cell = @incr.Derived(
    self.runtime,
    () => evaluate_probe_compute(compute),
    label?,
  )
  probe_view(cell)
}

///|
/// Advanced path: the output type owns its custom backdating identity.
pub fn[T : @incr.BackdateEq] Store::derived_with_backdate(
  self : Store,
  compute : () -> T raise ProbeReadError,
  label? : String,
) -> View[T] {
  let cell = @incr.Derived::with_backdate(
    self.runtime,
    () => evaluate_probe_compute(compute),
    label?,
  )
  probe_view(cell)
}

///|
/// Escape hatch: every successful recomputation is treated as changed.
pub fn[T] Store::derived_no_backdate(
  self : Store,
  compute : () -> T raise ProbeReadError,
  label? : String,
) -> View[T] {
  let cell = @incr.Derived::derived_no_backdate(
    self.runtime,
    () => evaluate_probe_compute(compute),
    label?,
  )
  probe_view(cell)
}
