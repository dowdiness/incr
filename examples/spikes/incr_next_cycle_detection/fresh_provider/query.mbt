///|
/// Fresh Query definition. It owns no memo, trace, cache, or value.
priv struct QueryCore[K, V] {
  store : StoreCore
  generation : RegionGeneration
  epoch : RegionEpoch
  query_id : QueryId
  compute : Ref[((EvalCtx, K) -> Result[V, ReadError])?]
  active : Map[K, ActiveInvocation]
  compute_count : Ref[Int]
}

///|
/// Typed keyed Query definition.
pub(all) struct Query[K, V] {
  priv core : QueryCore[K, V]
}

///|
/// Creates one fresh Query definition.
fn[K : Hash + Eq, V] make_query(
  store : StoreCore,
  epoch : RegionEpoch,
  generation : RegionGeneration,
  compute : (EvalCtx, K) -> Result[V, ReadError],
) -> Query[K, V] {
  {
    core: {
      store,
      generation,
      epoch,
      query_id: QueryId::{ owner: store.id, sequence: store.allocate() },
      compute: Ref(Some(compute)),
      active: Map([]),
      compute_count: Ref(0),
    },
  }
}

///|
/// Evaluates a Query from scratch through one active EvalCtx.
fn[K : Hash + Eq, V] EvalCtx::eval_query(
  self : EvalCtx,
  core : QueryCore[K, V],
  key : K,
) -> Result[V, ReadError] {
  match self.validate_definition(core.store.id, core.epoch, core.generation) {
    Some(error) => Err(error)
    None => core.evaluate_active(self, key)
  }
}

///| Fresh evaluation always enters the typed active map and key-free stack.
fn[K : Hash + Eq, V] QueryCore::evaluate_active(
  self : QueryCore[K, V],
  ctx : EvalCtx,
  key : K,
) -> Result[V, ReadError] {
  match self.active.get(key) {
    Some(active) =>
      if active.eval_id == ctx.session.eval_id {
        Err(ReadError::Cycle(ctx.cycle_witness(active, self.query_id)))
      } else {
        // A prior structured exit must remove this; clear defensively before
        // entering a new single-threaded root session.
        self.active.remove(key)
        self.evaluate_active(ctx, key)
      }
    None => {
      let active = ctx.enter_active(self.query_id)
      self.active.set(key, active)
      let result = match self.compute.val {
        None => Err(ReadError::ClosedRegion(generation=self.generation))
        Some(compute) => {
          self.compute_count.val = self.compute_count.val + 1
          compute(ctx, key)
        }
      }
      self.active.remove(key)
      ctx.leave_active(active)
      result
    }
  }
}

///|
/// Packages typed QueryCore plus K in an opaque EvalCtx recipe.
pub fn[K : Hash + Eq, V] Query::at(self : Query[K, V], key : K) -> View[V] {
  make_view(
    self.core.store,
    self.core.epoch,
    self.core.generation,
    ViewOrigin::Query(self.core.query_id),
    ctx => ctx.eval_query(self.core, key),
  )
}

///|
/// Releases the compute capture during Region close.
fn[K, V] QueryCore::close(self : QueryCore[K, V]) -> Unit {
  self.compute.val = None
  self.active.clear()
}

///|
/// Returns this Query's stable identity.
pub fn[K, V] Query::id(self : Query[K, V]) -> QueryId {
  self.core.query_id
}

///|
/// Returns an immutable Query state snapshot.
pub fn[K, V] Query::debug(self : Query[K, V]) -> QueryDebug {
  {
    query_id: self.core.query_id,
    generation: self.core.generation,
    compute_available: self.core.compute.val is Some(_),
    compute_count: self.core.compute_count.val,
    active_count: self.core.active.length(),
  }
}
