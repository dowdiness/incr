///|
/// One immutable ordered declaration entry and its authorization origin.
pub(all) struct ManifestEntry {
  local_port_id : PortId
  origin : PortOrigin
} derive(Eq, Debug)

///|
/// Ordered, deduplicated declarations for one Formula.
pub struct Manifest {
  priv entries : Array[ManifestEntry]
}

///|
pub fn Manifest::entries(self : Manifest) -> Array[ManifestEntry] {
  self.entries.copy()
}

///|
pub fn Manifest::contains(self : Manifest, port_id : PortId) -> Bool {
  self.entries.any(entry => entry.local_port_id == port_id)
}
