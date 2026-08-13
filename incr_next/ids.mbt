///|
/// Identity of one store. Values are created only by the kernel.
pub struct StoreId {
  priv value : Int
} derive(Eq, Hash, Debug)

///|
/// The committed state clock owned by one Store.
pub struct Revision {
  priv value : Int
} derive(Eq, Hash, Debug)

///|
/// Identity of one Region.
pub struct RegionId {
  priv owner : StoreId
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
/// A Region identity and its generation.
pub struct RegionGeneration {
  priv region : RegionId
  priv epoch : Int
} derive(Eq, Hash, Debug)

///|
/// Identity of one Source definition.
pub struct SourceId {
  priv owner : StoreId
  priv sequence : Int
} derive(Eq, Hash, Debug)

///|
pub fn SourceId::store_id(self : SourceId) -> StoreId {
  self.owner
}

///|
pub fn SourceId::sequence(self : SourceId) -> Int {
  self.sequence
}

///|
pub fn StoreId::value(self : StoreId) -> Int {
  self.value
}

///|
pub fn Revision::value(self : Revision) -> Int {
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
