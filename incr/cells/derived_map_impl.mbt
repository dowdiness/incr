///|
/// Returns the Derived entry for `key`, creating and caching it on first access.
fn[K : Hash + Eq, V : Eq] DerivedMap::get_or_create_entry(
  self : DerivedMap[K, V],
  key : K,
) -> Derived[V] {
  match self.entries.get(key) {
    Some(entry) if !entry.is_disposed() => entry
    _ => {
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
/// reports cycles as `ReadError` after recreating GC-disposed private entries.
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
/// read channel. A per-key entry that gc disposed is recreated before reading;
/// a cycle returns `Err(Cycle(_))`; a compute `raise Failure` is a defect and
/// still aborts.
fn[K : Hash + Eq, V : Eq] DerivedMap::read_honest(
  self : DerivedMap[K, V],
  key : K,
) -> Result[V, ReadError] {
  let entry = self.get_or_create_entry(key)
  let result : Result[V, ReadError] = Ok(entry.get_result_inner()) catch {
    @incr_types.CycleError::CycleDetected(_, _, _) as e =>
      Err(ReadError::cycle(e))
    e => {
      self.rt.drain_pending_events_direct()
      abort("DerivedMap compute raised: " + e.to_string())
    }
  }
  if self.rt.has_pending_events() {
    self.rt.drain_pending_events_if_idle()
  }
  result
}

///|
fn[K : Hash + Eq, V] DerivedMap::sweep_entries(
  self : DerivedMap[K, V],
) -> Int32 {
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
