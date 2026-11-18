///|
/// Identity of one store. Values are created only by the kernel.
#derive(Eq, Hash, Debug)
priv struct StoreId {
  value : Int32
}

///|
/// Identity of one Region.
#derive(Eq, Hash, Debug)
priv struct RegionId {
  owner : StoreId
  sequence : Int32
}

///|
/// A Region identity and its generation.
#derive(Eq, Hash, Debug)
priv struct RegionGeneration {
  region : RegionId
  epoch : Int32
}

///|
/// Identity of one Query definition, private to invocation tracking.
#derive(Eq, Debug)
priv struct QueryId {
  value : Int32
}

///|
/// Identity of one Source definition, private to transaction staging.
#derive(Eq, Hash, Debug)
priv struct SourceId {
  owner : StoreId
  sequence : Int32
}
