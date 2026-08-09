///|
/// One Store. It owns no Region, Source, Query, or View registry.
pub(all) struct Store {
  priv core : StoreCore
}

///|
/// Region owner of Source/Query close actions.
priv struct RegionCore {
  store : StoreCore
  epoch : RegionEpoch
  close_actions : Array[() -> Unit]
}

///|
/// Explicitly closable Region handle.
pub(all) struct Region {
  priv core : RegionCore
}

///|
/// Creates an empty Store at Revision zero.
pub fn Store::Store() -> Store {
  { core: new_store_core() }
}

///|
/// Creates one Region when no evaluation or transaction is active.
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
/// Checks phase and Region lifetime before a definition/lifecycle mutation.
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
/// Creates one Source and registers its close action.
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
/// Creates one memo-free Query and registers its compute-release action.
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
/// Releases Source payloads and Query compute captures, then seals the epoch.
pub fn Region::close(self : Region) -> Result[Unit, RegionError] {
  match self.core.check_open() {
    Some(error) => Err(error)
    None => {
      self.core.close_actions.each(action => action())
      self.core.close_actions.clear()
      self.core.epoch.seal()
      self.core.store.wake_all_mounts()
      Ok(())
    }
  }
}

///|
/// Reads one root under a fresh session capturing exactly one Revision.
pub fn[V] Store::read(self : Store, view : View[V]) -> Result[V, ReadError] {
  evaluate_view(self.core, view).result
}

///|
/// Returns this Store's stable identity.
pub fn Store::id(self : Store) -> StoreId {
  self.core.id
}

///|
/// Returns the current committed Revision.
pub fn Store::revision(self : Store) -> Revision {
  self.core.current_revision()
}

///|
/// Returns an immutable Store counter snapshot.
pub fn Store::debug(self : Store) -> StoreDebug {
  let (mount_count, active_edge_count) = self.core.debug_mounts()
  {
    root_read_attempts: self.core.counters.root_read_attempts,
    root_read_rejections: self.core.counters.root_read_rejections,
    transaction_attempts: self.core.counters.transaction_attempts,
    transaction_commits: self.core.counters.transaction_commits,
    transaction_rollbacks: self.core.counters.transaction_rollbacks,
    last_finished_active_depth: self.core.counters.last_finished_active_depth,
    mount_count,
    active_edge_count,
  }
}

///|
/// Returns this Region's stable identity.
pub fn Region::id(self : Region) -> RegionId {
  self.core.epoch.region_id
}

///|
/// Returns the current Region generation.
pub fn Region::generation(self : Region) -> RegionGeneration {
  self.core.epoch.snapshot()
}
