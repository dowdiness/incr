///|
pub(all) struct Store {
  priv core : StoreCore
}

///|
priv struct RegionCore {
  store : StoreCore
  epoch : RegionEpoch
  close_actions : Array[() -> Unit]
}

///|
pub(all) struct Region {
  priv core : RegionCore
}

///|
pub fn Store::Store() -> Store {
  { core: new_store_core() }
}

///|
pub fn Store::region(self : Store) -> Result[Region, RegionError] {
  match region_phase_error() {
    Some(error) => Err(error)
    None =>
      Ok({
        core: {
          store: self.core,
          epoch: self.core.new_region_epoch(),
          close_actions: [],
        },
      })
  }
}

///|
fn RegionCore::check_open(self : RegionCore) -> RegionError? {
  match region_phase_error() {
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
pub fn[T] Region::source(
  self : Region,
  initial : T,
) -> Result[Source[T], RegionError] {
  match self.core.check_open() {
    Some(error) => Err(error)
    None => {
      let generation = self.core.epoch.snapshot()
      let source = make_source(
        self.core.store,
        self.core.epoch,
        generation,
        initial,
      )
      self.core.close_actions.push(() => source.core.close())
      Ok(source)
    }
  }
}

///|
pub fn[K : Hash + Eq, V] Region::query(
  self : Region,
  compute : (EvalCtx, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError] {
  match self.core.check_open() {
    Some(error) => Err(error)
    None => {
      let generation = self.core.epoch.snapshot()
      let query = make_query(
        self.core.store,
        self.core.epoch,
        generation,
        compute,
      )
      self.core.close_actions.push(() => query.core.close())
      Ok(query)
    }
  }
}

///|
/// Clears owned Source payloads and Query memo/compute state before sealing the
/// Region. A successful close advances ChangeEpoch exactly once, not Revision.
pub fn Region::close(self : Region) -> Result[Unit, RegionError] {
  match self.core.check_open() {
    Some(error) => Err(error)
    None => {
      let preseal = self.core.epoch.snapshot()
      self.core.close_actions.each(action => action())
      self.core.close_actions.clear()
      self.core.epoch.seal()
      ignore(self.core.store.advance_close_epoch())
      self.core.store.wake_selected_mounts([WakeToken::RegionLifetime(preseal)])
      Ok(())
    }
  }
}

///|
pub fn[V] Store::read(self : Store, view : View[V]) -> Result[V, ReadError] {
  evaluate_view(self.core, view).result
}

///|
pub fn Store::id(self : Store) -> StoreId {
  self.core.id
}

///|
pub fn Store::revision(self : Store) -> Revision {
  self.core.current_revision()
}

///|
pub fn Store::change_epoch(self : Store) -> ChangeEpoch {
  self.core.current_change_epoch()
}

///|
pub fn Store::revision_changed_at(self : Store) -> ChangeEpoch {
  self.core.revision_changed_at.val
}

///|
pub fn Store::debug(self : Store) -> StoreDebug {
  let (mount_count, mount_index_edges) = self.core.debug_mounts()
  {
    root_read_attempts: self.core.counters.root_read_attempts,
    root_read_rejections: self.core.counters.root_read_rejections,
    transaction_attempts: self.core.counters.transaction_attempts,
    transaction_commits: self.core.counters.transaction_commits,
    transaction_rollbacks: self.core.counters.transaction_rollbacks,
    last_finished_active_depth: self.core.counters.last_finished_active_depth,
    mount_count,
    active_edge_count: mount_index_edges,
  }
}

///|
pub fn Region::id(self : Region) -> RegionId {
  self.core.epoch.region_id
}

///|
pub fn Region::generation(self : Region) -> RegionGeneration {
  self.core.epoch.snapshot()
}
