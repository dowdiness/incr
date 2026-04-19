///|
/// A keyed memoization map backed by one Memo per key.
///
/// `MemoMap[K, V]` provides a minimal parameterized-query pattern:
/// each key gets its own lazily-created `Memo[V]`, and subsequent reads
/// of that key reuse the cached memoized value.
///
/// Reading a key requires `K : Hash + Eq` and `V : Eq`, matching the
/// underlying `HashMap` lookup and `Memo` value semantics.
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime()
/// let source = Signal(rt, 10)
/// let by_id = MemoMap(rt, (id : Int) => source.get() + id)
///
/// inspect(by_id.get(1), content="11")
/// inspect(by_id.get(1), content="11")  // cache hit for key=1
/// inspect(by_id.get(2), content="12")  // separate memo for key=2
/// ```
pub(all) struct MemoMap[K, V] {
  priv rt : Runtime
  priv compute : (K) -> V
  priv label : String?
  priv entries : @hashmap.HashMap[K, Memo[V]]

  fn[K, V] new(
    rt : Runtime,
    compute : (K) -> V,
    label? : String,
  ) -> MemoMap[K, V]
}

///|
/// Creates a new empty MemoMap.
///
/// Entries are created lazily on first `get`/`get_result` per key.
pub fn[K, V] MemoMap::new(
  rt : Runtime,
  compute : (K) -> V,
  label? : String,
) -> MemoMap[K, V] {
  { rt, compute, label, entries: @hashmap.new() }
}

///|
/// Returns the value for `key`, computing lazily on first access.
///
/// Reads the memo outside any tracked context (untracked). This is the
/// correct way to read from test code or other untracked call sites.
pub fn[K : Hash + Eq, V : Eq] MemoMap::get(self : MemoMap[K, V], key : K) -> V {
  self.get_or_create_memo(key).get_untracked()
}

///|
/// Returns the value for `key`, aborting if called outside a tracked context.
///
/// Stricter-contract peer of `get()`. Both methods record a dependency on
/// the per-key memo when invoked from inside another memo's compute
/// function; the difference is what happens at top level — `get()` reads
/// silently without recording a dep, whereas `get_tracked()` aborts via
/// `Memo::get`'s tracking guard. Prefer this when the call site is
/// expected to be tracking (catches "meant to call from inside a memo
/// but I'm not" bugs).
///
/// Caveat: `MemoMap::clear()` unconditionally disposes every per-key
/// wrapper, so a tracked dependent recorded via this method will hit
/// the disposed-dep guard on its next verify if `clear()` runs between
/// reads. `gc()` is safe — it keeps wrapper memos alive as long as a
/// tracked dependent is reachable from a root. The same caveat applies
/// to `get()`.
pub fn[K : Hash + Eq, V : Eq] MemoMap::get_tracked(
  self : MemoMap[K, V],
  key : K,
) -> V {
  self.get_or_create_memo(key).get()
}

///|
/// Returns the value for `key` as a Result, matching `Memo::get_result`.
///
/// Reads the memo outside any tracked context (untracked).
pub fn[K : Hash + Eq, V : Eq] MemoMap::get_result(
  self : MemoMap[K, V],
  key : K,
) -> Result[V, CycleError] {
  self.get_or_create_memo(key).get_result_inner()
}

///|
/// Returns the value for `key`, or `fallback` if a cycle is detected.
pub fn[K : Hash + Eq, V : Eq] MemoMap::get_or(
  self : MemoMap[K, V],
  key : K,
  fallback : V,
) -> V {
  match self.get_result(key) {
    Ok(v) => v
    Err(_) => fallback
  }
}

///|
/// Returns the value for `key`, or computes a fallback from the cycle error.
pub fn[K : Hash + Eq, V : Eq] MemoMap::get_or_else(
  self : MemoMap[K, V],
  key : K,
  fallback : (CycleError) -> V,
) -> V {
  match self.get_result(key) {
    Ok(v) => v
    Err(e) => fallback(e)
  }
}

///|
/// Returns true if a memo entry for `key` has already been created.
pub fn[K : Hash + Eq, V] MemoMap::contains(
  self : MemoMap[K, V],
  key : K,
) -> Bool {
  self.entries.contains(key)
}

///|
/// Returns the number of memo entries that have been created so far.
pub fn[K, V] MemoMap::length(self : MemoMap[K, V]) -> Int {
  self.entries.length()
}

///|
/// Returns the memo for `key`, creating and caching it on first access.
fn[K : Hash + Eq, V : Eq] MemoMap::get_or_create_memo(
  self : MemoMap[K, V],
  key : K,
) -> Memo[V] {
  match self.entries.get(key) {
    Some(memo) => memo
    None => {
      // Each key gets a dedicated memo; key is captured by value in closure.
      let memo = match self.label {
        Some(label) => Memo::new(self.rt, () => (self.compute)(key), label~)
        None => Memo::new(self.rt, () => (self.compute)(key))
      }
      self.entries.set(key, memo)
      memo
    }
  }
}

///|
/// Removes entries whose memos have been disposed (e.g. by gc()).
///
/// Two-pass: collects keys to remove, then removes them (cannot mutate
/// HashMap during iteration). Returns the number of entries swept.
///
/// Call after `Runtime::gc()` to clean up stale entries.
pub fn[K : Hash + Eq, V] MemoMap::sweep(self : MemoMap[K, V]) -> Int {
  let to_remove : Array[K] = []
  for key, memo in self.entries {
    if memo.is_disposed() {
      to_remove.push(key)
    }
  }
  for key in to_remove {
    self.entries.remove(key)
  }
  to_remove.length()
}

///|
/// Disposes every wrapper memo and empties the entry map.
///
/// Unlike `sweep()`, which only removes entries whose memos are already
/// disposed, `clear()` actively disposes each wrapper memo. Use this after
/// a structural event (e.g. pipeline rebuild) that invalidates all cached
/// keys — `sweep()` is insufficient because MemoMap's wrappers are
/// Runtime-owned and are not reached by chain-scope disposal.
pub fn[K, V] MemoMap::clear(self : MemoMap[K, V]) -> Unit {
  for _, memo in self.entries {
    memo.dispose()
  }
  self.entries.clear()
}
