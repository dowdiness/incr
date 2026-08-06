///|
/// PROTOTYPE: callable read authority using the current adapter's Failure
/// effect. V12.10 owns the target ReadError hierarchy.
pub type View[T] = () -> T raise Failure

///|
pub struct Store {
  priv runtime : @incr.Runtime
  priv scope : @incr.Scope
  priv mut closed : Bool
}

///|
pub struct Write[T] {
  priv input : @incr.Input[T]
}

///|
/// Push authority for one Store-owned side-channel family.
pub struct Accumulator[A] {
  priv owner : @incr.RuntimeId
  priv raw : @incr.Accumulator[A]
}

///|
/// Read authority for one producer's contribution to an Accumulator.
pub struct Contribution[A] {
  priv values : View[Array[A]]
  priv snapshot : () -> Array[A]
}

///|
pub fn Store::Store() -> Store {
  let runtime = @incr.Runtime()
  { runtime, scope: @incr.Scope::new(runtime), closed: false }
}

///|
pub fn[T] Store::input(
  self : Store,
  value : T,
  label? : String,
) -> (View[T], Write[T]) {
  guard !self.closed else { abort("Store::input called after close") }
  let input = self.scope.input(value, label?)
  let view : View[T] = () => input.get()
  (view, { input, })
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
fn[T] derived_view(derived : @incr.Derived[T]) -> View[T] {
  () => derived.read_or_abort()
}

///|
pub fn[T : Eq] Store::derived(
  self : Store,
  compute : () -> T raise Failure,
  label? : String,
) -> View[T] {
  guard !self.closed else { abort("Store::derived called after close") }
  let derived = self.scope.derived(compute, label?)
  derived_view(derived)
}

///|
pub fn[A : Eq] Store::accumulator(
  self : Store,
  label? : String,
) -> Accumulator[A] {
  guard !self.closed else { abort("Store::accumulator called after close") }
  { owner: self.runtime.id(), raw: self.scope.accumulator(label?) }
}

///|
pub fn[A] Accumulator::push(
  self : Accumulator[A],
  value : A,
) -> Unit raise Failure {
  self.raw.push(value)
}

///|
fn[A, T] contribution(
  producer : @incr.Derived[T],
  accumulator : @incr.Accumulator[A],
) -> Contribution[A] {
  {
    values: () => producer.accumulated_or_abort(accumulator),
    snapshot: () => producer.accumulated_peek(accumulator),
  }
}

///|
/// Rejects cross-Store binding before a producer or contribution is created.
fn[A] Accumulator::check_store(
  self : Accumulator[A],
  store : Store,
) -> Unit raise Failure {
  guard self.owner == store.runtime.id() else {
    fail("Accumulator producer belongs to a different Store")
  }
}

///|
/// Creates an Eq producer and binds its producer-local contribution.
pub fn[A, T : Eq] Accumulator::derived(
  self : Accumulator[A],
  store : Store,
  compute : () -> T raise Failure,
  label? : String,
) -> (View[T], Contribution[A]) raise Failure {
  guard !store.closed else { abort("Accumulator::derived called after close") }
  self.check_store(store)
  let producer = store.scope.derived(compute, label?)
  (derived_view(producer), contribution(producer, self.raw))
}

///|
/// Creates a custom-backdated producer and binds its contribution.
pub fn[A, T : @incr.BackdateEq] Accumulator::derived_with_backdate(
  self : Accumulator[A],
  store : Store,
  compute : () -> T raise Failure,
  label? : String,
) -> (View[T], Contribution[A]) raise Failure {
  guard !store.closed else {
    abort("Accumulator::derived_with_backdate called after close")
  }
  self.check_store(store)
  let producer = @incr.Derived::with_backdate(store.runtime, compute, label?)
  store.scope.add_cell_ids([producer.id()])
  (derived_view(producer), contribution(producer, self.raw))
}

///|
/// Creates an unbounded no-backdate producer and binds its contribution.
pub fn[A, T] Accumulator::derived_no_backdate(
  self : Accumulator[A],
  store : Store,
  compute : () -> T raise Failure,
  label? : String,
) -> (View[T], Contribution[A]) raise Failure {
  guard !store.closed else {
    abort("Accumulator::derived_no_backdate called after close")
  }
  self.check_store(store)
  let producer = store.scope.derived_no_backdate(compute, label?)
  (derived_view(producer), contribution(producer, self.raw))
}

///|
/// Returns the callable tracked read capability for this producer.
pub fn[A] Contribution::view(self : Contribution[A]) -> View[Array[A]] {
  self.values
}

///|
/// Returns an untracked defensive snapshot for this producer.
pub fn[A] Contribution::peek(self : Contribution[A]) -> Array[A] {
  (self.snapshot)()
}

///|
pub fn[A] Accumulator::dispose(self : Accumulator[A]) -> Unit {
  self.raw.dispose()
}

///|
/// Reports the status of the current advanced lifecycle handle.
pub fn[A] Accumulator::is_disposed(self : Accumulator[A]) -> Bool {
  self.raw.is_disposed()
}

///|
pub fn Store::close(self : Store) -> Unit {
  if !self.closed {
    self.closed = true
    self.scope.dispose()
  }
}
