///|
/// One keyed memo entry. Dependency traces are owned by this entry and are
/// replaced together with the successful value.
priv struct MemoEntry[V] {
  memo_id : MemoId
  value : V
  last_successful : Array[Dependency]
  verified_at : ChangeEpoch
  changed_at : ChangeEpoch
}

///|
/// QueryCore owns only its typed memo table and computation state. There is no
/// reverse edge and no erased store-wide registry.
priv struct QueryCore[K, V] {
  store : StoreCore
  generation : RegionGeneration
  epoch : RegionEpoch
  query_id : QueryId
  compute : Ref[((EvalCtx, K) -> Result[V, ReadError])?]
  memos : Ref[Map[K, MemoEntry[V]]]
  next_memo : Ref[Int]
  compute_count : Ref[Int]
  cache_hits : Ref[Int]
  green_verifications : Ref[Int]
  failed_recomputes : Ref[Int]
}

///|
pub(all) struct Query[K, V] {
  priv core : QueryCore[K, V]
}

///|
fn[K : Hash + Eq, V] make_query(
  store : StoreCore,
  epoch : RegionEpoch,
  generation : RegionGeneration,
  compute : (EvalCtx, K) -> Result[V, ReadError],
) -> Query[K, V] {
  let query_id = QueryId::{
    owner: store.id,
    sequence: store.allocate_definition(),
  }
  {
    core: {
      store,
      generation,
      epoch,
      query_id,
      compute: Ref(Some(compute)),
      memos: Ref(Map([])),
      next_memo: Ref(1),
      compute_count: Ref(0),
      cache_hits: Ref(0),
      green_verifications: Ref(0),
      failed_recomputes: Ref(0),
    },
  }
}

///|
fn[K, V] QueryCore::allocate_memo(
  self : QueryCore[K, V],
) -> MemoId {
  let result = MemoId::{
    query: self.query_id,
    sequence: self.next_memo.val,
  }
  self.next_memo.val = self.next_memo.val + 1
  result
}

///|
fn[K, V] QueryCore::verify_dependencies(
  _self : QueryCore[K, V],
  ctx : EvalCtx,
  dependencies : Array[Dependency],
  verified_at : ChangeEpoch,
) -> Bool {
  dependencies.fold(init=true, (all_unchanged, dependency) => {
    let this_unchanged = match (dependency.verify)(ctx, verified_at) {
      ProvenUnchanged(changed_at) => changed_at.value <= verified_at.value
      RecomputeRequired => false
    }
    all_unchanged && this_unchanged
  })
}

///|
/// Runs one computation in an isolated temporary tracking frame. The frame is
/// published only after the computation succeeds.
fn[K, V] QueryCore::compute_once(
  self : QueryCore[K, V],
  ctx : EvalCtx,
  key : K,
) -> Result[(V, Array[Dependency]), ReadError] {
  match self.compute.val {
    None => Err(ReadError::ClosedRegion(generation=self.generation))
    Some(compute) => {
      self.compute_count.val = self.compute_count.val + 1
      let previous = ctx.session.tracking.val
      let frame = TrackingFrame::{ deps: [] }
      ctx.session.tracking.val = Some(frame)
      let result = compute(ctx, key)
      ctx.session.tracking.val = previous
      match result {
        Ok(value) => Ok((value, frame.deps))
        Err(error) => Err(error)
      }
    }
  }
}

///|
fn[K : Hash + Eq, V] QueryCore::recompute(
  self : QueryCore[K, V],
  ctx : EvalCtx,
  key : K,
  previous : MemoEntry[V]?,
) -> Result[V, ReadError] {
  match self.compute_once(ctx, key) {
    Err(error) => {
      self.failed_recomputes.val = self.failed_recomputes.val + 1
      Err(error)
    }
    Ok((value, dependencies)) => {
      let memo_id = match previous {
        Some(entry) => entry.memo_id
        None => self.allocate_memo()
      }
      self.memos.val[key] = MemoEntry::{
        memo_id,
        value,
        last_successful: dependencies,
        verified_at: ctx.current_change_epoch(),
        changed_at: ctx.current_change_epoch(),
      }
      Ok(self.memos.val[key].value)
    }
  }
}

///|
fn[K : Hash + Eq, V] QueryCore::read(
  self : QueryCore[K, V],
  ctx : EvalCtx,
  key : K,
) -> Result[V, ReadError] {
  match ctx.validate_definition(self.store.id, self.epoch, self.generation) {
    Some(error) => Err(error)
    None => {
      let current = ctx.current_change_epoch()
      match self.memos.val.get(key) {
        None => self.recompute(ctx, key, None)
        Some(entry) => {
          if entry.verified_at.value == current.value {
            self.cache_hits.val = self.cache_hits.val + 1
            Ok(entry.value)
          } else if self.verify_dependencies(
            ctx,
            entry.last_successful,
            entry.verified_at,
          ) {
            let updated = MemoEntry::{
              memo_id: entry.memo_id,
              value: entry.value,
              last_successful: entry.last_successful,
              verified_at: current,
              changed_at: entry.changed_at,
            }
            self.memos.val[key] = updated
            self.green_verifications.val = self.green_verifications.val + 1
            Ok(updated.value)
          } else {
            self.recompute(ctx, key, Some(entry))
          }
        }
      }
    }
  }
}

///|
/// Verifies an upstream Query directly. Errors and closed definitions are
/// collapsed to RecomputeRequired and never leak into an old parent result.
fn[K : Hash + Eq, V] QueryCore::verify_dependency(
  self : QueryCore[K, V],
  ctx : EvalCtx,
  key : K,
  verified_at : ChangeEpoch,
) -> Verification {
  match self.read(ctx, key) {
    Err(_) => RecomputeRequired
    Ok(_) => match self.memos.val.get(key) {
      None => RecomputeRequired
      Some(entry) =>
        if entry.changed_at.value > verified_at.value {
          RecomputeRequired
        } else {
          ProvenUnchanged(entry.changed_at)
        }
    }
  }
}

///|
fn[K : Hash + Eq, V] EvalCtx::eval_query(
  self : EvalCtx,
  core : QueryCore[K, V],
  key : K,
) -> Result[V, ReadError] {
  core.read(self, key)
}

///|
pub fn[K : Hash + Eq, V] Query::at(
  self : Query[K, V],
  key : K,
) -> View[V] {
  let core = self.core
  make_view(
    core.store,
    core.epoch,
    core.generation,
    ViewOrigin::Query(core.query_id),
    ctx => match ctx.eval_query(core, key) {
      Ok(value) => Ok({
        value,
        dependency: {
          verify: (current_ctx, verified_at) =>
            core.verify_dependency(current_ctx, key, verified_at),
        },
      })
      Err(error) => Err(error)
    },
  )
}

///|
fn[K, V] QueryCore::close(self : QueryCore[K, V]) -> Unit {
  self.compute.val = None
  self.memos.val.clear()
}

///|
pub fn[K, V] Query::id(self : Query[K, V]) -> QueryId {
  self.core.query_id
}

///|
pub fn[K, V] Query::debug(self : Query[K, V]) -> QueryDebug {
  {
    query_id: self.core.query_id,
    generation: self.core.generation,
    compute_available: self.core.compute.val is Some(_),
    compute_count: self.core.compute_count.val,
    memo_count: self.core.memos.val.length(),
    cache_hits: self.core.cache_hits.val,
    green_verifications: self.core.green_verifications.val,
    failed_recomputes: self.core.failed_recomputes.val,
  }
}

///| Returns immutable evidence for one typed memo without exposing its value.
pub fn[K : Hash + Eq, V] Query::memo_debug(
  self : Query[K, V],
  key : K,
) -> MemoDebug? {
  self.core.memos.val.get(key).map(entry => MemoDebug::{
    memo_id: entry.memo_id,
    trace_length: entry.last_successful.length(),
    verified_at: entry.verified_at,
    changed_at: entry.changed_at,
  })
}
