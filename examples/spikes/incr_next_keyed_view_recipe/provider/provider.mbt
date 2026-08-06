///|
/// Allocator for distinct StoreIds; it is not a query/view/memo registry.
let next_store_id : Ref[Int] = Ref(0)

///|
/// A store-local identity, distinct from every other identity type.
pub(all) struct StoreId {
  priv value : Int
} derive(Eq, Debug)

///|
/// Identity of one Region.
pub(all) struct RegionId {
  priv owner : StoreId
  priv sequence : Int
} derive(Eq, Debug)

///|
/// Identity of one keyed Query definition.
pub(all) struct QueryId {
  priv owner : StoreId
  priv sequence : Int
} derive(Eq, Debug)

///|
/// Identity of one View recipe handle.
pub(all) struct ViewHandleId {
  priv owner : StoreId
  priv sequence : Int
} derive(Eq, Debug)

///|
/// Identity of one materialized memo entry.
pub(all) struct MemoId {
  priv query : QueryId
  priv sequence : Int
} derive(Eq, Debug)

///|
/// Region identity plus the lifetime epoch captured by a Query and its Views.
pub(all) struct RegionGeneration {
  priv region : RegionId
  priv epoch : Int
} derive(Eq, Debug)

///|
/// Structured read failures produced before recipe execution when possible.
pub(all) enum ReadError {
  CrossStore(view_store~ : StoreId, reader_store~ : StoreId)
  ClosedRegion(generation~ : RegionGeneration)
} derive(Eq, Debug)

///|
/// Immutable snapshot of Store read-boundary counters.
pub(all) struct StoreDebug {
  metadata_checks : Int
  cross_store_rejections : Int
  closed_region_rejections : Int
  recipe_invocations : Int
}

///|
/// Immutable snapshot of one Query's typed memo and lifecycle state.
pub(all) struct QueryDebug {
  query_id : QueryId
  creation_generation : RegionGeneration
  memo_count : Int
  lookup_count : Int
  materialization_count : Int
  eviction_count : Int
  next_memo_sequence : Int
  closed : Bool
}

///|
/// A read-only recipe-backed View. It has no public get/read/call surface.
pub(all) struct View[V] {
  priv metadata : ViewMetadata
  priv recipe : () -> Result[V, ReadError]
}

///|
/// Comparison B exposes K in its type and stores QueryCore plus K directly.
pub(all) struct ExplicitView[K, V] {
  priv metadata : ViewMetadata
  priv query : QueryCore[K, V]
  priv key : K
}

///|
/// A keyed Query definition which owns typed memo entries.
pub(all) struct Query[K, V] {
  priv core : QueryCore[K, V]
}

///|
/// A Store owns identity/allocation and read-boundary counters only.
pub(all) struct Store {
  priv core : StoreCore
  priv counters : StoreCounters
}

///|
/// A Region owns query close actions and a shared generation epoch.
pub(all) struct Region {
  priv core : RegionCore
}

///|
/// Evaluation context with the same explicit View read boundary.
pub(all) struct EvalCtx {
  priv store : Store
}

///|
/// A deliberately mutable key used only to demonstrate the caller contract.
pub(all) struct MutableKey {
  priv value : Ref[Int]
}

///|
/// Shared epoch referenced by metadata and QueryCore, never back to RegionCore.
priv struct RegionEpoch {
  value : Ref[Int]
}

///|
/// Store identity and allocation only; it owns no Region or Query.
priv struct StoreCore {
  id : StoreId
  mut next_local_id : Int
}

///|
/// Mutable counters hidden behind immutable StoreDebug snapshots.
priv struct StoreCounters {
  mut metadata_checks : Int
  mut cross_store_rejections : Int
  mut closed_region_rejections : Int
  mut recipe_invocations : Int
}

///|
/// Region lifecycle state and heterogeneous Query close actions.
priv struct RegionCore {
  owner : StoreId
  region_id : RegionId
  allocator : StoreCore
  epoch : RegionEpoch
  mut closed : Bool
  close_actions : Array[() -> Unit]
}

///|
/// Metadata inspected before A's recipe or B's QueryCore is invoked.
priv struct ViewMetadata {
  owner : StoreId
  query_id : QueryId
  generation : RegionGeneration
  epoch : RegionEpoch
  view_id : ViewHandleId
}

///|
/// Typed memo payload owned by exactly one QueryCore map entry.
priv struct MemoEntry[V] {
  memo_id : MemoId
  mut payload : V?
}

///|
/// Query-owned typed table. It has no RegionCore or View edge.
priv struct QueryCore[K, V] {
  owner : StoreId
  creation_generation : RegionGeneration
  region_epoch : RegionEpoch
  query_id : QueryId
  allocator : StoreCore
  memo : Map[K, MemoEntry[V]]
  mut compute : ((K) -> V)?
  mut next_memo_sequence : Int
  mut lookup_count : Int
  mut materialization_count : Int
  mut eviction_count : Int
  mut closed : Bool
}

///|
/// Creates a Store with no Region or Query registry.
pub fn Store::Store() -> Store {
  next_store_id.val = next_store_id.val + 1
  let id = StoreId::{ value: next_store_id.val }
  {
    core: StoreCore::{ id, next_local_id: 1 },
    counters: StoreCounters::{
      metadata_checks: 0,
      cross_store_rejections: 0,
      closed_region_rejections: 0,
      recipe_invocations: 0,
    },
  }
}

///|
/// Allocates one Store-local identity number.
fn StoreCore::allocate(self : StoreCore) -> Int {
  let id = self.next_local_id
  self.next_local_id = self.next_local_id + 1
  id
}

///|
/// Creates an independently closable Region.
pub fn Store::region(self : Store) -> Region {
  let region_id = RegionId::{
    owner: self.core.id,
    sequence: self.core.allocate(),
  }
  {
    core: RegionCore::{
      owner: self.core.id,
      region_id,
      allocator: self.core,
      epoch: RegionEpoch::{ value: Ref(0) },
      closed: false,
      close_actions: [],
    },
  }
}

///|
/// Returns the Region's current generation.
fn RegionCore::generation(self : RegionCore) -> RegionGeneration {
  RegionGeneration::{ region: self.region_id, epoch: self.epoch.value.val }
}

///|
/// Creates a typed keyed Query without materializing any key.
pub fn[K : Hash + Eq, V] Region::query(
  self : Region,
  compute : (K) -> V,
) -> Query[K, V] {
  guard !self.core.closed else { abort("Region::query called after close") }
  let query_id = QueryId::{
    owner: self.core.owner,
    sequence: self.core.allocator.allocate(),
  }
  let core : QueryCore[K, V] = {
    owner: self.core.owner,
    creation_generation: self.core.generation(),
    region_epoch: self.core.epoch,
    query_id,
    allocator: self.core.allocator,
    memo: Map([]),
    compute: Some(compute),
    next_memo_sequence: 1,
    lookup_count: 0,
    materialization_count: 0,
    eviction_count: 0,
    closed: false,
  }
  self.core.close_actions.push(() => core.close())
  { core, }
}

///|
/// Allocates a ViewHandleId without looking up or materializing a memo.
fn[K, V] QueryCore::allocate_view_id(self : QueryCore[K, V]) -> ViewHandleId {
  ViewHandleId::{ owner: self.owner, sequence: self.allocator.allocate() }
}

///|
/// Creates A by existentially packaging typed QueryCore and K in a closure.
fn[K : Hash + Eq, V] QueryCore::view(
  self : QueryCore[K, V],
  key : K,
) -> View[V] {
  let metadata = ViewMetadata::{
    owner: self.owner,
    query_id: self.query_id,
    generation: self.creation_generation,
    epoch: self.region_epoch,
    view_id: self.allocate_view_id(),
  }
  View::{ metadata, recipe: () => self.materialize(key) }
}

///|
/// Creates B with direct typed fields and no recipe closure.
fn[K, V] QueryCore::explicit_view(
  self : QueryCore[K, V],
  key : K,
) -> ExplicitView[K, V] {
  let metadata = ViewMetadata::{
    owner: self.owner,
    query_id: self.query_id,
    generation: self.creation_generation,
    epoch: self.region_epoch,
    view_id: self.allocate_view_id(),
  }
  ExplicitView::{ metadata, query: self, key }
}

///|
/// Creates A without memo lookup or materialization.
pub fn[K : Hash + Eq, V] Query::at(self : Query[K, V], key : K) -> View[V] {
  self.core.view(key)
}

///|
/// Creates comparison B without memo lookup or materialization.
pub fn[K, V] Query::at_explicit(
  self : Query[K, V],
  key : K,
) -> ExplicitView[K, V] {
  self.core.explicit_view(key)
}

///|
/// Materializes or reuses one typed memo entry.
fn[K : Hash + Eq, V] QueryCore::materialize(
  self : QueryCore[K, V],
  key : K,
) -> Result[V, ReadError] {
  if self.closed ||
    self.region_epoch.value.val != self.creation_generation.epoch {
    return Err(ReadError::ClosedRegion(generation=self.creation_generation))
  }
  self.lookup_count = self.lookup_count + 1
  match self.memo.get(key) {
    Some(entry) =>
      match entry.payload {
        Some(value) => Ok(value)
        None =>
          Err(ReadError::ClosedRegion(generation=self.creation_generation))
      }
    None => {
      let compute = match self.compute {
        Some(compute) => compute
        None =>
          return Err(
            ReadError::ClosedRegion(generation=self.creation_generation),
          )
      }
      let value = compute(key)
      let memo_id = MemoId::{
        query: self.query_id,
        sequence: self.next_memo_sequence,
      }
      self.next_memo_sequence = self.next_memo_sequence + 1
      self.materialization_count = self.materialization_count + 1
      self.memo.set(key, MemoEntry::{ memo_id, payload: Some(value) })
      Ok(value)
    }
  }
}

///|
/// Clears the compute closure and every memo payload on Region close.
fn[K, V] QueryCore::close(self : QueryCore[K, V]) -> Unit {
  if self.closed {
    return
  }
  self.compute = None
  self.memo.each((key, entry) => {
    ignore(key)
    entry.payload = None
  })
  self.memo.clear()
  self.closed = true
}

///|
/// Closes every Query, clears close actions, then advances the Region epoch.
pub fn Region::close(self : Region) -> Unit {
  if self.core.closed {
    return
  }
  self.core.close_actions.each(action => action())
  self.core.close_actions.clear()
  self.core.closed = true
  self.core.epoch.value.val = self.core.epoch.value.val + 1
}

///|
/// Checks owner and generation before recipe invocation or Query lookup.
fn Store::validate(self : Store, metadata : ViewMetadata) -> ReadError? {
  self.counters.metadata_checks = self.counters.metadata_checks + 1
  if metadata.owner != self.core.id {
    self.counters.cross_store_rejections = self.counters.cross_store_rejections +
      1
    return Some(
      ReadError::CrossStore(
        view_store=metadata.owner,
        reader_store=self.core.id,
      ),
    )
  }
  let current_generation = RegionGeneration::{
    region: metadata.generation.region,
    epoch: metadata.epoch.value.val,
  }
  if current_generation != metadata.generation {
    self.counters.closed_region_rejections = self.counters.closed_region_rejections +
      1
    return Some(ReadError::ClosedRegion(generation=metadata.generation))
  }
  None
}

///|
/// Reads A only through the Store's metadata-first boundary.
pub fn[V] Store::read(self : Store, view : View[V]) -> Result[V, ReadError] {
  match self.validate(view.metadata) {
    Some(error) => Err(error)
    None => {
      self.counters.recipe_invocations = self.counters.recipe_invocations + 1
      (view.recipe)()
    }
  }
}

///|
/// Reads B through direct typed fields after the same metadata checks.
pub fn[K : Hash + Eq, V] Store::read_explicit(
  self : Store,
  view : ExplicitView[K, V],
) -> Result[V, ReadError] {
  match self.validate(view.metadata) {
    Some(error) => Err(error)
    None => {
      self.counters.recipe_invocations = self.counters.recipe_invocations + 1
      view.query.materialize(view.key)
    }
  }
}

///|
/// Creates an evaluation context for one Store.
pub fn EvalCtx::EvalCtx(store : Store) -> EvalCtx {
  { store, }
}

///|
/// Reads A through EvalCtx using the same metadata-first boundary.
pub fn[V] EvalCtx::read(self : EvalCtx, view : View[V]) -> Result[V, ReadError] {
  self.store.read(view)
}

///|
/// Reads B explicitly because same-receiver argument overloading is unavailable.
pub fn[K : Hash + Eq, V] EvalCtx::read_explicit(
  self : EvalCtx,
  view : ExplicitView[K, V],
) -> Result[V, ReadError] {
  self.store.read_explicit(view)
}

///|
/// Returns an immutable Store counter snapshot.
pub fn Store::debug(self : Store) -> StoreDebug {
  {
    metadata_checks: self.counters.metadata_checks,
    cross_store_rejections: self.counters.cross_store_rejections,
    closed_region_rejections: self.counters.closed_region_rejections,
    recipe_invocations: self.counters.recipe_invocations,
  }
}

///|
/// Returns immutable Query counters and identities.
pub fn[K, V] Query::debug(self : Query[K, V]) -> QueryDebug {
  {
    query_id: self.core.query_id,
    creation_generation: self.core.creation_generation,
    memo_count: self.core.memo.length(),
    lookup_count: self.core.lookup_count,
    materialization_count: self.core.materialization_count,
    eviction_count: self.core.eviction_count,
    next_memo_sequence: self.core.next_memo_sequence,
    closed: self.core.closed,
  }
}

///|
/// Returns the current MemoId for debug evidence.
pub fn[K : Hash + Eq, V] Query::memo_id(self : Query[K, V], key : K) -> MemoId? {
  self.core.memo.get(key).map(entry => entry.memo_id)
}

///|
/// Evicts a key so a surviving View can rematerialize it with a new MemoId.
pub fn[K : Hash + Eq, V] Query::evict(self : Query[K, V], key : K) -> Unit {
  if self.core.memo.contains(key) {
    self.core.memo.remove(key)
    self.core.eviction_count = self.core.eviction_count + 1
  }
}

///|
/// Returns A's stable QueryId.
pub fn[V] View::query_id(self : View[V]) -> QueryId {
  self.metadata.query_id
}

///|
/// Returns A's distinct ViewHandleId.
pub fn[V] View::handle_id(self : View[V]) -> ViewHandleId {
  self.metadata.view_id
}

///|
/// Returns A's captured RegionGeneration.
pub fn[V] View::generation(self : View[V]) -> RegionGeneration {
  self.metadata.generation
}

///|
/// Returns B's distinct ViewHandleId.
pub fn[K, V] ExplicitView::handle_id(self : ExplicitView[K, V]) -> ViewHandleId {
  self.metadata.view_id
}

///|
/// Returns B's QueryId.
pub fn[K, V] ExplicitView::query_id(self : ExplicitView[K, V]) -> QueryId {
  self.query.query_id
}

///|
/// Returns B's captured RegionGeneration.
pub fn[K, V] ExplicitView::generation(
  self : ExplicitView[K, V],
) -> RegionGeneration {
  self.metadata.generation
}

///|
/// Creates a mutable key for the caller-contract counterexample.
pub fn MutableKey::MutableKey(value : Int) -> MutableKey {
  { value: Ref(value) }
}

///|
/// Mutates a key after it has been used as a Map key.
pub fn MutableKey::set(self : MutableKey, value : Int) -> Unit {
  self.value.val = value
}

///|
/// Reads the current mutable key value.
pub fn MutableKey::value(self : MutableKey) -> Int {
  self.value.val
}

///|
/// Returns the numeric StoreId component for evidence output.
pub fn StoreId::value(self : StoreId) -> Int {
  self.value
}

///|
/// Returns QueryId's Store provenance.
pub fn QueryId::store_id(self : QueryId) -> StoreId {
  self.owner
}

///|
/// Returns QueryId's Store-local component.
pub fn QueryId::sequence(self : QueryId) -> Int {
  self.sequence
}

///|
/// Returns ViewHandleId's Store provenance.
pub fn ViewHandleId::store_id(self : ViewHandleId) -> StoreId {
  self.owner
}

///|
/// Returns ViewHandleId's Store-local component.
pub fn ViewHandleId::sequence(self : ViewHandleId) -> Int {
  self.sequence
}

///|
/// Returns MemoId's Query identity.
pub fn MemoId::query_id(self : MemoId) -> QueryId {
  self.query
}

///|
/// Returns MemoId's Query-local component.
pub fn MemoId::sequence(self : MemoId) -> Int {
  self.sequence
}

///|
/// Returns RegionGeneration's Region identity.
pub fn RegionGeneration::region_id(self : RegionGeneration) -> RegionId {
  self.region
}

///|
/// Returns RegionGeneration's epoch number.
pub fn RegionGeneration::epoch(self : RegionGeneration) -> Int {
  self.epoch
}

///|
/// Returns RegionId's Store provenance.
pub fn RegionId::store_id(self : RegionId) -> StoreId {
  self.owner
}

///|
/// Returns RegionId's Store-local component.
pub fn RegionId::sequence(self : RegionId) -> Int {
  self.sequence
}

///|
/// Hashes a mutable key from its current value; later mutation is invalid.
pub impl Hash for MutableKey with fn hash(self) {
  self.value.val.hash()
}

///|
/// Combines a mutable key hash from its current value.
pub impl Hash for MutableKey with fn hash_combine(self, hasher) {
  self.value.val.hash_combine(hasher)
}

///|
/// Compares a mutable key from its current value; later mutation is invalid.
pub impl Eq for MutableKey with fn equal(self, other) -> Bool {
  self.value.val == other.value.val
}
