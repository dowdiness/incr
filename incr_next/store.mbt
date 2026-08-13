///|
/// One Store owns its clocks and identity; it owns no Region registry.
pub struct Store {
  priv id : StoreId
  priv revision_clock : Ref[Int]
  priv change_epoch : Ref[Int]
  priv next_sequence : Ref[Int]
}

///|
/// Creates a Store at Revision zero.
pub fn Store::Store() -> Store {
  {
    id: fresh_store_id(),
    revision_clock: Ref(0),
    change_epoch: Ref(0),
    next_sequence: Ref(1),
  }
}

///|
/// Returns this Store's stable identity.
pub fn Store::id(self : Store) -> StoreId {
  self.id
}

///|
/// Returns this Store's committed Revision.
pub fn Store::revision(self : Store) -> Revision {
  { value: self.revision_clock.val }
}

///|
fn Store::allocate(self : Store) -> Int {
  let sequence = self.next_sequence.val
  self.next_sequence.val = sequence + 1
  sequence
}
