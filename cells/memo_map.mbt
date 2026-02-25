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
pub fn[K : Hash + Eq, V : Eq] MemoMap::get(self : MemoMap[K, V], key : K) -> V {
  self.get_or_create_memo(key).get()
}

///|
/// Returns the value for `key` as a Result, matching `Memo::get_result`.
pub fn[K : Hash + Eq, V : Eq] MemoMap::get_result(
  self : MemoMap[K, V],
  key : K,
) -> Result[V, CycleError] {
  self.get_or_create_memo(key).get_result()
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
