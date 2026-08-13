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
/// Returns the committed clock value represented by this Revision.
pub fn Revision::value(self : Revision) -> Int {
  self.value
}

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
/// Identity of one Source definition, private to transaction staging.
priv struct SourceId {
  owner : StoreId
  sequence : Int
} derive(Eq, Hash, Debug)
