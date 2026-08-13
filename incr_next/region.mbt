///|
priv enum RegionState {
  Open
  Closing
  Closed
}

///|
priv struct RegionEpoch {
  owner : StoreId
  region : RegionId
  generation : Ref[Int]
  state : Ref[RegionState]
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
  self.state.val is Open && self.snapshot() == generation
}

///|
/// A lifetime owner for Sources and Queries.
pub struct Region {
  priv owner : StoreId
  priv epoch : RegionEpoch
  priv change_epoch : Ref[Int]
  priv next_sequence : Ref[Int]
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
          state: Ref(Open),
        },
        change_epoch: self.change_epoch,
        next_sequence: self.next_sequence,
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
      match self.epoch.state.val {
        Open => None
        Closing | Closed =>
          Some(RegionError::ClosedRegion(generation=self.epoch.snapshot()))
      }
  }
}

///|
/// Closes this Region and releases its registered payloads.
pub fn Region::close(self : Region) -> Result[Unit, RegionError] {
  match self.check_open() {
    Some(error) => Err(error)
    None => {
      self.epoch.state.val = Closing
      self.close_actions.each(action => action())
      self.close_actions.clear()
      self.epoch.generation.val = self.epoch.generation.val + 1
      self.epoch.state.val = Closed
      self.change_epoch.val = self.change_epoch.val + 1
      Ok(())
    }
  }
}
