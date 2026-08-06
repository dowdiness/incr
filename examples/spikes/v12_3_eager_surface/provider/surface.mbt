///|
/// PROTOTYPE: placeholder effect only; V12.10 owns the real ReadError shape.
pub suberror ProbeReadError {
  Unused
}

///|
/// PROTOTYPE: passive callable read authority.
pub type View[T] = () -> T raise ProbeReadError

///|
/// PROTOTYPE: nominal write authority for source-driving scenarios.
pub struct Write[T] {
  priv input : @incr.Input[T]
}

///|
pub fn[T : Eq] Write::set(self : Write[T], value : T) -> Unit {
  self.input.set(value)
}

///|
pub fn[T] Write::force_set(self : Write[T], value : T) -> Unit {
  self.input.force_set(value)
}

///|
/// PROTOTYPE: idempotent breaker for one eager mount.
pub struct Stop {
  priv mount : @incr.EagerDerived[Unit]
}

///|
pub fn Stop::stop(self : Stop) -> Unit {
  if !self.mount.is_disposed() {
    self.mount.dispose()
  }
}

///|
pub fn Stop::is_stopped(self : Stop) -> Bool {
  self.mount.is_disposed()
}

///|
/// PROTOTYPE: owner of active eager mounts.
pub struct Store {
  priv runtime : @incr.Runtime
  priv mounts : Array[@incr.EagerDerived[Unit]]
  priv closed : Ref[Bool]
}

///|
pub fn Store::Store() -> Store {
  { runtime: @incr.Runtime(), mounts: [], closed: Ref(false) }
}

///|
pub fn[T] Store::input(self : Store, initial : T) -> (View[T], Write[T]) {
  let input = @incr.Input(self.runtime, initial)
  let view : View[T] = () => input.get()
  (view, { input, })
}

///|
pub fn Store::batch(self : Store, writes : () -> Unit raise?) -> Unit raise? {
  self.runtime.batch(writes)
}

///|
/// Mounts an existing passive View for immediate and proactive evaluation.
pub fn[T] Store::eager(
  self : Store,
  view : View[T],
  label? : String,
) -> Stop raise ProbeReadError {
  guard !self.closed.val else { abort("prototype Store is closed") }
  ignore(label)
  let mount = @incr.EagerDerived(self.runtime, () => {
    ignore(
      view() catch {
        _ => abort("unexpected prototype eager read failure")
      },
    )
  })
  self.mounts.push(mount)
  { mount, }
}

///|
/// Stops every active mount owned by this Store.
pub fn Store::close(self : Store) -> Unit {
  if self.closed.val {
    return
  }
  self.closed.val = true
  self.mounts.each(mount => if !mount.is_disposed() { mount.dispose() })
}
