///|

///|
/// An opaque, non-callable recipe View. It exposes no public read operation.
pub struct View[V] {
  priv owner : StoreId
  priv generation : RegionGeneration
  priv dependency_kind : DependencyKind
  priv verifier : (QueryContext) -> Verification
  priv recipe : (QueryContext) -> Result[V, ReadError]
}
