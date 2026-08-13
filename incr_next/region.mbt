///|
priv struct RegionEpoch {
  owner : StoreId
  region : RegionId
  generation : Ref[Int]
  closed : Ref[Bool]
}

///|
fn RegionEpoch::snapshot(self : RegionEpoch) -> RegionGeneration {
  { region: self.region, epoch: self.generation.val }
}

///|
fn RegionEpoch::accepts(
  self : RegionEpoch,
  generation : RegionGeneration,
) -> Bool {
  !self.closed.val && self.snapshot() == generation
}

///|
/// A lifetime owner for Sources and Queries.
pub struct Region {
  priv owner : StoreId
  priv epoch : RegionEpoch
  priv change_epoch : Ref[Int]
  priv close_actions : Array[() -> Unit]
}

///|
/// Creates a Region in the supplied Store when the alpha gate is idle.
pub fn Store::region(self : Store) -> Result[Region, RegionError] {
  match phase_region_error() {
    Some(error) => Err(error)
    None => {
      let sequence = self.next_sequence.val
      self.next_sequence.val = sequence + 1
      let id : RegionId = { owner: self.id, sequence }
      Ok({
        owner: self.id,
        epoch: {
          owner: self.id,
          region: id,
          generation: Ref(0),
          closed: Ref(false),
        },
        change_epoch: self.change_epoch,
        close_actions: [],
      })
    }
  }
}

///|
fn Region::check_open(self : Region) -> RegionError? {
  match phase_region_error() {
    Some(error) => Some(error)
    None =>
      if self.epoch.closed.val {
        Some(RegionError::ClosedRegion(generation=self.epoch.snapshot()))
      } else {
        None
      }
  }
}

///|
/// Returns the Region identity.
pub fn Region::id(self : Region) -> RegionId {
  self.epoch.region
}

///|
/// Returns the current Region generation.
pub fn Region::generation(self : Region) -> RegionGeneration {
  self.epoch.snapshot()
}

///|
/// Closes this Region and releases its registered payloads.
pub fn Region::close(self : Region) -> Result[Unit, RegionError] {
  match self.check_open() {
    Some(error) => Err(error)
    None => {
      self.close_actions.each(action => action())
      self.close_actions.clear()
      self.epoch.closed.val = true
      self.epoch.generation.val = self.epoch.generation.val + 1
      self.change_epoch.val = self.change_epoch.val + 1
      Ok(())
    }
  }
}
