///|
/// Keyed derived map facade. Lazily caches per-key `Derived` entries on first
/// access; scope-owned maps clear entries on dispose.
pub(all) struct DerivedMap[K, V] {
  priv rt : Runtime
  priv compute : (K) -> V raise Failure
  priv label : String?
  priv entries : @hashmap.HashMap[K, Derived[V]]
  priv disposed : Ref[CellId?]
}

///|
/// Creates a keyed derived map.
pub fn[K : Hash + Eq, V] DerivedMap::DerivedMap(
  rt : Runtime,
  compute : (K) -> V raise Failure,
  label? : String,
) -> DerivedMap[K, V] {
  { rt, compute, label, entries: @hashmap.HashMap([]), disposed: { val: None } }
}

///|
/// Creates a fallible keyed derived map: a per-key recoverable domain failure
/// is expressed in the value as `Result[V, E]`, never raised. The compute is
/// `noraise`. See `Derived::fallible` and
/// docs/design/specs/2026-05-28-honest-read-error-ownership.md.
pub fn[K : Hash + Eq, V, E] DerivedMap::fallible(
  rt : Runtime,
  compute : (K) -> Result[V, E],
  label? : String,
) -> DerivedMap[K, Result[V, E]] {
  // See `Derived::fallible`: wrap the noraise compute for the base ctor.
  DerivedMap::DerivedMap(rt, fn(k) { compute(k) }, label?)
}

///|
fn[K, V] DerivedMap::guard_live(
  self : DerivedMap[K, V],
) -> Result[Unit, ReadError] {
  match self.disposed.val {
    None => Ok(())
    Some(id) => Err(ReadError::disposed(id))
  }
}

///|
fn[K, V] DerivedMap::dispose_from_scope(self : DerivedMap[K, V]) -> Unit {
  guard self.disposed.val is None else { return }
  let mut disposed_id : CellId? = None
  for _, entry in self.entries {
    if disposed_id is None {
      disposed_id = Some(entry.id())
    }
  }
  let id = match disposed_id {
    Some(id) => id
    None => {
      let tombstone = Derived::Derived(
        self.rt,
        () => (),
        label="derived_map_disposed",
      )
      tombstone.dispose()
      tombstone.id()
    }
  }
  self.disposed.val = Some(id)
  self.clear_entries()
}

///|
/// Strict graph read for `key`. Requires an active tracked context.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::get(
  self : DerivedMap[K, V],
  key : K,
) -> Result[V, ReadError] {
  match self.guard_live() {
    Ok(_) => self.get_strict_honest(key)
    Err(e) => Err(e)
  }
}

///|
/// Strict graph read for `key` that aborts on invalid context or any read error.
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
) -> Result[V, ReadError] {
  match self.guard_live() {
    Ok(_) => self.read_honest(key)
    Err(e) => Err(e)
  }
}

///|
/// Permissive read for `key` that aborts on any read error.
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
/// Returns the value for `key`, or `fallback` if a read error is detected.
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
/// Returns the value for `key`, or computes a fallback from the read error.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::read_or_else(
  self : DerivedMap[K, V],
  key : K,
  fallback : (ReadError) -> V,
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
  match self.guard_live() {
    Ok(_) => self.entries.contains(key)
    Err(_) => false
  }
}

///|
/// Returns the number of cached entries.
pub fn[K, V] DerivedMap::cache_len(self : DerivedMap[K, V]) -> Int {
  match self.guard_live() {
    Ok(_) => self.entries.length()
    Err(_) => 0
  }
}

///|
/// Removes cached entries whose underlying cells have been disposed.
pub fn[K : Hash + Eq, V] DerivedMap::sweep_cache(
  self : DerivedMap[K, V],
) -> Int {
  match self.guard_live() {
    Ok(_) => self.sweep_entries()
    Err(_) => 0
  }
}

///|
/// Clears all cached entries.
pub fn[K, V] DerivedMap::clear_cache(self : DerivedMap[K, V]) -> Unit {
  match self.guard_live() {
    Ok(_) => self.clear_entries()
    Err(_) => ()
  }
}
