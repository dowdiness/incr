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
/// One committed change epoch. Region close can advance this without a revision.
pub(all) struct ChangeEpoch {
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
/// Identity of one root evaluation session. The session identity is intentionally
/// not exposed as an EvalCtx accessor.
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
/// Identity of one memo local to a Query definition.
pub(all) struct MemoId {
  priv query : QueryId
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
pub fn StoreId::value(self : StoreId) -> Int {
  self.value
}

///|
pub fn Revision::value(self : Revision) -> Int {
  self.value
}

///|
pub fn ChangeEpoch::value(self : ChangeEpoch) -> Int {
  self.value
}

///|
pub fn RegionId::store_id(self : RegionId) -> StoreId {
  self.owner
}

///|
pub fn RegionId::sequence(self : RegionId) -> Int {
  self.sequence
}

///|
pub fn RegionGeneration::region_id(self : RegionGeneration) -> RegionId {
  self.region
}

///|
pub fn RegionGeneration::epoch(self : RegionGeneration) -> Int {
  self.epoch
}

///|
pub fn SourceId::store_id(self : SourceId) -> StoreId {
  self.owner
}

///|
pub fn SourceId::sequence(self : SourceId) -> Int {
  self.sequence
}

///|
pub fn QueryId::store_id(self : QueryId) -> StoreId {
  self.owner
}

///|
pub fn QueryId::sequence(self : QueryId) -> Int {
  self.sequence
}

///|
pub fn ViewHandleId::store_id(self : ViewHandleId) -> StoreId {
  self.owner
}

///|
pub fn ViewHandleId::sequence(self : ViewHandleId) -> Int {
  self.sequence
}

///|
pub fn TransactionId::store_id(self : TransactionId) -> StoreId {
  self.owner
}

///|
pub fn TransactionId::sequence(self : TransactionId) -> Int {
  self.sequence
}

///|
pub fn MemoId::query_id(self : MemoId) -> QueryId {
  self.query
}

///|
pub fn MemoId::sequence(self : MemoId) -> Int {
  self.sequence
}
