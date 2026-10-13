///|
/// Identity of one store. Values are created only by the kernel.
priv struct StoreId {
  value : Int32
} derive(Eq, Hash, Debug)

///|
/// Identity of one Region.
priv struct RegionId {
  owner : StoreId
  sequence : Int32
} derive(Eq, Hash, Debug)

///|
/// A Region identity and its generation.
priv struct RegionGeneration {
  region : RegionId
  epoch : Int32
} derive(Eq, Hash, Debug)

///|
/// Identity of one Query definition, private to invocation tracking.
priv struct QueryId {
  value : Int32
} derive(Eq, Debug)

///|
/// Identity of one Source definition, private to transaction staging.
priv struct SourceId {
  owner : StoreId
  sequence : Int32
} derive(Eq, Hash, Debug)
