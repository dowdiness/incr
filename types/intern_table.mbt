///|
/// A stable integer key returned by `InternTable::intern`.
///
/// Same value always maps to the same `InternId` within a table. IDs are
/// monotonically increasing and can be used as array indices or `MemoMap` keys.
pub(all) struct InternId {
  index : Int
} derive(Eq, Debug, Compare)

///|
pub impl Show for InternId with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Hash for InternId with hash(self) {
  self.index.hash()
}

///|
pub impl Hash for InternId with hash_combine(self, hasher) {
  self.index.hash_combine(hasher)
}

///|
/// A grow-only interning table that assigns stable `InternId` keys to values.
///
/// Interning guarantees that equal values always receive the same `InternId`,
/// enabling cheap identity comparison (`id1 == id2`) instead of deep structural
/// equality. Used by the bidirectional type-checker as `MemoMap` keys for
/// cross-revision cache stability.
pub(all) struct InternTable[T] {
  to_id : @hashmap.HashMap[T, InternId]
  values : Array[T]
}

///|
pub fn[T] InternTable::new() -> InternTable[T] {
  { to_id: @hashmap.new(), values: [] }
}

///|
/// Returns the `InternId` for `value`, inserting it if not already present.
pub fn[T : Hash + Eq] InternTable::intern(
  self : InternTable[T],
  value : T,
) -> InternId {
  match self.to_id.get(value) {
    Some(id) => id
    None => {
      let id = InternId::{ index: self.values.length() }
      self.values.push(value)
      self.to_id.set(value, id)
      id
    }
  }
}

///|
/// Returns the value associated with `id`.
///
/// Panics if `id` was not produced by this table.
pub fn[T] InternTable::get(self : InternTable[T], id : InternId) -> T {
  self.values[id.index]
}

///|
/// Returns the number of unique values interned so far.
pub fn[T] InternTable::len(self : InternTable[T]) -> Int {
  self.values.length()
}
