///|
/// Semantic equivalence supplied by the result type. Implementations must only
/// return true when every admissible downstream observation is unchanged.
pub(open) trait CutoffEq {
  fn cutoff_equal(Self, Self) -> Bool
}

///|
/// Query-owned semantic propagation policy.
priv enum CutoffPolicy[V] {
  AlwaysChanged
  Compare((V, V) -> Bool)
}

///|
/// Applies one policy only after a successful current recompute.
fn[V] CutoffPolicy::unchanged(
  self : CutoffPolicy[V],
  old : V,
  next : V,
) -> Bool {
  match self {
    AlwaysChanged => false
    Compare(compare) => compare(old, next)
  }
}

///|
/// One keyed memo entry. Dependency traces are owned by this entry and are
/// replaced together with the successful value.
priv struct MemoEntry[V] {
  memo_id : MemoId
  value : V
  last_successful : Array[Dependency]
  last_successful_footprint : Array[WakeToken]
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
  cutoff : Ref[CutoffPolicy[V]?]
  memos : Ref[Map[K, MemoEntry[V]]]
  next_memo : Ref[Int]
  active : Map[K, ActiveInvocation]
  compute_count : Ref[Int]
  cutoff_calls : Ref[Int]
  eviction_attempts : Ref[Int]
  evictions : Ref[Int]
  eviction_noops : Ref[Int]
  eviction_rejections : Ref[Int]
  cache_hits : Ref[Int]
  green_verifications : Ref[Int]
  failed_recomputes : Ref[Int]
}

///|
pub(all) struct Query[K, V] {
  priv core : QueryCore[K, V]
}

///|
fn[K : Hash + Eq, V] make_query_with_cutoff(
  store : StoreCore,
  epoch : RegionEpoch,
  generation : RegionGeneration,
  compute : (EvalCtx, K) -> Result[V, ReadError],
  cutoff : CutoffPolicy[V],
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
      cutoff: Ref(Some(cutoff)),
      memos: Ref(Map([])),
      next_memo: Ref(1),
      active: Map([]),
      compute_count: Ref(0),
      cutoff_calls: Ref(0),
      eviction_attempts: Ref(0),
      evictions: Ref(0),
      eviction_noops: Ref(0),
      eviction_rejections: Ref(0),
      cache_hits: Ref(0),
      green_verifications: Ref(0),
      failed_recomputes: Ref(0),
    },
  }
}

///|
/// Preserves the #463 constructor as the AlwaysChanged baseline.
fn[K : Hash + Eq, V] make_query(
  store : StoreCore,
  epoch : RegionEpoch,
  generation : RegionGeneration,
  compute : (EvalCtx, K) -> Result[V, ReadError],
) -> Query[K, V] {
  make_query_with_cutoff(store, epoch, generation, compute, AlwaysChanged)
}

///|
/// Registers one Query after Region validation.
fn[K : Hash + Eq, V] Region::register_query(
  self : Region,
  compute : (EvalCtx, K) -> Result[V, ReadError],
  cutoff : CutoffPolicy[V],
) -> Result[Query[K, V], RegionError] {
  match self.core.check_open() {
    Some(error) => Err(error)
    None => {
      let query = make_query_with_cutoff(
        self.core.store,
        self.core.epoch,
        self.core.epoch.snapshot(),
        compute,
        cutoff,
      )
      self.core.close_actions.push(() => query.core.close())
      Ok(query)
    }
  }
}

///|
/// Creates a Query whose every successful recompute is semantically changed.
pub fn[K : Hash + Eq, V] Region::query_always_changed(
  self : Region,
  compute : (EvalCtx, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError] {
  self.register_query(compute, AlwaysChanged)
}

///|
/// Creates a Query whose Eq implementation supplies semantic equivalence.
pub fn[K : Hash + Eq, V : Eq] Region::query_eq(
  self : Region,
  compute : (EvalCtx, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError] {
  self.register_query(compute, Compare((old, next) => old == next))
}

///|
/// Creates a Query whose result type owns its semantic equivalence relation.
pub fn[K : Hash + Eq, V : CutoffEq] Region::query_type_owned(
  self : Region,
  compute : (EvalCtx, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError] {
  self.register_query(compute, Compare((old, next) => old.cutoff_equal(next)))
}

///|
fn[K, V] QueryCore::allocate_memo(self : QueryCore[K, V]) -> MemoId {
  let result = MemoId::{ query: self.query_id, sequence: self.next_memo.val }
  self.next_memo.val = self.next_memo.val + 1
  result
}

///|
fn[K, V] QueryCore::verify_dependencies(
  self : QueryCore[K, V],
  ctx : EvalCtx,
  dependencies : Array[Dependency],
  verified_at : ChangeEpoch,
) -> (Bool, Array[WakeToken]) {
  dependencies.fold(init=(true, [WakeToken::RegionLifetime(self.generation)]), (
    state,
    dependency,
  ) => {
    let (all_unchanged, aggregate) = state
    match (dependency.verify)(ctx, verified_at) {
      ProvenUnchanged(changed_at~, footprint~) =>
        (
          all_unchanged && changed_at.value <= verified_at.value,
          union_footprints(aggregate, footprint),
        )
      RecomputeRequired => (false, aggregate)
    }
  })
}

///|
/// Runs one computation in an isolated temporary tracking frame. The frame is
/// published only after the computation succeeds.
fn[K, V] QueryCore::compute_once(
  self : QueryCore[K, V],
  ctx : EvalCtx,
  key : K,
) -> Result[(V, Array[Dependency], Array[WakeToken]), ReadError] {
  match self.compute.val {
    None => Err(ReadError::ClosedRegion(generation=self.generation))
    Some(compute) => {
      self.compute_count.val = self.compute_count.val + 1
      let previous = ctx.session.tracking.val
      let frame = TrackingFrame::{ deps: [], footprint: [] }
      ctx.session.tracking.val = Some(frame)
      let result = compute(ctx, key)
      ctx.session.tracking.val = previous
      match result {
        Ok(value) => Ok((value, frame.deps, frame.footprint))
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
    Ok((value, dependencies, footprint)) => {
      let current = ctx.current_change_epoch()
      let (memo_id, changed_at) = match previous {
        None => (self.allocate_memo(), current)
        Some(entry) => {
          let unchanged = match self.cutoff.val {
            None => false
            Some(policy) => {
              self.cutoff_calls.val = self.cutoff_calls.val + 1
              policy.unchanged(entry.value, value)
            }
          }
          (entry.memo_id, if unchanged { entry.changed_at } else { current })
        }
      }
      self.memos.val[key] = MemoEntry::{
        memo_id,
        value,
        last_successful: dependencies,
        last_successful_footprint: union_footprints(
          [WakeToken::RegionLifetime(self.generation)],
          footprint,
        ),
        verified_at: current,
        changed_at,
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
    None =>
      match self.active.get(key) {
        Some(active) =>
          if active.eval_id == ctx.session.eval_id {
            Err(ReadError::Cycle(ctx.cycle_witness(active, self.query_id)))
          } else {
            self.active.remove(key)
            self.read(ctx, key)
          }
        None => {
          let current = ctx.current_change_epoch()
          match self.memos.val.get(key) {
            Some(entry) if entry.verified_at.value == current.value => {
              self.cache_hits.val = self.cache_hits.val + 1
              Ok(entry.value)
            }
            _ => self.read_slow_active(ctx, key)
          }
        }
      }
  }
}

///|
/// Stale verification and current recompute share one structured active scope.
fn[K : Hash + Eq, V] QueryCore::read_slow_active(
  self : QueryCore[K, V],
  ctx : EvalCtx,
  key : K,
) -> Result[V, ReadError] {
  let active = ctx.enter_active(self.query_id)
  self.active.set(key, active)
  let current = ctx.current_change_epoch()
  let result = match self.memos.val.get(key) {
    None => self.recompute(ctx, key, None)
    Some(entry) => {
      let (green, current_footprint) = self.verify_dependencies(
        ctx,
        entry.last_successful,
        entry.verified_at,
      )
      if green {
        let updated = MemoEntry::{
          memo_id: entry.memo_id,
          value: entry.value,
          last_successful: entry.last_successful,
          last_successful_footprint: current_footprint,
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
  self.active.remove(key)
  ctx.leave_active(active)
  result
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
    Ok(_) =>
      match self.memos.val.get(key) {
        None => RecomputeRequired
        Some(entry) =>
          if entry.changed_at.value > verified_at.value {
            RecomputeRequired
          } else {
            ProvenUnchanged(
              changed_at=entry.changed_at,
              footprint=union_footprints(
                [WakeToken::RegionLifetime(self.generation)],
                entry.last_successful_footprint,
              ),
            )
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
pub fn[K : Hash + Eq, V] Query::at(self : Query[K, V], key : K) -> View[V] {
  let core = self.core
  make_view(
    core.store,
    core.epoch,
    core.generation,
    ViewOrigin::Query(core.query_id),
    ctx => {
      match ctx.eval_query(core, key) {
        Ok(value) =>
          Ok({
            value,
            dependency: {
              verify: (current_ctx, verified_at) => {
                core.verify_dependency(current_ctx, key, verified_at)
              },
              footprint: core.memos.val
              .get(key)
              .map(entry => entry.last_successful_footprint)
              .unwrap_or([]),
            },
            footprint: core.memos.val
            .get(key)
            .map(entry => entry.last_successful_footprint.copy())
            .unwrap_or([]),
          })
        Err(error) => Err(error)
      }
    },
  )
}

///|
/// Returns a typed eviction phase failure without changing either Store clock.
fn eviction_phase_error(requested_store : StoreId) -> EvictionError? {
  match execution_mode.val {
    Idle => None
    Evaluating(active_store, _) =>
      Some(
        EvictionError::EvictionDuringEvaluation(active_store~, requested_store~),
      )
    Transacting(active_store, _) =>
      Some(
        EvictionError::EvictionDuringTransaction(
          active_store~,
          requested_store~,
        ),
      )
  }
}

///|
/// Removes one Eq-equal typed memo entry while preserving the Query recipe.
pub fn[K : Hash + Eq, V] Query::evict_memo(
  self : Query[K, V],
  key : K,
) -> Result[Bool, EvictionError] {
  self.core.eviction_attempts.val = self.core.eviction_attempts.val + 1
  if !self.core.epoch.accepts(self.core.generation) {
    self.core.eviction_rejections.val = self.core.eviction_rejections.val + 1
    Err(EvictionError::ClosedRegion(generation=self.core.generation))
  } else {
    match eviction_phase_error(self.core.store.id) {
      Some(error) => {
        self.core.eviction_rejections.val = self.core.eviction_rejections.val +
          1
        Err(error)
      }
      None =>
        if self.core.memos.val.contains(key) {
          self.core.memos.val.remove(key)
          self.core.evictions.val = self.core.evictions.val + 1
          Ok(true)
        } else {
          self.core.eviction_noops.val = self.core.eviction_noops.val + 1
          Ok(false)
        }
    }
  }
}

///|
fn[K, V] QueryCore::close(self : QueryCore[K, V]) -> Unit {
  self.compute.val = None
  self.cutoff.val = None
  self.memos.val.clear()
  self.active.clear()
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
    cutoff_available: self.core.cutoff.val is Some(_),
    compute_count: self.core.compute_count.val,
    cutoff_calls: self.core.cutoff_calls.val,
    eviction_attempts: self.core.eviction_attempts.val,
    evictions: self.core.evictions.val,
    eviction_noops: self.core.eviction_noops.val,
    eviction_rejections: self.core.eviction_rejections.val,
    memo_count: self.core.memos.val.length(),
    cache_hits: self.core.cache_hits.val,
    green_verifications: self.core.green_verifications.val,
    failed_recomputes: self.core.failed_recomputes.val,
    active_count: self.core.active.length(),
  }
}

///|
/// Returns immutable evidence for one typed memo without exposing its value.
pub fn[K : Hash + Eq, V] Query::memo_debug(
  self : Query[K, V],
  key : K,
) -> MemoDebug? {
  self.core.memos.val
  .get(key)
  .map(entry => MemoDebug::{
    memo_id: entry.memo_id,
    trace_length: entry.last_successful.length(),
    verified_at: entry.verified_at,
    changed_at: entry.changed_at,
  })
}
