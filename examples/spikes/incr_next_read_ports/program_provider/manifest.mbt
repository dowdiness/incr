///|
/// Ordered, deduplicated Port capabilities declared by one Formula.
pub struct Manifest {
  priv ports : Array[PortId]
}

///|
/// Returns a defensive copy of the manifest Port identities.
pub fn Manifest::port_ids(self : Manifest) -> Array[PortId] {
  self.ports.copy()
}

///|
/// Returns whether this manifest declares the Port.
pub fn Manifest::contains(self : Manifest, port_id : PortId) -> Bool {
  self.ports.contains(port_id)
}
