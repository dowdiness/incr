///|
/// Returns the Derived entry for `key`, creating and caching it on first access.
fn[K : Hash + Eq, V : Eq] DerivedMap::get_or_create_entry(
  self : DerivedMap[K, V],
  key : K,
) -> Derived[V] {
  match self.entries.get(key) {
    Some(entry) => entry
    None => {
      let entry = match self.label {
        Some(label) => Derived(self.rt, () => (self.compute)(key), label~)
        None => Derived(self.rt, () => (self.compute)(key))
      }
      self.entries.set(key, entry)
      entry
    }
  }
}

///|
/// Package-private strict honest read. Requires an active tracked context;
/// reports mechanism failures (cycle / disposed per-key entry) as `ReadError`.
fn[K : Hash + Eq, V : Eq] DerivedMap::get_strict_honest(
  self : DerivedMap[K, V],
  key : K,
) -> Result[V, ReadError] {
  guard self.rt.core.tracking.stack.length() > 0 else {
    abort(
      "DerivedMap::get() called outside tracked context. Use DerivedMap::read(key) or DerivedMap::read_or_abort(key) to read from outside the graph.",
    )
  }
  self.read_honest(key)
}

///|
/// Package-private honest permissive read — the single source of truth for the
/// read channel. A read of a per-key entry that gc disposed (while the map still
/// caches the entry) returns `Err(Disposed(_))`; a cycle returns
/// `Err(Cycle(_))`; a compute `raise Failure` is a defect and still aborts.
fn[K : Hash + Eq, V : Eq] DerivedMap::read_honest(
  self : DerivedMap[K, V],
  key : K,
) -> Result[V, ReadError] {
  let entry = self.get_or_create_entry(key)
  guard !entry.is_disposed() else {
    return Err(ReadError::disposed(entry.id()))
  }
  let result = entry.get_result_inner() catch {
    e => {
      self.rt.drain_pending_events_direct()
      abort("DerivedMap compute raised: " + e.to_string())
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
fn[K : Hash + Eq, V : Eq] DerivedMap::get_strict_result(
  self : DerivedMap[K, V],
  key : K,
) -> Result[V, CycleError] {
  guard self.rt.core.tracking.stack.length() > 0 else {
    abort(
      "DerivedMap::get() called outside tracked context. Use DerivedMap::read(key) or DerivedMap::read_or_abort(key) to read from outside the graph.",
    )
  }
  self.read_result(key)
}

///|
/// Package-private permissive Result read. Records a dependency when tracked.
/// Compatibility projection of `read_honest` onto `CycleError`: a disposed
/// per-key entry aborts (legacy contract), a cycle is `Err(CycleError)`.
fn[K : Hash + Eq, V : Eq] DerivedMap::read_result(
  self : DerivedMap[K, V],
  key : K,
) -> Result[V, CycleError] {
  match self.read_honest(key) {
    Ok(v) => Ok(v)
    Err(ReadError::Cycle(e)) => Err(e)
    Err(ReadError::Disposed(_)) =>
      abort("DerivedMap::read called on a disposed entry")
  }
}

///|
fn[K : Hash + Eq, V] DerivedMap::sweep_entries(self : DerivedMap[K, V]) -> Int {
  let to_remove : Array[K] = []
  for key, entry in self.entries {
    if entry.is_disposed() {
      to_remove.push(key)
    }
  }
  for key in to_remove {
    self.entries.remove(key)
  }
  to_remove.length()
}

///|
fn[K, V] DerivedMap::clear_entries(self : DerivedMap[K, V]) -> Unit {
  for _, entry in self.entries {
    entry.dispose()
  }
  self.entries.clear()
}
