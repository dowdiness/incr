///|
/// PROTOTYPE: placeholder effect only; V12.10 owns the real ReadError shape.
pub suberror ProbeReadError {
  Unused
}

///|
/// PROTOTYPE: callable read authority for the V12.3 Write shape probe.
pub type View[T] = () -> T raise ProbeReadError

///|
/// PROTOTYPE: nominal write authority backed by the current Input API.
pub struct Write[T] {
  priv input : @incr.Input[T]
}

///|
/// Equality-suppressing write capability.
pub fn[T : Eq] Write::set(self : Write[T], value : T) -> Unit {
  self.input.set(value)
}

///|
/// Unconditional write capability, including for non-Eq values.
pub fn[T] Write::force_set(self : Write[T], value : T) -> Unit {
  self.input.force_set(value)
}

///|
/// PROTOTYPE: creation shell for paired read and write capabilities.
pub struct Store {
  priv runtime : @incr.Runtime
}

///|
pub fn Store::Store() -> Store {
  { runtime: @incr.Runtime() }
}

///|
pub fn[T] Store::input(self : Store, initial : T) -> (View[T], Write[T]) {
  let input = @incr.Input(self.runtime, initial)
  let view : View[T] = () => input.get()
  let write : Write[T] = { input, }
  (view, write)
}
