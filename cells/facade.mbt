///|
/// Target-name input cell facade over `Signal`.
pub(all) struct Input[T] {
  priv inner : Signal[T]
}

///|
/// Creates an input cell with the given initial value.
pub fn[T] Input::Input(
  rt : Runtime,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> Input[T] {
  { inner: Signal(rt, initial, durability~, label?) }
}

///|
/// Returns the current value and records a dependency when tracked.
pub fn[T] Input::get(self : Input[T]) -> T {
  self.inner.get()
}

///|
/// Returns the current value without recording a dependency.
pub fn[T] Input::peek(self : Input[T]) -> T {
  self.inner.peek()
}

///|
/// Sets the input to a new value, skipping same-value updates.
pub fn[T : Eq] Input::set(self : Input[T], new_value : T) -> Unit {
  self.inner.set(new_value)
}

///|
/// Sets the input to a value and always bumps the relevant revision.
pub fn[T] Input::force_set(self : Input[T], new_value : T) -> Unit {
  self.inner.set_unconditional(new_value)
}

///|
/// Target-name lazy derived cell facade over `Memo`.
pub(all) struct Derived[T] {
  priv inner : Memo[T]
}

///|
/// Creates a lazy derived value.
pub fn[T : Eq] Derived::Derived(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
) -> Derived[T] {
  { inner: Memo(rt, compute, label?) }
}

///|
/// Strict graph read. Requires an active tracked context.
pub fn[T] Derived::get(self : Derived[T]) -> Result[T, CycleError] {
  self.inner.get_strict_result()
}

///|
/// Strict graph read that aborts on invalid context or cycle.
pub fn[T] Derived::get_or_abort(self : Derived[T]) -> T {
  match self.get() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Permissive read. Works outside the graph and records a dependency if tracked.
pub fn[T] Derived::read(self : Derived[T]) -> Result[T, CycleError] {
  self.inner.read_result()
}

///|
/// Permissive read that aborts on cycle.
pub fn[T] Derived::read_or_abort(self : Derived[T]) -> T {
  match self.read() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Target-name reachable lazy derived cell facade over `HybridMemo`.
pub(all) struct ReachableDerived[T] {
  priv inner : HybridMemo[T]
}

///|
/// Creates a reachable lazy derived value.
pub fn[T : Eq] ReachableDerived::ReachableDerived(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
) -> ReachableDerived[T] {
  { inner: HybridMemo(rt, compute, label?) }
}

///|
/// Strict graph read. Requires an active tracked context.
pub fn[T : Eq] ReachableDerived::get(
  self : ReachableDerived[T],
) -> Result[T, CycleError] {
  self.inner.get_strict_result()
}

///|
/// Strict graph read that aborts on invalid context or cycle.
pub fn[T : Eq] ReachableDerived::get_or_abort(self : ReachableDerived[T]) -> T {
  match self.get() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Permissive read. Works outside the graph and records a dependency if tracked.
pub fn[T : Eq] ReachableDerived::read(
  self : ReachableDerived[T],
) -> Result[T, CycleError] {
  self.inner.read_result()
}

///|
/// Permissive read that aborts on cycle.
pub fn[T : Eq] ReachableDerived::read_or_abort(self : ReachableDerived[T]) -> T {
  match self.read() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Target-name eager derived cell facade over `Reactive`.
pub(all) struct EagerDerived[T] {
  priv inner : Reactive[T]
}

///|
/// Creates an eager derived value.
pub fn[T : Eq] EagerDerived::EagerDerived(
  rt : Runtime,
  compute : () -> T,
) -> EagerDerived[T] {
  { inner: Reactive::new(rt, compute) }
}

///|
/// Strict graph read. Requires an active tracked context.
pub fn[T] EagerDerived::get(self : EagerDerived[T]) -> T {
  self.inner.get()
}

///|
/// Permissive read. Works outside the graph and records a dependency if tracked.
pub fn[T] EagerDerived::read(self : EagerDerived[T]) -> T {
  self.inner.read_permissive()
}

///|
/// Target-name keyed derived facade over `MemoMap`.
pub(all) struct DerivedMap[K, V] {
  priv inner : MemoMap[K, V]
}

///|
/// Creates a keyed derived map.
pub fn[K : Hash + Eq, V] DerivedMap::DerivedMap(
  rt : Runtime,
  compute : (K) -> V raise Failure,
  label? : String,
) -> DerivedMap[K, V] {
  { inner: MemoMap(rt, compute, label?) }
}

///|
/// Strict graph read for `key`. Requires an active tracked context.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::get(
  self : DerivedMap[K, V],
  key : K,
) -> Result[V, CycleError] {
  self.inner.get_strict_result(key)
}

///|
/// Strict graph read for `key` that aborts on invalid context or cycle.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::get_or_abort(
  self : DerivedMap[K, V],
  key : K,
) -> V {
  match self.get(key) {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Permissive read for `key`. Records a dependency if tracked.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::read(
  self : DerivedMap[K, V],
  key : K,
) -> Result[V, CycleError] {
  self.inner.read_result(key)
}

///|
/// Permissive read for `key` that aborts on cycle.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::read_or_abort(
  self : DerivedMap[K, V],
  key : K,
) -> V {
  match self.read(key) {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Returns the value for `key`, or `fallback` if a cycle is detected.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::read_or(
  self : DerivedMap[K, V],
  key : K,
  fallback : V,
) -> V {
  match self.read(key) {
    Ok(value) => value
    Err(_) => fallback
  }
}

///|
/// Returns the value for `key`, or computes a fallback from the cycle error.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::read_or_else(
  self : DerivedMap[K, V],
  key : K,
  fallback : (CycleError) -> V,
) -> V {
  match self.read(key) {
    Ok(value) => value
    Err(e) => fallback(e)
  }
}

///|
/// Returns whether a cached entry exists for `key`.
pub fn[K : Hash + Eq, V] DerivedMap::has_cached(
  self : DerivedMap[K, V],
  key : K,
) -> Bool {
  self.inner.contains(key)
}

///|
/// Returns the number of cached entries.
pub fn[K, V] DerivedMap::cache_len(self : DerivedMap[K, V]) -> Int {
  self.inner.length()
}

///|
/// Removes cached entries whose underlying cells have been disposed.
pub fn[K : Hash + Eq, V] DerivedMap::sweep_cache(
  self : DerivedMap[K, V],
) -> Int {
  self.inner.sweep()
}

///|
/// Clears all cached entries.
pub fn[K, V] DerivedMap::clear_cache(self : DerivedMap[K, V]) -> Unit {
  self.inner.clear()
}
