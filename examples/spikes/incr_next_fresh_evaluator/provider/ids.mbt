///|
/// Identity of one Store.
pub(all) struct StoreId {
  priv value : Int
} derive(Eq, Hash, Debug)

///|
/// One committed Store revision.
pub(all) struct Revision {
  priv value : Int
} derive(Eq, Hash, Debug)

///|
/// Identity of one Region.
pub(all) struct RegionId {
  priv owner : StoreId
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
/// Region identity plus its lifetime epoch.
pub(all) struct RegionGeneration {
  priv region : RegionId
  priv epoch : Int
} derive(Eq, Hash, Debug)

///|
/// Identity of one Source definition.
pub(all) struct SourceId {
  priv owner : StoreId
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
/// Identity of one Query definition.
pub(all) struct QueryId {
  priv owner : StoreId
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
/// Identity of one opaque View recipe.
pub(all) struct ViewHandleId {
  priv owner : StoreId
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
/// Identity of one root evaluation session.
pub(all) struct EvalId {
  priv owner : StoreId
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
/// Identity of one transaction session.
pub(all) struct TransactionId {
  priv owner : StoreId
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
/// Returns the numeric Store identity for evidence output.
pub fn StoreId::value(self : StoreId) -> Int {
  self.value
}

///|
/// Returns the numeric revision.
pub fn Revision::value(self : Revision) -> Int {
  self.value
}

///|
/// Returns RegionId's Store provenance.
pub fn RegionId::store_id(self : RegionId) -> StoreId {
  self.owner
}

///|
/// Returns RegionId's Store-local sequence.
pub fn RegionId::sequence(self : RegionId) -> Int {
  self.sequence
}

///|
/// Returns the Region identity captured by a generation.
pub fn RegionGeneration::region_id(self : RegionGeneration) -> RegionId {
  self.region
}

///|
/// Returns the epoch captured by a generation.
pub fn RegionGeneration::epoch(self : RegionGeneration) -> Int {
  self.epoch
}

///|
/// Returns SourceId's Store provenance.
pub fn SourceId::store_id(self : SourceId) -> StoreId {
  self.owner
}

///|
/// Returns SourceId's Store-local sequence.
pub fn SourceId::sequence(self : SourceId) -> Int {
  self.sequence
}

///|
/// Returns QueryId's Store provenance.
pub fn QueryId::store_id(self : QueryId) -> StoreId {
  self.owner
}

///|
/// Returns QueryId's Store-local sequence.
pub fn QueryId::sequence(self : QueryId) -> Int {
  self.sequence
}

///|
/// Returns ViewHandleId's Store provenance.
pub fn ViewHandleId::store_id(self : ViewHandleId) -> StoreId {
  self.owner
}

///|
/// Returns ViewHandleId's Store-local sequence.
pub fn ViewHandleId::sequence(self : ViewHandleId) -> Int {
  self.sequence
}

///|
/// Returns EvalId's Store provenance.
pub fn EvalId::store_id(self : EvalId) -> StoreId {
  self.owner
}

///|
/// Returns EvalId's Store-local sequence.
pub fn EvalId::sequence(self : EvalId) -> Int {
  self.sequence
}

///|
/// Returns TransactionId's Store provenance.
pub fn TransactionId::store_id(self : TransactionId) -> StoreId {
  self.owner
}

///|
/// Returns TransactionId's Store-local sequence.
pub fn TransactionId::sequence(self : TransactionId) -> Int {
  self.sequence
}
