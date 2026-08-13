///|
/// Fresh Query definition. K1.1 deliberately stores no memo or trace.
priv struct QueryCore[K, V] {
  owner : StoreId
  generation : RegionGeneration
  epoch : RegionEpoch
  compute : Ref[((QueryContext, K) -> Result[V, ReadError])?]
}

///|
/// A typed keyed Query recipe.
pub struct Query[K, V] {
  priv core : QueryCore[K, V]
}

///|
fn[K, V] QueryContext::eval_query(
  self : QueryContext,
  core : QueryCore[K, V],
  key : K,
) -> Result[V, ReadError] {
  match self.expired() {
    Some(error) => Err(error)
    None =>
      if core.owner != self.session.owner {
        Err(
          ReadError::CrossStore(
            view_store=core.owner,
            reader_store=self.session.owner,
          ),
        )
      } else if !core.epoch.accepts(core.generation) {
        Err(ReadError::ClosedRegion(generation=core.generation))
      } else {
        match core.compute.val {
          None => Err(ReadError::ClosedRegion(generation=core.generation))
          Some(compute) => compute(self, key)
        }
      }
  }
}

///|
/// Creates a no-memo Query in this Region.
pub fn[K, V] Region::query(
  self : Region,
  compute : (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError] {
  match self.check_open() {
    Some(error) => Err(error)
    None => {
      let core : QueryCore[K, V] = {
        owner: self.owner,
        generation: self.epoch.snapshot(),
        epoch: self.epoch,
        compute: Ref(Some(compute)),
      }
      let query = Query::{ core, }
      self.close_actions.push(() => query.core.compute.val = None)
      Ok(query)
    }
  }
}

///|
/// Captures a typed key in one opaque, non-callable View.
pub fn[K, V] Query::at(self : Query[K, V], key : K) -> View[V] {
  {
    owner: self.core.owner,
    generation: self.core.generation,
    recipe: ctx => ctx.eval_query(self.core, key),
  }
}
